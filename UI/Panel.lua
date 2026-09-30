local _, ns = ...

local Scanner = ns.Scanner
local Store = ns.Store

-- One list row: checkboxes shrink from the template's 32px to the 24px of the close button that
-- removes a keyword row. INPUT_H is the height of InputBoxTemplate's border art.
local ROW_H = 24
local INPUT_H = 20

-- Two equal content wells side by side, inside the template's own inset margins.
local PANEL_W = 616
local COLUMN_GAP = 4
local COLUMN_W = (PANEL_W - PANEL_INSET_LEFT_OFFSET + PANEL_INSET_RIGHT_OFFSET - COLUMN_GAP) / 2

-- Padding inside a content well, the gap under a heading, the gap between controls, and the gap
-- between sections.
local PAD = 12
local TEXT_GAP = 4
local GAP = 8
local SECTION_GAP = 16

local DROPDOWN_W = 160
local ADD_W = 56
local TEST_W = 64

-- InputBoxTemplate draws its left border 5px outside the edit box, so the box sits in a little to
-- line the visible border up with the checkbox art above it.
local INPUT_INSET = 8
local KEYWORD_GAP = 4

local panel

local function createText(parent, font)
    local text = parent:CreateFontString(nil, "ARTWORK")
    text:SetFontObject(font)
    text:SetJustifyH("LEFT")
    return text
end

local function createButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetText(label)
    return button
end

-- The box shrinks to the row; the label keeps the template's own anchor beside it.
local function createCheckbox(parent)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(ROW_H, ROW_H)
    checkbox.Text:SetFontObject(GameFontHighlight)
    return checkbox
end

