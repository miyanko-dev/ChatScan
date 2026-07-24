local ADDON_NAME = "ChatScan"
local PREFIX = "|cffffff00[ChatScan]:|r "

local RAID_ICONS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

local DEDUP_TTL = 10
local DEDUP_MAX = 20
local DEFAULT_SOUND_ID = 3175  -- SOUNDKIT.MAP_PING (minimap ping)
local SOUND_THROTTLE = 3.0

-- Friendly named alerts for the sound picker, so users never type a raw ID.
local SOUND_PRESETS = {
    { name = "Minimap Ping",   id = SOUNDKIT.MAP_PING },
    { name = "Whisper",        id = SOUNDKIT.TELL_MESSAGE },
    { name = "Raid Warning",   id = SOUNDKIT.RAID_WARNING },
    { name = "Ready Check",    id = SOUNDKIT.READY_CHECK },
    { name = "Auction Window", id = SOUNDKIT.AUCTION_WINDOW_OPEN },
    { name = "Alarm Clock",    id = SOUNDKIT.ALARM_CLOCK_WARNING_1 },
    { name = "Murloc",         id = SOUNDKIT.MURLOC_AGGRO },
}

-- Layout spacing. All numeric padding/sizing uses the 4/8/16/24/32 increment system; exceptions are dimensions dictated by Blizzard art (header banner / label lift) and the 20px native CheckButton size.
local PAD = 16                  -- outer panel padding (sides + bottom)
local PAD_TOP = 48              -- clears the dialog-box-header banner
local SECTION_GAP = 24          -- vertical space between two section boxes
local SECTION_INNER_PAD = 8     -- inset between section border and body
local SECTION_LABEL_LIFT = 7    -- header banner overlap; visual-only
local HELPER_GAP = 8            -- space below a section's helper text
local ROW_H = 24                -- height of an interactive row (input/button)
local ROW_GAP = 4               -- vertical space between row siblings
local CB_H = 20                 -- native UICheckButton size
local CB_PITCH = 24             -- checkbox row pitch (CB_H + ROW_GAP)

local COMBAT_LOG_INDEX = 2

local panel
local channelCheckboxes = {}
local outputCheckboxes = {}
local channelListChildren = {}
local outputListChildren = {}
local keywordRowsActive = {}
local keywordRowPool = {}
local keywordsContainer
local addKeywordRow, layoutKeywordRows

local scanning = false
local scanFrame = CreateFrame("Frame")
local parsedGroups = {}
local activeChannels = {}
local activeOutputs = {}
local activeOptions = { playSound = true, soundId = DEFAULT_SOUND_ID }
local recentMatches = {}
local lastSoundTime = 0
local matchCount = 0
local lastMatchSender, lastMatchStamp

