local _, ns = ...

local Scanner = {
    scanning = false,
    matchCount = 0,
    lastMatchSender = nil,
    lastMatchStamp = nil,
    -- True while the client withholds chat text from addons, see the OnEvent handler.
    chatLocked = false,
}
ns.Scanner = Scanner

local keywordGroups = {}
local recentMatches = {}
local lastSoundTime = 0
local listeners = {}
local eventFrame = CreateFrame("Frame")

-- Lets the panel and minimap tooltip follow scan state without the scanner knowing about frames.
function Scanner.OnChanged(callback)
    listeners[#listeners + 1] = callback
end

local function fireChanged()
    for _, callback in ipairs(listeners) do callback() end
end

-- One row is an OR group; commas inside a row separate AND terms. Terms are lowercased once here.
function Scanner.ReloadKeywords()
    keywordGroups = {}
    for _, row in ipairs(ns.Store.Get().keywords) do
        local terms = {}
        for raw in row:gmatch("[^,]+") do
            local term = ns.trim(raw)
            if term ~= "" then terms[#terms + 1] = strlower(term) end
        end
        if #terms > 0 then keywordGroups[#keywordGroups + 1] = terms end
    end
end

local function matchesKeywords(text)
    local lower = strlower(text)
    for _, terms in ipairs(keywordGroups) do
        local all = true
        for _, term in ipairs(terms) do
            if not strfind(lower, term, 1, true) then
                all = false
                break
            end
        end
        if all then return true end
    end
    return false
end

local function isDuplicate(sender, msg)
    local now = GetTime()
    local key = sender .. "\031" .. msg
    for i = #recentMatches, 1, -1 do
        local entry = recentMatches[i]
        if now - entry.t > ns.DEDUP_TTL then
            table.remove(recentMatches, i)
        elseif entry.k == key then
            return true
        end
    end
    recentMatches[#recentMatches + 1] = { k = key, t = now }
    if #recentMatches > ns.DEDUP_MAX then table.remove(recentMatches, 1) end
    return false
end

-- Chat windows a match may be delivered to, skipping the combat log.
function Scanner.OutputWindows()
    local windows = {}
    for i = 1, Constants.ChatFrameConstants.MaxChatWindows do
        local name = GetChatWindowInfo(i)
        if i ~= ns.COMBAT_LOG_INDEX and name and name ~= "" then
            windows[#windows + 1] = { index = i, name = name, key = strlower(name) }
        end
    end
    return windows
end

-- Falls back to the default chat frame when no output tab is picked, and flashes background tabs.
local function deliver(line)
    local outputs = ns.Store.Get().outputs
    local delivered = false
    for _, window in ipairs(Scanner.OutputWindows()) do
        local frame = _G["ChatFrame" .. window.index]
        if outputs[window.key] and frame then
            frame:AddMessage(line)
            if frame ~= SELECTED_CHAT_FRAME then FCF_StartAlertFlash(frame) end
            delivered = true
        end
    end
    if not delivered then DEFAULT_CHAT_FRAME:AddMessage(line) end
end

-- Built like Blizzard's own channel line: GetPlayerLink carries lineID, chat type and channel so
-- the right-click menu works, and raid markers render unless the sender suppressed them.
local function showMatch(msg, sender, channelName, channelIndex, lineID, suppressRaidIcons)
    local stamp = date("%H:%M")
    local link = GetPlayerLink(sender, "|cffffff00[" .. sender .. "]:|r", lineID, "CHANNEL", tostring(channelIndex))
    local text = C_ChatInfo.ReplaceIconAndGroupExpressions(msg, suppressRaidIcons, true)
    deliver("|cff7f7f7f[" .. stamp .. "]|r |cff40c0ff[" .. channelName .. "]|r " .. link .. " " .. text)

    Scanner.matchCount = Scanner.matchCount + 1
    Scanner.lastMatchSender = sender
    Scanner.lastMatchStamp = stamp
    fireChanged()

    local store = ns.Store.Get()
    local now = GetTime()
    if store.playSound and now - lastSoundTime >= ns.SOUND_THROTTLE then
        PlaySound(store.soundId)
        lastSoundTime = now
    end
end

local LOCKDOWN_NOTICE = "The client is withholding chat text from addons (chat messaging lockdown), so keyword matching is paused. Your settings are fine."

-- Announced once per transition, so a long lockdown never floods chat but never fails silently.
local function setChatLocked(locked)
    if Scanner.chatLocked == locked then return end
    Scanner.chatLocked = locked
    ns.notify(locked and LOCKDOWN_NOTICE or "Chat text is readable again, scanning resumed.")
    fireChanged()
end

-- CHAT_MSG_CHANNEL is SecretInChatMessagingLockdown: during lockdown text and playerName arrive as
-- secret values and any string operation on them aborts this handler. channelBaseName, channelIndex,
-- lineID and suppressRaidIcons are NeverSecret, so the channel filter runs first. The lockdown test
-- takes no arguments because issecretvalue rejects secrets from tainted addon code.
eventFrame:SetScript("OnEvent", function(_, _, ...)
    local msg, sender, _, _, _, _, _, channelIndex, channelBaseName, _, lineID, _, _, _, _, _, suppressRaidIcons = ...
    if not ns.Store.Get().inputChannels[ns.channelKey(channelBaseName)] then return end

    if C_ChatInfo.InChatMessagingLockdown() then
        setChatLocked(true)
        return
    end
    setChatLocked(false)

    if matchesKeywords(msg) and not isDuplicate(sender, msg) then
        showMatch(msg, sender, channelBaseName, channelIndex, lineID, suppressRaidIcons)
    end
end)

local function countChannels()
    local n = 0
    for _ in pairs(ns.Store.Get().inputChannels) do n = n + 1 end
    return n
end

-- Starts from saved settings. A resume after login or reload stays quiet about missing settings.
local function begin(isResume)
    local store = ns.Store.Get()
    Scanner.ReloadKeywords()
    local channels = countChannels()

    if #keywordGroups == 0 or channels == 0 then
        if isResume then
            store.scanEnabled = false
        elseif #keywordGroups == 0 then
            ns.notify("No keywords entered. Open the scan panel to configure.")
        else
            ns.notify("No input channels selected. Open the scan panel to configure.")
        end
        return
    end

    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    Scanner.scanning = true
    Scanner.matchCount = 0
    store.scanEnabled = true
    ns.notify(string.format("Scanning %d channel(s) for %d keyword group(s).", channels, #keywordGroups))

    -- Surfaced at start, so a scan that cannot match never looks healthy.
    Scanner.chatLocked = C_ChatInfo.InChatMessagingLockdown()
    if Scanner.chatLocked then ns.notify(LOCKDOWN_NOTICE) end
    fireChanged()
end

function Scanner.Start()
    begin(false)
end

function Scanner.Resume()
    if ns.Store.Get().scanEnabled then begin(true) end
end

function Scanner.Stop()
    eventFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
    Scanner.scanning = false
    Scanner.chatLocked = false
    ns.Store.Get().scanEnabled = false
    ns.notify("Scan stopped.")
    fireChanged()
end