-- A checkbox list with a pool, so channel joins and tab changes never leak frames.
local function createCheckList(container, emptyText)
    local list = { active = {}, pool = {} }
    local empty = createText(container, GameFontDisableSmall)
    empty:SetPoint("LEFT", container, "TOPLEFT", 0, -ROW_H / 2)
    empty:SetText(emptyText)

    -- Renders entries top-down and returns the height used.
    function list:Render(entries, isChecked, onClick)
        for _, checkbox in ipairs(self.active) do
            checkbox:Hide()
            self.pool[#self.pool + 1] = checkbox
        end
        wipe(self.active)
        empty:SetShown(#entries == 0)

        for i, entry in ipairs(entries) do
            local checkbox = table.remove(self.pool) or createCheckbox(container)
            checkbox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * ROW_H)
            checkbox.Text:SetText(entry.name)
            checkbox:SetChecked(isChecked(entry))
            checkbox:SetScript("OnClick", function(self) onClick(entry, self:GetChecked()) end)
            checkbox:Show()
            self.active[i] = checkbox
        end
        return math.max(#entries, 1) * ROW_H
    end

    return list
end

-- Community channels are named Community:<clubId>:<streamId>, which Blizzard's chat shows as the
-- community and stream name. C_Club names turn secret in chat lockdown and are missing before the
-- club loads, so the raw name stays then; every other channel name passes through unchanged.
local function channelLabel(name)
    local clubId = ChatFrameUtil.GetCommunityAndStreamFromChannel(name)
    if not clubId or C_ChatInfo.InChatMessagingLockdown() or not C_Club.GetClubInfo(clubId) then
        return name
    end
    return ChatFrameUtil.ResolveChannelName(name)
end

-- Every channel the player is in, community channels included. The key stays the raw channel name,
-- so a renamed community keeps its tick.
local function channelEntries()
    local list = { GetChannelList() }
    local entries, seen = {}, {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        local key = ns.channelKey(name)
        if not seen[key] then
            seen[key] = true
            entries[#entries + 1] = { name = channelLabel(name), key = key }
        end
    end
    return entries
end

-- A heading, a grey helper line and a content frame. Only TOP* anchors, so every frame has one
-- vertical constraint; the helper's two anchors give it the width it needs to measure its wrap.
local function createSection(column, title, helperText)
    local section = CreateFrame("Frame", nil, column)
    section:SetPoint("TOPLEFT", PAD, -PAD)
    section:SetPoint("TOPRIGHT", -PAD, -PAD)

    local heading = createText(section, GameFontNormal)
    heading:SetPoint("TOPLEFT")
    heading:SetText(title)

    local helper = createText(section, GameFontDisableSmall)
    helper:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -TEXT_GAP)
    helper:SetPoint("TOPRIGHT", 0, 0)
    helper:SetText(helperText)

    section.content = CreateFrame("Frame", nil, section)
    section.content:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -GAP)
    section.content:SetPoint("TOPRIGHT", helper, "BOTTOMRIGHT", 0, -GAP)

    -- Height follows the measured text, so a long helper line never overlaps the content.
    function section:Layout(contentHeight)
        self.content:SetHeight(contentHeight)
        self:SetHeight(heading:GetStringHeight() + TEXT_GAP + helper:GetStringHeight() + GAP + contentHeight)
    end

    return section
end

-- Stacks laid-out sections in a column and returns the height the column needs.
local function stackSections(column, sections)
    local height = PAD
    for i, section in ipairs(sections) do
        if i > 1 then
            height = height + SECTION_GAP
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT", sections[i - 1], "BOTTOMLEFT", 0, -SECTION_GAP)
            section:SetPoint("TOPRIGHT", sections[i - 1], "BOTTOMRIGHT", 0, -SECTION_GAP)
        end
        height = height + section:GetHeight()
    end
    return height + PAD
end

-- Keyword rows mirror the slash command: one row is an OR group, commas inside it are AND terms.
-- The trailing row is always empty and ready for the next rule.
local KeywordRows = { active = {}, pool = {} }

local function persistKeywords()
    local keywords = {}
    for _, row in ipairs(KeywordRows.active) do
        if row.saved then keywords[#keywords + 1] = row.saved end
    end
    Store.Get().keywords = keywords
    Scanner.ReloadKeywords()
end

-- A row already saved in any case is not stored twice, the same rule as /cs <keyword>.
local function commitRow(row)
    local typed = ns.trim(row.editBox:GetText())
    if typed == "" then return end
    local lower = typed:lower()
    for _, other in ipairs(KeywordRows.active) do
        if other ~= row and other.saved and other.saved:lower() == lower then
            typed = row.saved
            break
        end
    end
    row.saved = typed
    row.editBox:SetText(typed or "")
    row.editBox:ClearFocus()
    row:UpdateState()
    persistKeywords()
    panel:RefreshKeywords()
end

local function deleteRow(row)
    tDeleteItem(KeywordRows.active, row)
    row.saved = nil
    row:Hide()
    KeywordRows.pool[#KeywordRows.pool + 1] = row
    persistKeywords()
    panel:RefreshKeywords()
end

-- An empty row shows no button, a typed row shows Add, a saved and unchanged row shows remove.
local function createKeywordRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(256)
    editBox:SetHeight(INPUT_H)
    row.editBox = editBox

    local addBtn = createButton(row, "Add", ADD_W)
    addBtn:SetPoint("RIGHT")

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    removeBtn:SetPoint("RIGHT")

    function row:UpdateState()
        local typed = ns.trim(editBox:GetText())
        local isSaved = self.saved ~= nil and typed == self.saved
        local isTyped = typed ~= "" and not isSaved
        addBtn:SetShown(isTyped)
        removeBtn:SetShown(isSaved)

        editBox:ClearAllPoints()
        editBox:SetPoint("LEFT", INPUT_INSET, 0)
        if isSaved then
            editBox:SetPoint("RIGHT", removeBtn, "LEFT", -GAP, 0)
        elseif isTyped then
            editBox:SetPoint("RIGHT", addBtn, "LEFT", -GAP, 0)
        else
            editBox:SetPoint("RIGHT")
        end
    end

    editBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then row:UpdateState() end
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(row.saved or "")
        self:ClearFocus()
        row:UpdateState()
    end)
    editBox:SetScript("OnEnterPressed", function() commitRow(row) end)
    addBtn:SetScript("OnClick", function() commitRow(row) end)
    removeBtn:SetScript("OnClick", function() deleteRow(row) end)

    return row
end

local function addKeywordRow(parent, keyword)
    local row = table.remove(KeywordRows.pool) or createKeywordRow(parent)
    row.saved = keyword
    row.editBox:SetText(keyword or "")
    row.editBox:SetCursorPosition(0)
    row:UpdateState()
    row:Show()
    KeywordRows.active[#KeywordRows.active + 1] = row
end

-- Keeps one empty row at the end, lays rows out top-down and returns the height used.
local function layoutKeywordRows(parent)
    local last = KeywordRows.active[#KeywordRows.active]
    if not last or last.saved then addKeywordRow(parent, nil) end

    for i, row in ipairs(KeywordRows.active) do
        local y = -(i - 1) * (ROW_H + KEYWORD_GAP)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    end
    local count = #KeywordRows.active
    return count * ROW_H + (count - 1) * KEYWORD_GAP
end

local function populateKeywordRows(parent)
    for i = #KeywordRows.active, 1, -1 do
        local row = KeywordRows.active[i]
        row:Hide()
        KeywordRows.pool[#KeywordRows.pool + 1] = row
        KeywordRows.active[i] = nil
    end
    for _, keyword in ipairs(Store.Get().keywords) do
        addKeywordRow(parent, keyword)
    end
end

-- A ButtonFrameTemplate tool window with the addon icon as portrait, moved by dragging and closed
-- with Escape.
local function createWindow()
    local frame = CreateFrame("Frame", "ChatScanFrame", UIParent, "ButtonFrameTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle(ns.TITLE)
    frame:SetPortraitToAsset(ns.ICON)
    tinsert(UISpecialFrames, frame:GetName())
    frame:Hide()
    return frame
end

-- The template's Inset becomes the left well and a second InsetFrameTemplate the right one, both on
-- Blizzard's own inset offsets.
local function createColumns(frame)
    local left = frame.Inset
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + COLUMN_W, PANEL_INSET_BOTTOM_BUTTON_OFFSET)

    local right = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", COLUMN_GAP, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET)
    return left, right
end

-- The alert toggle, a named sound picker that previews each pick, and a Test button. Returns the
-- toggle, the picker and the height they use.
local function createSoundControls(content)
    local soundCheck = createCheckbox(content)
    soundCheck:SetPoint("TOPLEFT")
    soundCheck.Text:SetText("Play sound on match")
    soundCheck:SetScript("OnClick", function(self)
        Store.Get().playSound = self:GetChecked()
    end)

    -- Only the width is set, so the dropdown keeps the template's own height.
    local soundDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    soundDropdown:SetWidth(DROPDOWN_W)
    soundDropdown:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -TEXT_GAP)
    soundDropdown:SetDefaultText("Choose a sound")
    soundDropdown:SetupMenu(function(_, root)
        for _, sound in ipairs(ns.SOUNDS) do
            root:CreateRadio(sound.name,
                function() return Store.Get().soundId == sound.id end,
                function()
                    Store.Get().soundId = sound.id
                    PlaySound(sound.id)
                end)
        end
    end)

    local testBtn = createButton(content, "Test", TEST_W)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", GAP, 0)
    testBtn:SetScript("OnClick", function() PlaySound(Store.Get().soundId) end)

    return soundCheck, soundDropdown, ROW_H + TEXT_GAP + soundDropdown:GetHeight()
end

-- The live status sits in the attic, right of the portrait and centred between title bar and wells.
local function createStatusLine(frame, right)
    local status = createText(frame, GameFontHighlight)
    status:SetPoint("TOPLEFT", frame.TitleContainer, "BOTTOMLEFT")
    status:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT")
    status:SetJustifyV("MIDDLE")
    return status
end

-- The primary action in the button bar's bottom-right corner. MagicButton_OnLoad turns the zero
-- offsets into Blizzard's corner offsets, so it runs once the anchor exists.
local function createStartButton(frame)
    local startBtn = CreateFrame("Button", nil, frame, "MagicButtonTemplate")
    startBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    MagicButton_OnLoad(startBtn)
    startBtn:SetScript("OnClick", function()
        if Scanner.scanning then Scanner.Stop() else Scanner.Start() end
    end)
    return startBtn
end

local function buildPanel()
    local frame = createWindow()
    local left, right = createColumns(frame)

    local channelsSection = createSection(left, "Scanned Channels",
        "Pick which chat channels to scan. Zone channels stay selected when you change zones.")
    local keywordsSection = createSection(left, "Keywords",
        "Each row matches on its own (OR). Separate keywords in one row with commas to require all of them (AND). Press Enter or Add to save a row.")
    local outputsSection = createSection(right, "Output Tabs",
        "Pick which chat tabs receive matches. With none selected, matches go to the default chat frame.")
    local soundSection = createSection(right, "Alert Sound",
        "Play a sound when a keyword matches, at most once every 3 seconds.")

    local channelList = createCheckList(channelsSection.content, "Not in any channels")
    local outputList = createCheckList(outputsSection.content, "No chat tabs available")
    local soundCheck, soundDropdown, soundH = createSoundControls(soundSection.content)
    local status = createStatusLine(frame, right)
    local startBtn = createStartButton(frame)

    -- The button label and the status line show whether a scan runs.
    function frame:RefreshStatus()
        local count = ns.matchLabel(Scanner.matchCount)
        if Scanner.scanning then
            startBtn:SetText("Stop")
            -- A running scan can be unable to match while the client withholds chat text, or once
            -- every keyword or channel is gone.
            if Scanner.chatLocked then
                status:SetText(WARNING_FONT_COLOR:WrapTextInColorCode("Chat locked by client") .. "  matching paused")
            elseif not Scanner.CanMatch() then
                status:SetText(WARNING_FONT_COLOR:WrapTextInColorCode("Nothing to match") .. "  add a keyword and tick a channel")
            else
                status:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("Scanning") .. "  " .. count)
            end
        else
            startBtn:SetText("Start")
            if Scanner.matchCount > 0 then
                status:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("Stopped") .. "  " .. count .. " this session")
            else
                status:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("Not scanning"))
            end
        end
    end

    local channelsH, keywordsH, outputsH = ROW_H, ROW_H, ROW_H

    -- The window grows with its content: the attic, the taller well and the button bar.
    function frame:Resize()
        channelsSection:Layout(channelsH)
        keywordsSection:Layout(keywordsH)
        outputsSection:Layout(outputsH)
        soundSection:Layout(soundH)
        local leftH = stackSections(left, { channelsSection, keywordsSection })
        local rightH = stackSections(right, { outputsSection, soundSection })
        self:SetHeight(math.ceil(-PANEL_INSET_ATTIC_OFFSET + math.max(leftH, rightH) + PANEL_INSET_BOTTOM_BUTTON_OFFSET))
    end

    function frame:RefreshChannels()
        local channels = Store.Get().inputChannels
        channelsH = channelList:Render(channelEntries(),
            function(entry) return channels[entry.key] end,
            function(entry, checked)
                channels[entry.key] = checked or nil
                self:RefreshStatus()
            end)
        self:Resize()
    end

    function frame:RefreshOutputs()
        local outputs = Store.Get().outputs
        outputsH = outputList:Render(Scanner.OutputWindows(),
            function(entry) return outputs[entry.key] end,
            function(entry, checked) outputs[entry.key] = checked or nil end)
        self:Resize()
    end

    function frame:RefreshKeywords()
        keywordsH = layoutKeywordRows(keywordsSection.content)
        self:Resize()
    end

    function frame:PopulateKeywords()
        populateKeywordRows(keywordsSection.content)
        self:RefreshKeywords()
    end

    -- The channel list stays live while the panel is open.
    frame:SetScript("OnShow", function(self)
        soundCheck:SetChecked(Store.Get().playSound)
        soundDropdown:GenerateMenu()
        self:RefreshChannels()
        self:RefreshOutputs()
        self:PopulateKeywords()
        self:RefreshStatus()
        self:RegisterEvent("CHANNEL_UI_UPDATE")
        self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
    end)
    frame:SetScript("OnEvent", function(self)
        self:RefreshChannels()
    end)

    Scanner.OnChanged(function()
        if frame:IsShown() then frame:RefreshStatus() end
    end)

    return frame
end

function ns.TogglePanel()
    panel = panel or buildPanel()
    panel:SetShown(not panel:IsShown())
end

-- Called after slash commands change keywords, so an open panel mirrors the store.
function ns.RefreshPanel()
    if panel and panel:IsShown() then panel:PopulateKeywords() end
end
