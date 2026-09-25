local _, ns = ...

local Design = ns.Design
local Scanner = ns.Scanner
local Store = ns.Store

local SPACE = Design.SPACE
local FONT = Design.FONT
local CONTROL_H = Design.CONTROL_H

-- Two columns of 296 each: 616 = XS margin + 296 + XS gap + 296 + XS margin.
local PANEL_W = 616
local DROPDOWN_W = 160
local ADD_W = 48
local TEST_W = 64
local START_W = 96

-- InputBoxTemplate draws its left border 5px outside the frame; an XS inset lines the visible
-- border up with the checkbox art above it.
local INPUT_INSET = SPACE.XS

local panel

local function createText(parent, font)
    local text = parent:CreateFontString(nil, "ARTWORK")
    text:SetFontObject(font)
    text:SetJustifyH("LEFT")
    return text
end

local function createButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, CONTROL_H)
    button:SetText(label)
    return button
end

-- UICheckButtonTemplate anchors its label for a 32px box; at CONTROL_H it sits flush right.
local function createCheckbox(parent)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(CONTROL_H, CONTROL_H)
    checkbox.Text:SetFontObject(FONT.TEXT)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT")
    return checkbox
end

-- A checkbox list with a pool, so channel joins and tab changes never leak frames.
local function createCheckList(container, emptyText)
    local list = { active = {}, pool = {} }
    local empty = createText(container, FONT.HELPER)
    empty:SetPoint("LEFT", container, "TOPLEFT", 0, -CONTROL_H / 2)
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
            checkbox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * CONTROL_H)
            checkbox.Text:SetText(entry.name)
            checkbox:SetChecked(isChecked(entry))
            checkbox:SetScript("OnClick", function(self) onClick(entry, self:GetChecked()) end)
            checkbox:Show()
            self.active[i] = checkbox
        end
        return math.max(#entries, 1) * CONTROL_H
    end

    return list
end

local function channelEntries()
    local list = { GetChannelList() }
    local entries, seen = {}, {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        local key = ns.channelKey(name)
        if not seen[key] then
            seen[key] = true
            entries[#entries + 1] = { name = name, key = key }
        end
    end
    return entries
end

-- A heading, a grey helper line and a content frame. Only TOP* anchors, so every frame has one
-- vertical constraint; the helper's two anchors give it the width it needs to measure its wrap.
local function createSection(column, title, helperText)
    local section = CreateFrame("Frame", nil, column)
    section:SetPoint("TOPLEFT", SPACE.S, -SPACE.S)
    section:SetPoint("TOPRIGHT", -SPACE.S, -SPACE.S)

    local heading = createText(section, FONT.HEADING)
    heading:SetPoint("TOPLEFT")
    heading:SetText(title)

    local helper = createText(section, FONT.HELPER)
    helper:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -SPACE.XS)
    helper:SetPoint("TOPRIGHT", 0, 0)
    helper:SetText(helperText)

    section.content = CreateFrame("Frame", nil, section)
    section.content:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -SPACE.XS)
    section.content:SetPoint("TOPRIGHT", helper, "BOTTOMRIGHT", 0, -SPACE.XS)

    -- Height follows the measured helper text, so a long helper never overlaps its content.
    function section:Layout(contentHeight)
        self.content:SetHeight(contentHeight)
        self:SetHeight(heading:GetStringHeight() + SPACE.XS + helper:GetStringHeight() + SPACE.XS + contentHeight)
    end

    return section
end

-- Stacks laid-out sections in a column and returns the height the column needs.
local function stackSections(column, sections)
    local height = SPACE.S
    for i, section in ipairs(sections) do
        if i > 1 then
            height = height + SPACE.M
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT", sections[i - 1], "BOTTOMLEFT", 0, -SPACE.M)
            section:SetPoint("TOPRIGHT", sections[i - 1], "BOTTOMRIGHT", 0, -SPACE.M)
        end
        height = height + section:GetHeight()
    end
    return height + SPACE.S
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

local function commitRow(row)
    local typed = ns.trim(row.editBox:GetText())
    if typed == "" then return end
    for _, other in ipairs(KeywordRows.active) do
        if other ~= row and other.saved == typed then
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
    row:SetHeight(CONTROL_H)

    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(FONT.TEXT)
    editBox:SetMaxLetters(256)
    editBox:SetHeight(CONTROL_H)
    row.editBox = editBox

    local addBtn = createButton(row, "Add", ADD_W)
    addBtn:SetPoint("RIGHT")

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    removeBtn:SetSize(CONTROL_H, CONTROL_H)
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
            editBox:SetPoint("RIGHT", removeBtn, "LEFT", -SPACE.XS, 0)
        elseif isTyped then
            editBox:SetPoint("RIGHT", addBtn, "LEFT", -SPACE.XS, 0)
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
        local y = -(i - 1) * (CONTROL_H + SPACE.XS)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    end
    local count = #KeywordRows.active
    return count * CONTROL_H + (count - 1) * SPACE.XS
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

-- The column insets replace the template's single Inset, in the same band between header and footer.
local function createColumn(frame, side)
    local column = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    local x = side == "LEFT" and SPACE.XS or -SPACE.XS
    column:SetPoint("TOP" .. side, frame, "TOP" .. side, x, -Design.HEADER_H)
    column:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, x, Design.FOOTER_H)
    column:SetWidth((PANEL_W - 3 * SPACE.XS) / 2)
    return column
