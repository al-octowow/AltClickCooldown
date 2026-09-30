ACC_Channel = "AUTO"

local function ACC_FormatTime(seconds)
    if seconds <= 0 then
        return "READY"
    end

    seconds = math.ceil(seconds)

    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local remainder = math.mod(seconds, 3600)
        local m = math.floor(remainder / 60)
        return string.format("%dh %02dm", h, m)
    elseif seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = math.mod(seconds, 60)
        return string.format("%dm %02ds", m, s)
    else
        return string.format("%ds", seconds)
    end
end

local function ACC_GetChannel()
    if ACC_Channel == "PARTY" then
        return "PARTY"
    elseif ACC_Channel == "RAID" then
        return "RAID"
    elseif ACC_Channel == "SAY" then
        return "SAY"
    elseif ACC_Channel == "SELF" then
        return "SELF"
    end

    if GetNumRaidMembers() > 0 then
        return "RAID"
    elseif GetNumPartyMembers() > 0 then
        return "PARTY"
    end

    return "SELF"
end

local function ACC_Send(message)
    local channel = ACC_GetChannel()

    if channel == "SELF" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAltClickCooldown:|r " .. message)
    else
        SendChatMessage(message, channel)
    end
end

local function ACC_GetActionName(slot)
    local name

    if GetActionText then
        name = GetActionText(slot)
        if name and name ~= "" then
            return name
        end
    end

    if GameTooltip and GameTooltip.SetAction then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetAction(slot)

        local line = getglobal("GameTooltipTextLeft1")
        if line then
            name = line:GetText()
        end

        GameTooltip:Hide()
    end

    if name and name ~= "" then
        return name
    end

    return "Action " .. tostring(slot)
end

local function ACC_AnnounceAction(slot)
    if not slot then
        return
    end

    local start, duration, enable = GetActionCooldown(slot)

    if not start or not duration then
        ACC_Send(ACC_GetActionName(slot) .. ": cooldown unavailable")
        return
    end

    local remaining = 0

    if start > 0 and duration > 0 then
        remaining = (start + duration) - GetTime()

        if remaining < 0 then
            remaining = 0
        end
    end

    ACC_Send(ACC_GetActionName(slot) .. ": " .. ACC_FormatTime(remaining))
end

local function ACC_HookButton(button)
    if not button or not button.GetScript or not button.SetScript then
        return
    end

    if button.ACC_Hooked then
        return
    end

    local oldClick = button:GetScript("OnClick")

    if type(oldClick) ~= "function" then
        return
    end

    button.ACC_Hooked = true
    button.ACC_OriginalOnClick = oldClick

    button:SetScript("OnClick", function()
        -- PFUI uses Alt for self-casting, so this check must happen before
        -- the original PFUI handler is allowed to run.
        if arg1 == "LeftButton" and IsAltKeyDown() then
            -- PFUI stores the CURRENT action slot in button.id. This is
            -- especially important for its paging bar.
            if this.bar and this.bar == 11 then
                -- Stance bar is not a normal action cooldown.
                local start, duration, enable = GetShapeshiftFormCooldown(this.id)
                if start and duration then
                    local remaining = 0
                    if start > 0 and duration > 0 then
                        remaining = (start + duration) - GetTime()
                        if remaining < 0 then remaining = 0 end
                    end
                    ACC_Send("Stance " .. tostring(this.id) .. ": " .. ACC_FormatTime(remaining))
                end
            elseif this.bar and this.bar == 12 then
                -- Pet actions have their own cooldown API.
                local start, duration, enable = GetPetActionCooldown(this.id)
                if start and duration then
                    local remaining = 0
                    if start > 0 and duration > 0 then
                        remaining = (start + duration) - GetTime()
                        if remaining < 0 then remaining = 0 end
                    end
                    ACC_Send("Pet Action " .. tostring(this.id) .. ": " .. ACC_FormatTime(remaining))
                end
            else
                ACC_AnnounceAction(this.id)
            end
            return
        end

        -- Preserve PFUI's exact normal click behavior.
        return oldClick()
    end)
end

local pfBars = {
    "Main",
    "Paging",
    "Right",
    "Vertical",
    "Left",
    "Top",
    "StanceBar1",
    "StanceBar2",
    "StanceBar3",
    "StanceBar4",
    "Stances",
    "Pet",
}

local function ACC_HookPFUI()
    local hooked = 0
    local barIndex, buttonIndex

    for barIndex = 1, table.getn(pfBars) do
        local prefix = "pfActionBar" .. pfBars[barIndex] .. "Button"

        for buttonIndex = 1, 12 do
            local button = getglobal(prefix .. buttonIndex)

            if button then
                local before = button.ACC_Hooked
                ACC_HookButton(button)
                if not before and button.ACC_Hooked then
                    hooked = hooked + 1
                end
            end
        end
    end

    return hooked
end

local function ACC_HookBlizzard()
    local i

    for i = 1, 12 do
        local button = getglobal("ActionButton" .. i)
        if button then
            ACC_HookButton(button)
        end

        button = getglobal("MultiBarBottomLeftButton" .. i)
        if button then ACC_HookButton(button) end

        button = getglobal("MultiBarBottomRightButton" .. i)
        if button then ACC_HookButton(button) end

        button = getglobal("MultiBarRightButton" .. i)
        if button then ACC_HookButton(button) end

        button = getglobal("MultiBarLeftButton" .. i)
        if button then ACC_HookButton(button) end

        button = getglobal("BonusActionButton" .. i)
        if button then ACC_HookButton(button) end
    end
end

local function ACC_HookAll()
    ACC_HookBlizzard()

    -- PFUI creates its buttons during its actionbar module initialization.
    ACC_HookPFUI()
end

local frame = CreateFrame("Frame", "AltClickCooldownFrame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")

frame:SetScript("OnEvent", function()
    -- Run after login and whenever another addon finishes loading. This
    -- catches pfUI regardless of addon load order.
    ACC_HookAll()
end)

SLASH_ALTCLICKCOOLDOWN1 = "/acc"

SlashCmdList["ALTCLICKCOOLDOWN"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "party" then
        ACC_Channel = "PARTY"
        DEFAULT_CHAT_FRAME:AddMessage("AltClickCooldown: channel set to PARTY.")
    elseif msg == "raid" then
        ACC_Channel = "RAID"
        DEFAULT_CHAT_FRAME:AddMessage("AltClickCooldown: channel set to RAID.")
    elseif msg == "say" then
        ACC_Channel = "SAY"
        DEFAULT_CHAT_FRAME:AddMessage("AltClickCooldown: channel set to SAY.")
    elseif msg == "self" then
        ACC_Channel = "SELF"
        DEFAULT_CHAT_FRAME:AddMessage("AltClickCooldown: channel set to SELF.")
    elseif msg == "reset" or msg == "auto" then
        ACC_Channel = "AUTO"
        DEFAULT_CHAT_FRAME:AddMessage("AltClickCooldown: channel set to AUTO.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAltClickCooldown commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("/acc party - announce to party")
        DEFAULT_CHAT_FRAME:AddMessage("/acc raid  - announce to raid")
        DEFAULT_CHAT_FRAME:AddMessage("/acc say   - announce in say")
        DEFAULT_CHAT_FRAME:AddMessage("/acc self  - only show locally")
        DEFAULT_CHAT_FRAME:AddMessage("/acc reset - automatic channel")
    end
end