local function notify(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function matchLabel(count)
    return string.format("%d match%s", count, count == 1 and "" or "es")
end

local function playerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function loadStore()
    ChatScanDB = ChatScanDB or {}
    if type(ChatScanDB.minimap) ~= "table" then
        ChatScanDB.minimap = { hide = false, minimapPos = 195 }
    end
    local key = playerKey()
    ChatScanDB[key] = ChatScanDB[key] or {
        inputChannels = {},
        outputs = {},
        keywords = {},
        scanEnabled = false,
        playSound = true,
        soundId = DEFAULT_SOUND_ID,
    }
    local store = ChatScanDB[key]
    store.inputChannels = store.inputChannels or {}
    store.outputs = store.outputs or {}
    store.keywords = store.keywords or {}
    if store.scanEnabled == nil then store.scanEnabled = false end
    if store.playSound == nil then store.playSound = true end
    if type(store.soundId) ~= "number" or store.soundId <= 0 then
        store.soundId = DEFAULT_SOUND_ID
    end
    return store
end

local function renderIcons(text)
    return (text:gsub("{(.-)}", function(symbol)
        local index = RAID_ICONS[strlower(symbol)]
        if index then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
        end
        return "{" .. symbol .. "}"
    end))
end

local function parseKeywords(rows)
    local groups = {}
    if type(rows) ~= "table" then return groups end
    for _, rowText in ipairs(rows) do
        if type(rowText) == "string" then
            local terms = {}
            for raw in string.gmatch(rowText, "[^,]+") do
                local term = raw:match("^%s*(.-)%s*$")
                if term and term ~= "" then
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
        if now - entry.t > DEDUP_TTL then
            table.remove(recentMatches, i)
        elseif entry.k == key then
            return true
        end
    end
    recentMatches[#recentMatches + 1] = { k = key, t = now }
    while #recentMatches > DEDUP_MAX do
        table.remove(recentMatches, 1)
    end
    return false
end

local function showMatch(msg, sender, channelName)
    local rendered = renderIcons(msg)
    local prefix = "|cff7f7f7f[" .. date("%H:%M") .. "]|r"
    if channelName and channelName ~= "" then
        prefix = prefix .. " |cff40c0ff[" .. channelName .. "]|r"
    end
    local line = prefix .. " |Hplayer:" .. sender .. "|h|cffffff00[" .. sender .. "]:|r|h " .. rendered

    local delivered = false
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        if i ~= COMBAT_LOG_INDEX then
            local name = GetChatWindowInfo and GetChatWindowInfo(i)
            if name and name ~= "" and activeOutputs[strlower(name)] then
                local frame = _G["ChatFrame" .. i]
                if frame then
                    frame:AddMessage(line)
                    -- Flash the tab so matches in a background tab aren't missed.
                    if frame ~= SELECTED_CHAT_FRAME then
                        FCF_StartAlertFlash(frame)
                    end
                    delivered = true
                end
            end
        end
    end
    if not delivered then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end

    matchCount = matchCount + 1
    lastMatchSender = sender
    lastMatchStamp = date("%H:%M")
    if panel and panel.updateStatus then panel.updateStatus() end

    if activeOptions.playSound then
        local now = GetTime()
        if now - lastSoundTime >= SOUND_THROTTLE then
            PlaySound(activeOptions.soundId or DEFAULT_SOUND_ID, "Master", true)
            lastSoundTime = now
        end
    end
end

scanFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "CHAT_MSG_CHANNEL" then return end
    local msg, sender, _, _, _, _, _, _, channelName = ...
    if not msg or msg == "" then return end
    local nameKey = channelName and strlower(channelName) or nil
    if not nameKey or not activeChannels[nameKey] then return end
    if not matchesKeywords(msg) then return end
    if isDuplicate(sender, msg) then return end
    showMatch(msg, sender or UNKNOWN or "?", channelName)
end)

local function loadRuntime(store)
    parsedGroups = parseKeywords(store.keywords)
    activeChannels = {}
    for name, on in pairs(store.inputChannels) do
        if on then activeChannels[strlower(name)] = true end
    end
    activeOutputs = {}
    for k, v in pairs(store.outputs) do
        activeOutputs[k] = v and true or false
    end
    activeOptions.playSound = store.playSound ~= false
    activeOptions.soundId = store.soundId or DEFAULT_SOUND_ID
end

local function countTrue(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
end

local function notifyScanning()
    notify(string.format("Scanning %d channel(s) for %d keyword group(s).",
        countTrue(activeChannels), #parsedGroups))
end

local function startScan()
    local store = loadStore()
    loadRuntime(store)

    if #parsedGroups == 0 then
        notify("No keywords entered. Open the scan panel to configure.")
        return false
    end
    if countTrue(activeChannels) == 0 then
        notify("No input channels selected. Open the scan panel to configure.")
        return false
    end

    if not scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    end
    scanning = true
    store.scanEnabled = true
    matchCount = 0
    notifyScanning()
    return true
end

local function stopScan()
    if scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
        scanFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
    if scanning then
        scanning = false
        notify("Scan stopped.")
    end
    local store = ChatScanDB and ChatScanDB[playerKey()]
    if store then store.scanEnabled = false end
end

local function clearChildren(list)
    for _, child in ipairs(list) do
        child:Hide()
        child:SetParent(nil)
    end
    wipe(list)
end

-- UICheckButtonTemplate exposes a .Text region on most clients but not all; fall back to a manual label so both cases render identically.
local function setCheckboxLabel(checkButton, text)
    if checkButton.Text then
        checkButton.Text:SetText(text)
        checkButton.Text:SetFontObject(GameFontHighlightSmall)
    else
        local label = checkButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", checkButton, "RIGHT", 2, 0)
        label:SetText(text)
    end
end

-- Render a list of CheckButtons inside `container`, anchored to the container itself (no double-counted top gap). Returns the rendered height so the caller can size the container exactly to the last row's bottom.
local function renderCheckList(container, entries, isChecked, onClick, emptyText, tracker)
    clearChildren(tracker)
    if #entries == 0 then
        local fs = container:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        fs:SetText(emptyText)
        tracker[#tracker + 1] = fs
        return CB_H
    end
    local anchor
    for i, entry in ipairs(entries) do
        local cb = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
        cb:SetSize(CB_H, CB_H)
        if i == 1 then
            cb:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        else
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ROW_GAP)
        end
        setCheckboxLabel(cb, entry.name)
        cb:SetChecked(isChecked(entry))
        cb:SetScript("OnClick", function(self) onClick(entry, self:GetChecked()) end)
        tracker[#tracker + 1] = cb
        if entry.key then
            (entry.bucket or {})[entry.key] = cb
        end
        anchor = cb
    end
    return CB_H + (#entries - 1) * CB_PITCH
end

local function rebuildChannels(container, store)
    wipe(channelCheckboxes)
    local list = { GetChannelList() }
    local entries = {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if name and name ~= "" then
            entries[#entries + 1] = {
                name = name, key = strlower(name), bucket = channelCheckboxes,
            }
        end
    end
    return renderCheckList(container, entries,
        function(entry) return store.inputChannels[entry.key] and true or false end,
        function(entry, checked) store.inputChannels[entry.key] = checked and true or nil end,
        "(not in any channels)", channelListChildren)
end

local function buildOutputs(container, store)
    wipe(outputCheckboxes)
    local entries = {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        if i ~= COMBAT_LOG_INDEX then
            local name = GetChatWindowInfo and GetChatWindowInfo(i)
            if name and name ~= "" then
                entries[#entries + 1] = {
                    name = name, key = strlower(name), bucket = outputCheckboxes,
                }
            end
        end
    end
    return renderCheckList(container, entries,
        function(entry) return store.outputs[entry.key] and true or false end,
        function(entry, checked) store.outputs[entry.key] = checked and true or nil end,
        "(no chat tabs available)", outputListChildren)
end

-- Per-row UX mirrors TargetFinder's slot rows. A row holds one keyword group. States: * empty (no saved keyword, input blank) -> no button shown * pending (input differs from saved text) -> "Add" button * saved (input matches saved text) -> remove (X) button The trailing row is always empty so users can add a new keyword without pressing an extra "new row" button.
local commitKeywordRow, deleteKeywordRow, ensureTrailingEmptyRow

local function persistKeywords()
    local store = ChatScanDB and ChatScanDB[playerKey()]
    if not store then return end
    store.keywords = {}
    for _, row in ipairs(keywordRowsActive) do
        if row.saved and row.saved ~= "" then
            store.keywords[#store.keywords + 1] = row.saved
        end
    end
    parsedGroups = parseKeywords(store.keywords)
end

local function createKeywordRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetMaxLetters(256)
    eb:SetHeight(ROW_H)
    eb:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.editBox = eb

    local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    addBtn:SetSize(48, ROW_H)
    addBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    addBtn:SetText("Add")
    addBtn:Hide()
    row.addBtn = addBtn

    local rmBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    rmBtn:SetSize(ROW_H, ROW_H)
    rmBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    rmBtn:Hide()
    row.removeBtn = rmBtn

    local function updateState()
        local typed = (eb:GetText() or ""):match("^%s*(.-)%s*$")
        eb:ClearAllPoints()
        eb:SetPoint("LEFT", row, "LEFT", 8, 0)
        if row.saved and row.saved ~= "" and typed == row.saved then
            addBtn:Hide()
            rmBtn:Show()
            eb:SetPoint("RIGHT", rmBtn, "LEFT", -ROW_GAP, 0)
        elseif typed ~= "" then
            rmBtn:Hide()
            addBtn:Show()
            eb:SetPoint("RIGHT", addBtn, "LEFT", -ROW_GAP, 0)
        else
            addBtn:Hide()
            rmBtn:Hide()
            eb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        end
    end
    row.updateState = updateState

    eb:SetScript("OnTextChanged", function(_, userInput)
        if userInput then updateState() end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(row.saved or "")
        self:ClearFocus()
        updateState()
    end)
    eb:SetScript("OnEnterPressed", function() commitKeywordRow(row) end)
    addBtn:SetScript("OnClick", function() commitKeywordRow(row) end)
    rmBtn:SetScript("OnClick", function() deleteKeywordRow(row) end)

    return row
end

local function acquireRow()
    local row = table.remove(keywordRowPool)
    if not row then
        row = createKeywordRow(keywordsContainer)
    end
    row:SetParent(keywordsContainer)
    row:Show()
    return row
end

local function releaseRow(row)
    row.saved = nil
    row.editBox:SetText("")
    row:ClearAllPoints()
    row:Hide()
    keywordRowPool[#keywordRowPool + 1] = row
end

function addKeywordRow(text, savedAs)
    local row = acquireRow()
    row.saved = savedAs
    row.editBox:SetText(text or "")
    row.editBox:SetCursorPosition(0)
    keywordRowsActive[#keywordRowsActive + 1] = row
    if row.updateState then row.updateState() end
    return row
end

function layoutKeywordRows()
    for i, row in ipairs(keywordRowsActive) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", keywordsContainer, "TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
        row:SetPoint("RIGHT", keywordsContainer, "RIGHT", 0, 0)
        row:SetHeight(ROW_H)
    end
    local n = #keywordRowsActive
    local total = n > 0 and (n * ROW_H + (n - 1) * ROW_GAP) or ROW_H
    keywordsContainer:SetHeight(total)
    if panel and panel.resizePanel then
        panel.resizePanel()
    end
    return total
end

ensureTrailingEmptyRow = function()
    local last = keywordRowsActive[#keywordRowsActive]
    if not last or (last.saved and last.saved ~= "") then
        addKeywordRow(nil, nil)
    end
    layoutKeywordRows()
end

commitKeywordRow = function(row)
    local typed = (row.editBox:GetText() or ""):match("^%s*(.-)%s*$")
    if typed == "" then return end
    for _, other in ipairs(keywordRowsActive) do
        if other ~= row and other.saved == typed then
            row.editBox:SetText(row.saved or "")
            row.editBox:ClearFocus()
            row.updateState()
            return
        end
    end
    row.saved = typed
    row.editBox:ClearFocus()
    row.updateState()
    persistKeywords()
    ensureTrailingEmptyRow()
end

deleteKeywordRow = function(row)
    for i, r in ipairs(keywordRowsActive) do
        if r == row then
            table.remove(keywordRowsActive, i)
            releaseRow(row)
            break
        end
    end
    persistKeywords()
    ensureTrailingEmptyRow()
end

local function populateRows(store)
    for _, row in ipairs(keywordRowsActive) do
        releaseRow(row)
    end
    wipe(keywordRowsActive)
    for _, k in ipairs(store.keywords or {}) do
        addKeywordRow(k, k)
    end
    ensureTrailingEmptyRow()
end

-- Native Blizzard dialog backdrop (same art AceGUI's Frame / Questie's options use).
local function applyPanelBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

-- Blizzard dialog-box header banner from three pieces (left cap, middle, right cap); texcoords match AceGUI's Frame title.
local function buildTitleHeader(parent, text)
    local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

    local mid = parent:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(HEADER_TEXTURE)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", parent, "TOP", 0, 12)
    mid:SetHeight(40)

    local left = parent:CreateTexture(nil, "OVERLAY")
    left:SetTexture(HEADER_TEXTURE)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetWidth(30)
    left:SetHeight(40)

    local right = parent:CreateTexture(nil, "OVERLAY")
    right:SetTexture(HEADER_TEXTURE)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetWidth(30)
    right:SetHeight(40)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mid, "TOP", 0, -14)
    title:SetText(text)

    mid:SetWidth((title:GetStringWidth() or 0) + 10)

    return mid
end

-- Nested section box (matches AceGUI InlineGroup): flat dark bg + tooltip border.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    section:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    section:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 12, SECTION_LABEL_LIFT)
    label:SetText(labelText)
    section.label = label

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", SECTION_INNER_PAD, -SECTION_INNER_PAD)
    body:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -SECTION_INNER_PAD, SECTION_INNER_PAD)
    section.body = body

    return section
end

local function buildPanel()
    local f = CreateFrame("Frame", "ChatScanPanel", UIParent, "BackdropTemplate")
    f:SetSize(380, 1)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    applyPanelBackdrop(f)

    buildTitleHeader(f, "Chat Scan")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Builds a section box with a wrapped helper line at the top and a content container below it. The container is anchored at the top of the section body; helper text sits above with HELPER_GAP between the two. Returns the section + container; resizePanel later uses the container's height to compute the section's total height.
    local function makeContentSection(label, helperText, prevSection)
        local section = buildSection(f, label)
        if prevSection then
            section:SetPoint("TOPLEFT", prevSection, "BOTTOMLEFT", 0, -SECTION_GAP)
            section:SetPoint("TOPRIGHT", prevSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
        else
            section:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD_TOP)
            section:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD_TOP)
        end

        local helper = section.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        helper:SetPoint("TOPLEFT", section.body, "TOPLEFT", 0, 0)
        helper:SetPoint("RIGHT", section.body, "RIGHT", 0, 0)
        helper:SetJustifyH("LEFT")
        helper:SetWordWrap(true)
        helper:SetText(helperText)

        local container = CreateFrame("Frame", nil, section.body)
        container:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -HELPER_GAP)
        container:SetPoint("RIGHT", section.body, "RIGHT", 0, 0)
        container:SetHeight(CB_H)

        section.helper = helper
        section.container = container
        return section, container
    end

    -- Scanned Channels
    local channelsSection, channelContainer = makeContentSection(
        "Scanned Channels",
        "Pick which chat channels to scan for keyword matches.")

    -- Keywords
    local keywordsSection, kc = makeContentSection(
        "Keywords",
        "Each row matches independently (OR). Inside a row, separate keywords with commas to require all of them (AND).",
        channelsSection)
    keywordsContainer = kc

    -- Channel Output
    local outputsSection, outputContainer = makeContentSection(
        "Channel Output",
        "Pick which chat tabs receive keyword matches. If none are selected, the default chat frame is used.",
        keywordsSection)

    -- Sound Options
    local optionsSection = buildSection(f, "Sound Options")
    optionsSection:SetPoint("TOPLEFT", outputsSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    optionsSection:SetPoint("TOPRIGHT", outputsSection, "BOTTOMRIGHT", 0, -SECTION_GAP)

    local optionsHelper = optionsSection.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    optionsHelper:SetPoint("TOPLEFT", optionsSection.body, "TOPLEFT", 0, 0)
    optionsHelper:SetPoint("RIGHT", optionsSection.body, "RIGHT", 0, 0)
    optionsHelper:SetJustifyH("LEFT")
    optionsHelper:SetWordWrap(true)
    optionsHelper:SetText("This sound plays whenever a keyword match is found.")
    optionsSection.helper = optionsHelper

    -- Checkbox on the first row; the sound picker + Test sit on the row below.
    local soundCheck = CreateFrame("CheckButton", nil, optionsSection.body, "UICheckButtonTemplate")
    soundCheck:SetSize(CB_H, CB_H)
    soundCheck:SetPoint("TOPLEFT", optionsHelper, "BOTTOMLEFT", 0, -HELPER_GAP)
    setCheckboxLabel(soundCheck, "Play sound on match")
    soundCheck:SetScript("OnClick", function(self)
        local store = loadStore()
        local checked = self:GetChecked() and true or false
        store.playSound = checked
        activeOptions.playSound = checked
    end)
    f.soundCheck = soundCheck

    -- Named-sound picker. Choosing a sound saves it and plays it once as a preview.
    local soundDropdown = CreateFrame("DropdownButton", nil, optionsSection.body, "WowStyle1DropdownTemplate")
    soundDropdown:SetSize(160, ROW_H)
    soundDropdown:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -ROW_GAP)
    soundDropdown:SetDefaultText("Choose a sound")
    soundDropdown:SetupMenu(function(_, root)
        for _, preset in ipairs(SOUND_PRESETS) do
            root:CreateRadio(preset.name,
                function() return activeOptions.soundId == preset.id end,
                function()
                    local store = loadStore()
                    store.soundId = preset.id
                    activeOptions.soundId = preset.id
                    PlaySound(preset.id, "Master", true)
                end)
        end
    end)
    f.soundDropdown = soundDropdown

    -- Replays the selected sound so it can be previewed at any time.
    local testBtn = CreateFrame("Button", nil, optionsSection.body, "UIPanelButtonTemplate")
    testBtn:SetSize(60, ROW_H)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", ROW_GAP, 0)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function()
        PlaySound(activeOptions.soundId or DEFAULT_SOUND_ID, "Master", true)
    end)

    -- Footer (Close on the left, Start/Stop on the right)
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, ROW_H)
    closeBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(96, ROW_H)
    startBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local startTex = startBtn:GetNormalTexture()
    local startHi = startBtn:GetHighlightTexture()

    local function refreshStartBtn()
        if scanning then
            startBtn:SetText("Stop")
            if startTex then startTex:SetVertexColor(1, 0.35, 0.35) end
            if startHi then startHi:SetVertexColor(1, 0.5, 0.5) end
        else
            startBtn:SetText("Start")
            if startTex then startTex:SetVertexColor(1, 1, 1) end
            if startHi then startHi:SetVertexColor(1, 1, 1) end
        end
        if f.updateStatus then f.updateStatus() end
    end
    f.refreshStartBtn = refreshStartBtn
    refreshStartBtn()

    startBtn:SetScript("OnClick", function()
        if scanning then
            stopScan()
            refreshStartBtn()
            return
        end
        if startScan() then refreshStartBtn() end
    end)

    -- Live feedback shown between the footer buttons: scan state + match count.
    local statusText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", closeBtn, "RIGHT", 8, 0)
    statusText:SetPoint("RIGHT", startBtn, "LEFT", -8, 0)
    statusText:SetJustifyH("CENTER")

    local function updateStatus()
        if scanning then
            statusText:SetText("|cff40ff40Scanning|r  •  " .. matchLabel(matchCount))
        elseif matchCount > 0 then
            statusText:SetText("|cff999999Stopped|r  •  " .. matchLabel(matchCount) .. " this session")
        else
            statusText:SetText("|cff999999Not scanning|r")
        end
    end
    f.updateStatus = updateStatus

    -- Section height = helper text + HELPER_GAP + content height + body insets. Content containers no longer carry an internal "top gap", so the body's bottom inset becomes the only padding below the last row.
    local function sizeContentSection(section, contentH)
        local helperH = math.max(section.helper:GetStringHeight(), CB_H)
        section:SetHeight(helperH + HELPER_GAP + contentH + SECTION_INNER_PAD * 2)
    end

    local function resizePanel()
        sizeContentSection(channelsSection, channelContainer:GetHeight())
        sizeContentSection(keywordsSection, keywordsContainer:GetHeight())
        sizeContentSection(outputsSection, outputContainer:GetHeight())
        sizeContentSection(optionsSection, ROW_H + ROW_GAP + CB_H)

        local sectionsH = channelsSection:GetHeight() + SECTION_GAP +
            keywordsSection:GetHeight() + SECTION_GAP +
            outputsSection:GetHeight() + SECTION_GAP +
            optionsSection:GetHeight()
        local footerH = SECTION_GAP + ROW_H + PAD
        f:SetHeight(PAD_TOP + sectionsH + footerH)
    end
    f.resizePanel = resizePanel

    local function refreshChannelList()
        local store = loadStore()
        local channelsH = rebuildChannels(channelContainer, store)
        channelContainer:SetHeight(math.max(channelsH, CB_H))
    end

    f:SetScript("OnShow", function()
        local store = loadStore()

        -- Keep runtime values in sync so the picker and Test button reflect the saved sound even when a scan hasn't been started yet.
        activeOptions.playSound = store.playSound ~= false
        activeOptions.soundId = store.soundId or DEFAULT_SOUND_ID

        refreshChannelList()
        populateRows(store)

        local outH = buildOutputs(outputContainer, store)
        outputContainer:SetHeight(math.max(outH, CB_H))

        soundCheck:SetChecked(store.playSound ~= false)
        soundDropdown:GenerateMenu()

        -- Refresh the channel list live as the player joins or leaves channels.
        f:RegisterEvent("CHANNEL_UI_UPDATE")
        f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

        refreshStartBtn()
        updateStatus()
        resizePanel()
    end)

    f:SetScript("OnHide", function()
        f:UnregisterEvent("CHANNEL_UI_UPDATE")
        f:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    end)

    f:SetScript("OnEvent", function(self)
        if not self:IsShown() then return end
        refreshChannelList()
        resizePanel()
    end)

    tinsert(UISpecialFrames, "ChatScanPanel")
    f:Hide()
    return f
end

local function togglePanel()
    if not panel then panel = buildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

local function setupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if LDBIcon:IsRegistered(ADDON_NAME) then return end

    local dataObject = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = ADDON_NAME,
        icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
        OnClick = function(_, button)
            if button == "LeftButton" then
                togglePanel()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(ADDON_NAME)
            if scanning then
                tt:AddLine("|cff00ff00Scanning|r — " .. matchLabel(matchCount) .. " this session.", 1, 1, 1)
                if lastMatchSender then
                    tt:AddLine(string.format("Last: %s at %s", lastMatchSender, lastMatchStamp or "?"), 1, 1, 1)
                end
            end
            tt:AddLine("|cffffd200Left-click|r to toggle the panel.", 1, 1, 1)
            tt:AddLine("|cffffd200/cs <KEYWORD>|r adds a keyword and starts scanning.", 1, 1, 1)
            tt:AddLine("|cffffd200/cs <KW1>,<KW2>|r adds an AND combination.", 1, 1, 1)
            tt:AddLine("|cffffd200/cs start|r begins a scan.", 1, 1, 1)
            tt:AddLine("|cffffd200/cs stop|r ends the scan.", 1, 1, 1)
            tt:AddLine("|cffffd200/cs clear|r empties the keyword list.", 1, 1, 1)
        end,
    })

    LDBIcon:Register(ADDON_NAME, dataObject, ChatScanDB.minimap)
end

local function refreshPanelIfShown()
    if panel and panel:IsShown() then
        local store = loadStore()
        populateRows(store)
        if panel.refreshStartBtn then panel.refreshStartBtn() end
    end
end

SLASH_CHATSCAN1 = "/cs"
SLASH_CHATSCAN2 = "/chatscan"
SlashCmdList["CHATSCAN"] = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    local lower = raw:lower()

    if raw == "" then
        togglePanel()
        return
    end

    if lower == "start" then
        if scanning then
            notify("Already scanning.")
        elseif startScan() and panel then
            panel.refreshStartBtn()
        end
        return
    end

    if lower == "stop" then
        if scanning then
            stopScan()
            if panel then panel.refreshStartBtn() end
        else
            notify("Not scanning.")
        end
        return
    end

    if lower == "clear" then
        local store = loadStore()
        if #store.keywords == 0 then
            notify("Keyword list is already empty.")
            return
        end
        store.keywords = {}
        parsedGroups = {}
        notify("Keyword list cleared.")
        refreshPanelIfShown()
        return
    end

    -- Treat as a keyword (or comma-separated AND group).
    local store = loadStore()
    for _, existing in ipairs(store.keywords) do
        if existing:lower() == lower then
            notify("Already tracking: " .. existing)
            if not scanning and startScan() and panel then
                panel.refreshStartBtn()
            end
            return
        end
    end
    store.keywords[#store.keywords + 1] = raw
    parsedGroups = parseKeywords(store.keywords)
    notify("Added keyword: " .. raw)
    refreshPanelIfShown()
    if not scanning then
        if startScan() and panel then panel.refreshStartBtn() end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        loadStore()
    elseif event == "PLAYER_LOGIN" then
        setupMinimapButton()
        local store = loadStore()
        if not store.scanEnabled then return end
        loadRuntime(store)
        if #parsedGroups > 0 and countTrue(activeChannels) > 0 then
            if not scanFrame:IsEventRegistered("CHAT_MSG_CHANNEL") then
                scanFrame:RegisterEvent("CHAT_MSG_CHANNEL")
            end
            scanning = true
            notifyScanning()
        else
            store.scanEnabled = false
        end
    end
end)
