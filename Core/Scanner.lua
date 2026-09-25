local _, ns = ...

local Compat = ns.Compat

local Scanner = {
    scanning = false,
    matchCount = 0,
    lastMatchSender = nil,
    lastMatchStamp = nil,
    -- True while the client refuses addons access to chat text. See Compat.ChatPayloadReadable.
    chatLocked = false,
}
ns.Scanner = Scanner

local parsedGroups = {}
local activeChannels = {}
local activeOutputs = {}
local activeOptions = { playSound = true, soundId = ns.DEFAULT_SOUND_ID }
local recentMatches = {}
local lastSoundTime = 0

local eventFrame = CreateFrame("Frame")

-- Listeners the panel registers so scan state changes refresh the UI without the scanner knowing
-- about frames.
local listeners = {}

function Scanner.OnChanged(callback)
    listeners[#listeners + 1] = callback
end

local function fireChanged()
    for _, callback in ipairs(listeners) do callback() end
end

function Scanner.ParseKeywords(rows)
    local groups = {}
    if type(rows) ~= "table" then return groups end
    for _, rowText in ipairs(rows) do
        if type(rowText) == "string" then
            local terms = {}
            for raw in string.gmatch(rowText, "[^,]+") do
                local term = ns.trim(raw)
                if term ~= "" then
                    terms[#terms + 1] = strlower(term)
                end
            end
            if #terms > 0 then
                groups[#groups + 1] = terms
            end
        end
    end
    return groups
end

local function matchesKeywords(text)
    if #parsedGroups == 0 then return false end
    local lower = strlower(text)
    for _, terms in ipairs(parsedGroups) do
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
    local key = (sender or "?") .. "\031" .. msg
    for i = #recentMatches, 1, -1 do
        local entry = recentMatches[i]
        if now - entry.t > ns.DEDUP_TTL then
            table.remove(recentMatches, i)
        elseif entry.k == key then
            return true
        end
    end
    recentMatches[#recentMatches + 1] = { k = key, t = now }
    while #recentMatches > ns.DEDUP_MAX do
        table.remove(recentMatches, 1)
    end
    return false
end

-- Mirror Blizzard's player link shape (name:lineID:chatType). Both clients split these fields out
-- and hand lineID to the right-click menu.
local function playerLink(sender, lineID)
    local link = "|Hplayer:" .. sender
    if lineID and lineID > 0 then
        link = link .. ":" .. lineID .. ":CHANNEL"
    end
    return link .. "|h|cffffff00[" .. sender .. "]:|r|h"
end

-- Iterates the chat windows a match may be delivered to, skipping the combat log.
function Scanner.OutputWindows()
    local windows = {}
    for i = 1, Compat.MaxChatWindows() do
        if i ~= ns.COMBAT_LOG_INDEX then
            local name = GetChatWindowInfo(i)
            if name and name ~= "" then
                windows[#windows + 1] = { index = i, name = name, key = strlower(name) }
            end
        end
    end
    return windows
end

local function deliver(line)
    local delivered = false
    for _, window in ipairs(Scanner.OutputWindows()) do
        if activeOutputs[window.key] then
            local frame = _G["ChatFrame" .. window.index]
            if frame then
                frame:AddMessage(line)
                -- Flash the tab so matches in a background tab aren't missed.
                if frame ~= SELECTED_CHAT_FRAME and FCF_StartAlertFlash then
                    FCF_StartAlertFlash(frame)
                end
                delivered = true
            end
        end
    end
    if not delivered then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

local function showMatch(msg, sender, channelName, lineID)
    local stamp = date("%H:%M")
    local prefix = "|cff7f7f7f[" .. stamp .. "]|r"
    if channelName and channelName ~= "" then
        prefix = prefix .. " |cff40c0ff[" .. channelName .. "]|r"
    end
    deliver(prefix .. " " .. playerLink(sender, lineID) .. " " .. Compat.RenderChatExpressions(msg))

    Scanner.matchCount = Scanner.matchCount + 1
    Scanner.lastMatchSender = sender
    Scanner.lastMatchStamp = stamp
    fireChanged()

    if activeOptions.playSound then
        local now = GetTime()
        if now - lastSoundTime >= ns.SOUND_THROTTLE then
            Compat.PlaySound(activeOptions.soundId)
            lastSoundTime = now
        end
    end
end

local LOCKDOWN_NOTICE = "This client is withholding chat text from addons (chat messaging lockdown), so keyword matching is paused. Nothing is wrong with your settings."

-- Announced once per transition rather than per message, so a lockdown that lasts the whole
-- session does not flood the chat frame but never fails silently either.
local function setChatLocked(locked)
    if Scanner.chatLocked == locked then return end
    Scanner.chatLocked = locked
    if locked then
        ns.notify(LOCKDOWN_NOTICE)
    else
        ns.notify("Chat text is readable again, scanning resumed.")
    end
    fireChanged()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "CHAT_MSG_CHANNEL" then return end

    -- Checked before the payload is unpacked, and with a call that takes no arguments. On 1.60
    -- the text and sender arrive as secret values during lockdown, and the first string operation
    -- on one aborts this handler, so there is no safe way to inspect them first.
    if not Compat.ChatPayloadReadable() then
        setChatLocked(true)
        return
    end
    setChatLocked(false)

    -- Payload order is identical on 1.15.9 and 1.60.1: 9 = channelBaseName, 11 = lineID.
    local msg, sender, _, _, _, _, _, _, channelBaseName, _, lineID = ...
    if not msg or msg == "" then return end
    if not activeChannels[ns.channelKey(channelBaseName)] then return end
    if not matchesKeywords(msg) then return end
    if isDuplicate(sender, msg) then return end
    showMatch(msg, sender or UNKNOWN or "?", channelBaseName, lineID)
end)

function Scanner.LoadRuntime(store)
    parsedGroups = Scanner.ParseKeywords(store.keywords)
    activeChannels = {}
    for key, on in pairs(store.inputChannels) do
        if on then activeChannels[key] = true end
    end
    activeOutputs = {}
    for key, on in pairs(store.outputs) do
        if on then activeOutputs[key] = true end
    end
    activeOptions.playSound = store.playSound ~= false
    activeOptions.soundId = store.soundId or ns.DEFAULT_SOUND_ID
end

-- Channel and output changes apply to a running scan straight away, so ticking a box in the panel
-- takes effect on the next message instead of the next Start.
function Scanner.SetChannelEnabled(key, enabled)
    activeChannels[key] = enabled and true or nil
end

function Scanner.SetOutputEnabled(key, enabled)
    activeOutputs[key] = enabled and true or nil
end

function Scanner.SetSoundEnabled(enabled)
    activeOptions.playSound = enabled and true or false
end

function Scanner.SetSoundId(id)
    activeOptions.soundId = id or ns.DEFAULT_SOUND_ID
end

function Scanner.GetSoundId()
    return activeOptions.soundId
end

function Scanner.ReloadKeywords(store)
    parsedGroups = Scanner.ParseKeywords(store.keywords)
end

local function countTrue(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
end

local function notifyScanning()
    ns.notify(string.format("Scanning %d channel(s) for %d keyword group(s).",
        countTrue(activeChannels), #parsedGroups))
end

local function beginListening()
    if not eventFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    end
    Scanner.scanning = true
end

-- Starts a scan from saved settings. Returns false with a chat hint when nothing is configured.
function Scanner.Start()
    local store = ns.Store.Get()
    Scanner.LoadRuntime(store)

    if #parsedGroups == 0 then
        ns.notify("No keywords entered. Open the scan panel to configure.")
        return false
    end
    if countTrue(activeChannels) == 0 then
        ns.notify("No input channels selected. Open the scan panel to configure.")
        return false
    end

    beginListening()
    store.scanEnabled = true
    Scanner.matchCount = 0
    notifyScanning()
    -- Surfaced at Start rather than on the first message, so the user is not left watching an
    -- apparently running scan that can never match.
    if not Compat.ChatPayloadReadable() then
        Scanner.chatLocked = true
        ns.notify(LOCKDOWN_NOTICE)
    end
    fireChanged()
    return true
end

function Scanner.Stop()
    if eventFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        eventFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
    if Scanner.scanning then
        Scanner.scanning = false
        ns.notify("Scan stopped.")
    end
    Scanner.chatLocked = false
    ns.Store.Get().scanEnabled = false
    fireChanged()
end

-- Resumes a scan that was active before a reload or logout, without announcing configuration
-- errors.
function Scanner.Resume()
    local store = ns.Store.Get()
    if not store.scanEnabled then return end
    Scanner.LoadRuntime(store)
    if #parsedGroups > 0 and countTrue(activeChannels) > 0 then
        beginListening()
        notifyScanning()
        if not Compat.ChatPayloadReadable() then
            Scanner.chatLocked = true
            ns.notify(LOCKDOWN_NOTICE)
        end
        fireChanged()
    else
        store.scanEnabled = false
    end
end