end

local function buildPanel()
    local frame = CreateFrame("Frame", "ChatScanFrame", UIParent, "ButtonFrameTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle(ns.TITLE .. " " .. C_AddOns.GetAddOnMetadata(ns.name, "Version"))
    frame:SetPortraitToAsset(ns.ICON)
    frame.Inset:Hide()

    local left = createColumn(frame, "LEFT")
    local right = createColumn(frame, "RIGHT")

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

    local soundCheck = createCheckbox(soundSection.content)
    soundCheck:SetPoint("TOPLEFT")
    soundCheck.Text:SetText("Play sound on match")
    soundCheck:SetScript("OnClick", function(self)
        Store.Get().playSound = self:GetChecked()
    end)

    local soundDropdown = CreateFrame("DropdownButton", nil, soundSection.content, "WowStyle1DropdownTemplate")
    soundDropdown:SetSize(DROPDOWN_W, CONTROL_H)
    soundDropdown:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -SPACE.XS)
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

    local testBtn = createButton(soundSection.content, "Test", TEST_W)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", SPACE.XS, 0)
    testBtn:SetScript("OnClick", function() PlaySound(Store.Get().soundId) end)

    local SOUND_H = CONTROL_H + SPACE.XS + CONTROL_H

    -- Footer: live status on the left, Start/Stop on the right, centred on the button row.
    local startBtn = createButton(frame, "Start", START_W)
    startBtn:SetPoint("BOTTOMRIGHT", -SPACE.XS, SPACE.XS)

    local status = createText(frame, FONT.TEXT)
    status:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", SPACE.XS + SPACE.S, SPACE.XS + CONTROL_H)
    status:SetPoint("BOTTOMRIGHT", startBtn, "BOTTOMLEFT", -SPACE.XS, 0)

    -- UIPanelButtonTemplate is a three-slice button with no NormalTexture, so tint its slices.
    local function tintStart(r, g, b)
        startBtn.Left:SetVertexColor(r, g, b)
        startBtn.Middle:SetVertexColor(r, g, b)
        startBtn.Right:SetVertexColor(r, g, b)
    end

    function frame:RefreshStatus()
        local count = ns.matchLabel(Scanner.matchCount)
        if Scanner.scanning then
            startBtn:SetText("Stop")
            tintStart(1, 0.4, 0.4)
            -- A running scan can be unable to match while the client withholds chat text.
            if Scanner.chatLocked then
                status:SetText(WARNING_FONT_COLOR:WrapTextInColorCode("Chat locked by client") .. "  matching paused")
            else
                status:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("Scanning") .. "  " .. count)
            end
        else
            startBtn:SetText("Start")
            tintStart(1, 1, 1)
            if Scanner.matchCount > 0 then
                status:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("Stopped") .. "  " .. count .. " this session")
            else
                status:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("Not scanning"))
            end
        end
    end

    startBtn:SetScript("OnClick", function()
        if Scanner.scanning then Scanner.Stop() else Scanner.Start() end
    end)

    local channelsH, keywordsH, outputsH = CONTROL_H, CONTROL_H, CONTROL_H

    function frame:Resize()
        channelsSection:Layout(channelsH)
        keywordsSection:Layout(keywordsH)
        outputsSection:Layout(outputsH)
        soundSection:Layout(SOUND_H)
        local leftH = stackSections(left, { channelsSection, keywordsSection })
        local rightH = stackSections(right, { outputsSection, soundSection })
        self:SetHeight(Design.HEADER_H + Design.Snap(math.max(leftH, rightH)) + Design.FOOTER_H)
    end

    function frame:RefreshChannels()
        local channels = Store.Get().inputChannels
        channelsH = channelList:Render(channelEntries(),
            function(entry) return channels[entry.key] end,
            function(entry, checked) channels[entry.key] = checked or nil end)
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

    tinsert(UISpecialFrames, frame:GetName())
    frame:Hide()
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
