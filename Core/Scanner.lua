local _, ns = ...

local Scanner = {
    scanning = false,
    matchCount = 0,
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
    fireChanged()
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

-- Open chat windows a match may be delivered to, skipping the combat log. A closed tab keeps its
-- name in GetChatWindowInfo, so only active windows count; a closed pick falls back to the default.
function Scanner.OutputWindows()
    local windows = {}
    for i = 1, Constants.ChatFrameConstants.MaxChatWindows do
        local name = GetChatWindowInfo(i)
        if i ~= ns.COMBAT_LOG_INDEX and name and name ~= "" and FCF_IsChatWindowIndexActive(i) then
            windows[#windows + 1] = { index = i, name = name, key = strlower(name) }
        end
    end
    return windows
end

-- Falls back to the default chat frame when no output tab is picked. Flashes a tab only while its
-- frame is hidden, as Blizzard's own chat does. The colour and chat type id travel with the line
-- like Blizzard's, so a later colour change in the chat settings recolours it too.
local function deliver(line, r, g, b, id)
    local outputs = ns.Store.Get().outputs
    local delivered = false
    for _, window in ipairs(Scanner.OutputWindows()) do
        local frame = _G["ChatFrame" .. window.index]
        if outputs[window.key] and frame then
            frame:AddMessage(line, r, g, b, id)
            if not frame:IsShown() then FCF_StartAlertFlash(frame) end
            delivered = true
        end
    end
    if not delivered then DEFAULT_CHAT_FRAME:AddMessage(line, r, g, b, id) end
end

-- Only the time stamp in front is ChatScan's own; the rest of the line is Blizzard's.
local function forward(line, r, g, b, id)
    local stamp = GRAY_FONT_COLOR:WrapTextInColorCode("[" .. date("%H:%M") .. "]")
    deliver(stamp .. " " .. line, r, g, b, id)

    Scanner.matchCount = Scanner.matchCount + 1
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

-- Announces a lockdown change and says whether chat text and club data are readable now.
local function canRead()
    local locked = C_ChatInfo.InChatMessagingLockdown()
    setChatLocked(locked)
    return not locked
end

-- Chat type events and the chat type key that ticks them.
local chatTypeOf = {}
for _, group in ipairs(ns.CHAT_GROUPS) do
    for _, chatType in ipairs(group.types) do
        for _, event in ipairs(chatType.events) do chatTypeOf[event] = chatType.key end
    end
end

-- Whether the player ticked this event's source: its chat type, or for channels the channel. Reads
-- only the NeverSecret channelBaseName, so it is safe before the lockdown check.
local function isTicked(event, ...)
    local store = ns.Store.Get()
    local typeKey = chatTypeOf[event]
    if typeKey then return store.chatTypes[typeKey] end
    local channelBaseName = select(9, ...)
    return store.inputChannels[ns.channelKey(channelBaseName)]
end

-- Every chat event ChatScan reads shares one payload, and all but CHAT_MSG_GUILD_DISCORD are
-- SecretInChatMessagingLockdown: during lockdown text, playerName, playerName2, guid, bnSenderID
-- and discordInfo may arrive as secret values that string operations cannot use. The source filter
-- and Blizzard's letterbox rule use NeverSecret fields only, so they run first and the rest is read
-- outside lockdown. Guild Discord is gated the same, so one lockdown rule covers every source.
-- Matching relies on the lockdown check alone; an extra issecretvalue guard on the text waits for
-- an in-game check.
local function onChatMessage(event, ...)
    local hideSender = select(16, ...)
    if hideSender or not isTicked(event, ...) or not canRead() then return end

    local msg, sender = ...
    if matchesKeywords(msg) and not isDuplicate(sender, msg) then forward(ns.Lines.Chat(event, ...)) end
end

-- A community stream that is in a chat tab is a chat channel and arrives as
-- CHAT_MSG_COMMUNITIES_CHANNEL too, so only streams outside every chat tab are read here and no
-- message forwards twice. CLUB_MESSAGE_ADDED itself is never secret, but GetMessageInfo is
-- SecretInChatMessagingLockdown, so it waits for the lockdown check.
local function onClubMessage(clubId, streamId, messageId)
    local channelName = ChatFrameUtil.GetCommunitiesChannelName(clubId, streamId)
    if not ns.Store.Get().inputChannels[ns.channelKey(channelName)] then return end
    local localID = ChatFrameUtil.GetCommunitiesChannelLocalID(clubId, streamId)
    if (localID and localID ~= 0) or not canRead() then return end

    local message = C_Club.GetMessageInfo(clubId, streamId, messageId)
    if not message or message.destroyed then return end
    local author = message.author.name or ""
    if matchesKeywords(message.content) and not isDuplicate(author, message.content) then
        forward(ns.Lines.Stream(clubId, streamId, message))
    end
end

-- ADDON_RESTRICTION_STATE_CHANGED fires before a restriction applies and after it lifts, so the
-- lockdown is re-read a frame later. This keeps the status right in a quiet channel.
local function refreshLockdown()
    if Scanner.scanning then setChatLocked(C_ChatInfo.InChatMessagingLockdown()) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        RunNextFrame(refreshLockdown)
    elseif event == "CLUB_MESSAGE_ADDED" then
        onClubMessage(...)
    else
        onChatMessage(event, ...)
    end
end)

-- Ticked channels, community streams and chat types together.
local function countSources()
    local store, n = ns.Store.Get(), 0
    for _ in pairs(store.inputChannels) do n = n + 1 end
    for _ in pairs(store.chatTypes) do n = n + 1 end
    return n
end

-- A running scan left with no keyword group or no source stays on but can never match.
function Scanner.CanMatch()
    return #keywordGroups > 0 and countSources() > 0
end

-- Starts from saved settings. A resume after login or reload stays quiet about missing settings.
local function begin(isResume)
    local store = ns.Store.Get()
    Scanner.ReloadKeywords()
    local sources = countSources()

    if #keywordGroups == 0 or sources == 0 then
        if isResume then
            store.scanEnabled = false
        elseif #keywordGroups == 0 then
            ns.notify("No keywords entered. Open the scan panel to configure.")
        else
            ns.notify("No channels or chat types selected. Open the scan panel to configure.")
        end
        return
    end

    -- Every source's event is registered, so ticks changed mid-scan apply at once. Community
    -- channels (Community:<clubId>:<streamId>) arrive on their own event.
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
    eventFrame:RegisterEvent("CLUB_MESSAGE_ADDED")
    eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    for event in pairs(chatTypeOf) do eventFrame:RegisterEvent(event) end
    Scanner.scanning = true
    Scanner.matchCount = 0
    store.scanEnabled = true
    ns.notify(string.format("Scanning %d source(s) for %d keyword group(s).", sources, #keywordGroups))

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
    eventFrame:UnregisterAllEvents()
    Scanner.scanning = false
    Scanner.chatLocked = false
    ns.Store.Get().scanEnabled = false
    ns.notify("Scan stopped.")
    fireChanged()
end
