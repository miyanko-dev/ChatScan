local ADDON_NAME = "ChatScan"
local PREFIX = "|cffffff00[ChatScan]:|r "

local RAID_ICONS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

local DEDUP_TTL = 10
local DEDUP_MAX = 20
local MATCH_SOUND = 3175
local SOUND_THROTTLE = 3.0

local COMBAT_LOG_INDEX = 2

local panel
local channelCheckboxes = {}
local outputCheckboxes = {}
local channelListChildren = {}
local outputListChildren = {}
local keywordRowsActive = {}
local keywordRowPool = {}
local keywordsContainer
local keywordAddBtn
local addKeywordRow, removeKeywordRow, layoutKeywordRows

local scanning = false
local scanFrame = CreateFrame("Frame")
local parsedGroups = {}
local activeChannels = {}
local activeOutputs = {}
local activeOptions = { playSound = true }
local recentMatches = {}
local lastSoundTime = 0

local function notify(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
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
    }
    local store = ChatScanDB[key]
    store.inputChannels = store.inputChannels or {}
    store.outputs = store.outputs or {}
    store.keywords = store.keywords or {}
    if store.scanEnabled == nil then store.scanEnabled = false end
    if store.playSound == nil then store.playSound = true end
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

local function showMatch(msg, sender)
    local rendered = renderIcons(msg)
    local line = "|Hplayer:" .. sender .. "|h|cffffff00[" .. sender .. "]:|r|h " .. rendered

    local delivered = false
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        if i ~= COMBAT_LOG_INDEX then
            local name = GetChatWindowInfo and GetChatWindowInfo(i)
            if name and name ~= "" and activeOutputs[strlower(name)] then
                local frame = _G["ChatFrame" .. i]
                if frame then
                    frame:AddMessage(line)
                    delivered = true
                end
            end
        end
    end
    if not delivered then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
    if activeOptions.playSound then
        local now = GetTime()
        if now - lastSoundTime >= SOUND_THROTTLE then
            PlaySound(MATCH_SOUND, "Master", true)
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
    showMatch(msg, sender or UNKNOWN or "?")
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
end

