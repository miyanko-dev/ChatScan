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
-- frame is hidden, as Blizzard's own chat does. The line carries the channel's colour and chat type
-- id like Blizzard's, so a later colour change in the chat settings recolours it too.
local function deliver(line, color)
    local outputs = ns.Store.Get().outputs
    local delivered = false
    for _, window in ipairs(Scanner.OutputWindows()) do
        local frame = _G["ChatFrame" .. window.index]
        if outputs[window.key] and frame then
            frame:AddMessage(line, color.r, color.g, color.b, color.id)
            if not frame:IsShown() then FCF_StartAlertFlash(frame) end
            delivered = true
        end
    end
    if not delivered then DEFAULT_CHAT_FRAME:AddMessage(line, color.r, color.g, color.b, color.id) end
end

-- Blizzard's own sender decoration: ambiguated name, class colour when that chat type's setting
-- asks for it, otherwise uncoloured so it takes the line colour. Blizzard's chat passes the first
-- 14 payload fields and discordInfo, so the helper gets exactly those.
local function decoratedSender(event, ...)
    local text, sender, language, channelName, sender2, flags, zoneID, channelIndex, baseName, languageID, lineID, guid, bnSenderID, isMobile, _, _, _, discordInfo = ...
    return ChatFrameUtil.GetDecoratedSenderName(event, text, sender, language, channelName, sender2, flags, zoneID, channelIndex, baseName, languageID, lineID, guid, bnSenderID, isMobile, discordInfo)
end

-- Community lines link through the community message, as Blizzard's chat does, so the right-click
-- menu offers the community actions. The last community line is read inside its own event, like
-- Blizzard's chat reads it; without it the name shows unlinked, as there.
local function communityLink(sender, display, bnSenderID)
    local messageInfo, clubId, streamId = C_Club.GetInfoFromLastCommunityChatLine()
    if not messageInfo then return display end
    local id = messageInfo.messageId
    if bnSenderID and bnSenderID ~= 0 then
        return GetBNPlayerCommunityLink(sender, display, bnSenderID, clubId, streamId, id.epoch, id.position)
    end
    return GetPlayerCommunityLink(sender, display, clubId, streamId, id.epoch, id.position)
end

-- The link keeps the full name so a whisper reaches the right player. A channel link carries
-- lineID, chat type and channel so the right-click menu works.
local function senderLink(event, ...)
    local _, sender, _, _, _, _, _, channelIndex, _, _, lineID, _, bnSenderID = ...
    local display = "[" .. decoratedSender(event, ...) .. "]"
    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" then return communityLink(sender, display, bnSenderID) end
    return GetPlayerLink(sender, display, lineID, "CHANNEL", tostring(channelIndex))
end

-- The channel link Blizzard's chat prints: left-click opens chat on that channel, right-click its
-- menu. Blizzard skips it for an empty channel name, which ResolvePrefixedChannelName cannot parse.
local function channelLink(channelName, channelIndex)
    if channelName == "" then return "" end
    local display = "[" .. ChatFrameUtil.ResolvePrefixedChannelName(channelName) .. "]"
    return LinkUtil.FormatLink(LinkTypes.Channel, display, "channel", channelIndex) .. " "
end

-- Built like Blizzard's channel line: channel link, sender link, then the text, with raid markers
-- rendered unless the sender suppressed them. Only the time stamp is ChatScan's own.
local function showMatch(event, ...)
    local msg, _, _, channelName, _, _, _, channelIndex, _, _, _, _, _, _, _, _, suppressRaidIcons = ...
    local stamp = GRAY_FONT_COLOR:WrapTextInColorCode("[" .. date("%H:%M") .. "]")
    local text = C_ChatInfo.ReplaceIconAndGroupExpressions(msg, suppressRaidIcons, true)
    local color = ChatTypeInfo["CHANNEL" .. channelIndex] or ChatTypeInfo.CHANNEL
    deliver(stamp .. " " .. channelLink(channelName, channelIndex) .. senderLink(event, ...) .. ": " .. text, color)

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

-- Both channel events are SecretInChatMessagingLockdown and share one payload: during lockdown
-- text, playerName, guid, bnSenderID and discordInfo may arrive as secret values that string
-- operations cannot use. channelName, channelIndex, channelBaseName, lineID and suppressRaidIcons are
-- NeverSecret, so the channel filter runs first and the rest is read only outside lockdown.
-- Matching relies on the lockdown check alone; an extra issecretvalue guard on the text waits for
-- an in-game check.
local function onChannelMessage(event, ...)
    local msg, sender, _, _, _, _, _, _, channelBaseName = ...
    if not ns.Store.Get().inputChannels[ns.channelKey(channelBaseName)] then return end

    if C_ChatInfo.InChatMessagingLockdown() then
        setChatLocked(true)
        return
    end
    setChatLocked(false)

    if matchesKeywords(msg) and not isDuplicate(sender, msg) then showMatch(event, ...) end
end

-- ADDON_RESTRICTION_STATE_CHANGED fires before a restriction applies and after it lifts, so the
-- lockdown is re-read a frame later. This keeps the status right in a quiet channel.
local function refreshLockdown()
    if Scanner.scanning then setChatLocked(C_ChatInfo.InChatMessagingLockdown()) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        RunNextFrame(refreshLockdown)
    else
        onChannelMessage(event, ...)
    end
end)

local function countChannels()
    local n = 0
    for _ in pairs(ns.Store.Get().inputChannels) do n = n + 1 end
    return n
end

-- A running scan left with no keyword group or no channel stays on but can never match.
function Scanner.CanMatch()
    return #keywordGroups > 0 and countChannels() > 0
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

    -- Community channels (Community:<clubId>:<streamId>) arrive on their own event.
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
    eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
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
    eventFrame:UnregisterAllEvents()
    Scanner.scanning = false
    Scanner.chatLocked = false
    ns.Store.Get().scanEnabled = false
    ns.notify("Scan stopped.")
    fireChanged()
end