local function countTrue(t)
    local n = 0
    for _, v in pairs(t) do if v then n = n + 1 end end
    return n
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
    notify(string.format("Scanning %d channel(s) for %d keyword group(s).",
        countTrue(activeChannels), #parsedGroups))
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

local function rebuildChannels(parent, anchorTop, store, topGap)
    clearChildren(channelListChildren)
    wipe(channelCheckboxes)

    local list = { GetChannelList() }
    local entries = {}
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if name and name ~= "" then
            entries[#entries + 1] = { id = id, name = name }
        end
    end

    topGap = topGap or 4
    local yOffset = -topGap
    if #entries == 0 then
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", anchorTop, "BOTTOMLEFT", 4, yOffset)
        fs:SetText("(not in any channels)")
        channelListChildren[#channelListChildren + 1] = fs
        return fs, topGap + 12
    end

    local lastFrame = anchorTop
    for _, entry in ipairs(entries) do
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, yOffset)
        if cb.Text then
            cb.Text:SetText(entry.name)
            cb.Text:SetFontObject(GameFontHighlightSmall)
        else
            local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            fs:SetText(entry.name)
        end
        local nameKey = strlower(entry.name)
        cb:SetChecked(store.inputChannels[nameKey] and true or false)
        cb:SetScript("OnClick", function(self)
            store.inputChannels[nameKey] = self:GetChecked() and true or nil
        end)
        channelListChildren[#channelListChildren + 1] = cb
        channelCheckboxes[nameKey] = cb
        lastFrame = cb
        yOffset = -4
    end
    local totalHeight = topGap + 20 + math.max(0, #entries - 1) * 24
    return lastFrame, totalHeight
end

local function buildOutputs(parent, anchorTop, store, topGap)
    clearChildren(outputListChildren)
    wipe(outputCheckboxes)

    local entries = {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        if i ~= COMBAT_LOG_INDEX then
            local name = GetChatWindowInfo and GetChatWindowInfo(i)
            if name and name ~= "" then
                entries[#entries + 1] = { index = i, name = name }
            end
        end
    end

    topGap = topGap or 4
    local yOffset = -topGap
    if #entries == 0 then
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", anchorTop, "BOTTOMLEFT", 4, yOffset)
        fs:SetText("(no chat tabs available)")
        outputListChildren[#outputListChildren + 1] = fs
        return fs, topGap + 12
    end

    local lastFrame = anchorTop
    for _, entry in ipairs(entries) do
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, yOffset)
        if cb.Text then
            cb.Text:SetText(entry.name)
            cb.Text:SetFontObject(GameFontHighlightSmall)
        else
            local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            fs:SetText(entry.name)
        end
        local nameKey = strlower(entry.name)
        cb:SetChecked(store.outputs[nameKey] and true or false)
        cb:SetScript("OnClick", function(self)
            store.outputs[nameKey] = self:GetChecked() and true or nil
        end)
        outputListChildren[#outputListChildren + 1] = cb
        outputCheckboxes[nameKey] = cb
        lastFrame = cb
        yOffset = -4
    end
    local totalHeight = topGap + 20 + math.max(0, #entries - 1) * 24
    return lastFrame, totalHeight
end

local function createKeywordRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetMaxLetters(256)
    eb:SetHeight(20)
    eb:SetPoint("LEFT", row, "LEFT", 8, 0)
    eb:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    row.editBox = eb

    local rm = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    rm:SetSize(20, 20)
    rm:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    rm:SetScript("OnClick", function() removeKeywordRow(row) end)
    row.removeBtn = rm

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
    row.editBox:SetText("")
    row:ClearAllPoints()
    row:Hide()
    keywordRowPool[#keywordRowPool + 1] = row
end

function addKeywordRow(text)
    local row = acquireRow()
    row.editBox:SetText(text or "")
    row.editBox:SetCursorPosition(0)
    keywordRowsActive[#keywordRowsActive + 1] = row
end

function removeKeywordRow(row)
    for i, r in ipairs(keywordRowsActive) do
        if r == row then
            table.remove(keywordRowsActive, i)
            releaseRow(row)
            break
        end
    end
    if #keywordRowsActive == 0 then
        addKeywordRow("")
    end
    layoutKeywordRows()
end

function layoutKeywordRows()
    local rowHeight = 24
    for i, row in ipairs(keywordRowsActive) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", keywordsContainer, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", keywordsContainer, "RIGHT", 0, 0)
        row:SetHeight(20)
    end
    local total = math.max(#keywordRowsActive * rowHeight - 4, 20)
    keywordsContainer:SetHeight(total)
    if panel and panel.resizePanel then
        panel.resizePanel()
    end
    return total
end

local function collectKeywords()
    local out = {}
    for _, row in ipairs(keywordRowsActive) do
        local text = row.editBox:GetText() or ""
        text = text:match("^%s*(.-)%s*$")
        if text ~= "" then
            out[#out + 1] = text
        end
    end
    return out
end

local function populateRows(store)
    for _, row in ipairs(keywordRowsActive) do
        releaseRow(row)
    end
    wipe(keywordRowsActive)
    if #store.keywords > 0 then
        for _, k in ipairs(store.keywords) do
            addKeywordRow(k)
        end
    else
        addKeywordRow("")
    end
end

-- Panel chrome (shared visual style across the addon's panels).
local PANEL_PAD = 14
local PANEL_PAD_TOP = 52       -- clears the dialog-box-header banner above the first section.
local PANEL_PAD_BOTTOM = 14
local SECTION_GAP = 22
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local HELPER_GAP = 8
local BTN_H = 22

-- Native Blizzard dialog-frame backdrop (matches AceGUI Frame, which is what
-- Questie's options panel uses). DialogBox-Border has the metallic look with
-- decorative corners; DialogBox-Background is the standard tan parchment.
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

-- Native Blizzard dialog-box header banner (Interface\DialogFrame\UI-DialogBox-Header)
-- composed as three texture pieces (left cap, repeating middle, right cap),
-- centered at the parent's top edge and overlapping into the frame interior.
-- Same texture coords AceGUI uses for its Frame title.
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

    -- Channels section
    local channelsSection = buildSection(f, "Channels")
    channelsSection:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_PAD, -PANEL_PAD_TOP)
    channelsSection:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PANEL_PAD, -PANEL_PAD_TOP)

    local channelsHelper = channelsSection.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    channelsHelper:SetPoint("TOPLEFT", channelsSection.body, "TOPLEFT", 0, 0)
    channelsHelper:SetPoint("RIGHT", channelsSection.body, "RIGHT", 0, 0)
    channelsHelper:SetJustifyH("LEFT")
    channelsHelper:SetWordWrap(true)
    channelsHelper:SetText("Pick which chat channels to scan for keyword matches.")

    local channelContainer = CreateFrame("Frame", nil, channelsSection.body)
    channelContainer:SetPoint("TOPLEFT", channelsHelper, "BOTTOMLEFT", 0, -HELPER_GAP)
    channelContainer:SetPoint("RIGHT", channelsSection.body, "RIGHT", 0, 0)
    channelContainer:SetHeight(20)

    -- Keywords section
    local keywordsSection = buildSection(f, "Keywords")
    keywordsSection:SetPoint("TOPLEFT", channelsSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    keywordsSection:SetPoint("TOPRIGHT", channelsSection, "BOTTOMRIGHT", 0, -SECTION_GAP)

    local keywordsHelper = keywordsSection.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    keywordsHelper:SetPoint("TOPLEFT", keywordsSection.body, "TOPLEFT", 0, 0)
    keywordsHelper:SetPoint("RIGHT", keywordsSection.body, "RIGHT", 0, 0)
    keywordsHelper:SetJustifyH("LEFT")
    keywordsHelper:SetWordWrap(true)
    keywordsHelper:SetText("Each row matches independently (OR). Inside a row, separate keywords with commas to require all of them (AND).")

    keywordsContainer = CreateFrame("Frame", nil, keywordsSection.body)
    keywordsContainer:SetPoint("TOPLEFT", keywordsHelper, "BOTTOMLEFT", 0, -HELPER_GAP)
    keywordsContainer:SetPoint("RIGHT", keywordsSection.body, "RIGHT", 0, 0)
    keywordsContainer:SetHeight(20)

    keywordAddBtn = CreateFrame("Button", nil, keywordsSection.body, "UIPanelButtonTemplate")
    keywordAddBtn:SetSize(140, BTN_H)
    keywordAddBtn:SetPoint("TOPLEFT", keywordsContainer, "BOTTOMLEFT", 0, -HELPER_GAP)
    keywordAddBtn:SetText("Add keyword group")
    keywordAddBtn:SetScript("OnClick", function()
        addKeywordRow("")
        layoutKeywordRows()
    end)

    -- Outputs section
    local outputsSection = buildSection(f, "Channel Match Display")
    outputsSection:SetPoint("TOPLEFT", keywordsSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    outputsSection:SetPoint("TOPRIGHT", keywordsSection, "BOTTOMRIGHT", 0, -SECTION_GAP)

    local outputsHelper = outputsSection.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    outputsHelper:SetPoint("TOPLEFT", outputsSection.body, "TOPLEFT", 0, 0)
    outputsHelper:SetPoint("RIGHT", outputsSection.body, "RIGHT", 0, 0)
    outputsHelper:SetJustifyH("LEFT")
    outputsHelper:SetWordWrap(true)
    outputsHelper:SetText("Pick which chat tabs receive keyword matches. If none are selected, the default chat frame is used.")

    local outputContainer = CreateFrame("Frame", nil, outputsSection.body)
    outputContainer:SetPoint("TOPLEFT", outputsHelper, "BOTTOMLEFT", 0, -HELPER_GAP)
    outputContainer:SetPoint("RIGHT", outputsSection.body, "RIGHT", 0, 0)
    outputContainer:SetHeight(20)

    -- Options section
    local optionsSection = buildSection(f, "Options")
    optionsSection:SetPoint("TOPLEFT", outputsSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    optionsSection:SetPoint("TOPRIGHT", outputsSection, "BOTTOMRIGHT", 0, -SECTION_GAP)

    local soundCheck = CreateFrame("CheckButton", nil, optionsSection.body, "UICheckButtonTemplate")
    soundCheck:SetSize(20, 20)
    soundCheck:SetPoint("TOPLEFT", optionsSection.body, "TOPLEFT", 0, 0)
    if soundCheck.Text then
        soundCheck.Text:SetText("Play sound on match")
        soundCheck.Text:SetFontObject(GameFontHighlightSmall)
    else
        local fs = soundCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", soundCheck, "RIGHT", 2, 0)
        fs:SetText("Play sound on match")
    end
    soundCheck:SetScript("OnClick", function(self)
        local store = loadStore()
        local checked = self:GetChecked() and true or false
        store.playSound = checked
        activeOptions.playSound = checked
    end)
    f.soundCheck = soundCheck
    optionsSection:SetHeight(20 + SECTION_INNER_PAD * 2)

    -- Footer buttons
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, BTN_H)
    closeBtn:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD_BOTTOM)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(100, BTN_H)
    startBtn:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD_BOTTOM)
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
    end
    f.refreshStartBtn = refreshStartBtn
    refreshStartBtn()

    startBtn:SetScript("OnClick", function()
        if scanning then
            stopScan()
            refreshStartBtn()
            return
        end
        local store = loadStore()
        store.keywords = collectKeywords()
        notify("Settings saved.")
        if startScan() then
            f:Hide()
        end
    end)

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, BTN_H)
    saveBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local store = loadStore()
        store.keywords = collectKeywords()
        notify("Settings saved.")
    end)

    -- Recomputes per-section heights and the overall panel height from current
    -- helper-text wrap and dynamic list/row heights. Called on show and any
    -- time keyword rows or channel lists change.
    local function resizePanel()
        local channelsHelperH = math.max(channelsHelper:GetStringHeight(), 16)
        local channelsListH = channelContainer:GetHeight()
        channelsSection:SetHeight(channelsHelperH + HELPER_GAP + channelsListH + SECTION_INNER_PAD * 2)

        local keywordsHelperH = math.max(keywordsHelper:GetStringHeight(), 28)
        local keywordsRowsH = keywordsContainer:GetHeight()
        keywordsSection:SetHeight(keywordsHelperH + HELPER_GAP + keywordsRowsH + HELPER_GAP + BTN_H + SECTION_INNER_PAD * 2)

        local outputsHelperH = math.max(outputsHelper:GetStringHeight(), 28)
        local outputsListH = outputContainer:GetHeight()
        outputsSection:SetHeight(outputsHelperH + HELPER_GAP + outputsListH + SECTION_INNER_PAD * 2)

        local sectionsH = channelsSection:GetHeight() + SECTION_GAP +
                          keywordsSection:GetHeight() + SECTION_GAP +
                          outputsSection:GetHeight() + SECTION_GAP +
                          optionsSection:GetHeight()
        local footerH = SECTION_GAP + BTN_H + PANEL_PAD_BOTTOM
        f:SetHeight(PANEL_PAD_TOP + sectionsH + footerH)
    end
    f.resizePanel = resizePanel

    f:SetScript("OnShow", function()
        local store = loadStore()

        local _, channelsHeight = rebuildChannels(channelContainer, channelsHelper, store, HELPER_GAP)
        channelContainer:SetHeight(math.max(channelsHeight, 16))

        populateRows(store)
        layoutKeywordRows()
        C_Timer.After(0, function()
            local first = keywordRowsActive[1]
            if f:IsShown() and first then first.editBox:SetFocus() end
        end)

        local _, outHeight = buildOutputs(outputContainer, outputsHelper, store, HELPER_GAP)
        outputContainer:SetHeight(math.max(outHeight, 16))

        soundCheck:SetChecked(store.playSound ~= false)
        refreshStartBtn()
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
                tt:AddLine("|cff00ff00Scanning active.|r", 1, 1, 1)
            else
                tt:AddLine("|cffffffffClick|r to toggle the panel.", 1, 1, 1)
            end
        end,
    })

    LDBIcon:Register(ADDON_NAME, dataObject, ChatScanDB.minimap)
end

SLASH_CHATSCAN1 = "/cs"
SLASH_CHATSCAN2 = "/chatscan"
SlashCmdList["CHATSCAN"] = function(msg)
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "start" then
        if not scanning and startScan() and panel then
            panel.refreshStartBtn()
        end
    elseif cmd == "stop" then
        stopScan()
        if panel then panel.refreshStartBtn() end
    else
        togglePanel()
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
            notify(string.format("Scanning %d channel(s) for %d keyword group(s).",
                countTrue(activeChannels), #parsedGroups))
        else
            store.scanEnabled = false
        end
    end
end)
