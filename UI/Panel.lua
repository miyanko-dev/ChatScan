local _, ns = ...

local Scanner = ns.Scanner
local Store = ns.Store
local Compat = ns.Compat

-- ButtonFrameTemplate anchors its Inset at TOPLEFT (4, -60) and BOTTOMRIGHT (-6, 26) on both 1.15.9 and 1.60.1; the panel is sized from these so the two column insets fill exactly that area.
local INSET_TOP = 60
local INSET_BOTTOM = 26
local INSET_LEFT = 4
local INSET_RIGHT = 6

local PANEL_W = 620
local COL_GAP = 4
local PAD = 12                -- inset border -> content
local GAP = 8                 -- between sibling widgets
local SECTION_GAP = 16        -- between two sections in a column
local ROW_H = 22              -- native UIPanelButton / input height
local DROPDOWN_H = 24         -- WowStyle1DropdownTemplate is 60x24 on 1.15.x and 120x25 on 1.60.x
local ROW_GAP = 4
local CB_SIZE = 24
local HEADER_GAP = 6          -- header -> helper, helper -> content
local BUTTON_BAR_Y = 4        -- button bar content sits this far above the frame bottom
local ATTIC_TEXT_X = 62       -- same left edge the template gives its own title text

local panel

-- UICheckButtonTemplate exposes .Text on both clients; the template anchors it for a 32px box, so re-anchor for the 24px size.
local function setCheckboxLabel(checkButton, text)
    local label = checkButton.Text
    if not label then
        label = checkButton:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        checkButton.Text = label
    end
    label:SetFontObject(GameFontHighlight)
    label:SetText(text)
    label:ClearAllPoints()
    label:SetPoint("LEFT", checkButton, "RIGHT", 2, 0)
end

-- Checkbox pool per list, so channel joins and reloads never leak frames.
local function acquireCheckbox(list, parent)
    local cb = table.remove(list.pool)
    if not cb then
        cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(CB_SIZE, CB_SIZE)
    end
    cb:SetParent(parent)
    cb:Show()
    list.active[#list.active + 1] = cb
    return cb
end

local function releaseCheckboxes(list)
    for _, cb in ipairs(list.active) do
        cb:Hide()
        cb:ClearAllPoints()
        cb:SetScript("OnClick", nil)
        list.pool[#list.pool + 1] = cb
    end
    wipe(list.active)
    if list.empty then list.empty:Hide() end
end

-- Renders entries as a vertical checkbox list anchored to the container top. Returns the height used.
local function renderCheckList(list, container, entries, isChecked, onClick, emptyText)
    releaseCheckboxes(list)
    if #entries == 0 then
        if not list.empty then
            list.empty = container:CreateFontString(nil, "ARTWORK", "GameFontDisable")
            list.empty:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
        end
        list.empty:SetText(emptyText)
        list.empty:Show()
        return CB_SIZE
    end
    local previous
    for _, entry in ipairs(entries) do
        local cb = acquireCheckbox(list, container)
        cb:ClearAllPoints()
        if previous then
            cb:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_GAP)
        else
            cb:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        end
        setCheckboxLabel(cb, entry.name)
        cb:SetChecked(isChecked(entry))
        cb:SetScript("OnClick", function(self) onClick(entry, self:GetChecked()) end)
        previous = cb
    end
    return #entries * CB_SIZE + (#entries - 1) * ROW_GAP
end

local function channelEntries()
    local list = { GetChannelList() }
    local entries, seen = {}, {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if type(name) == "string" and name ~= "" then
            local key = ns.channelKey(name)
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { name = name, key = key }
            end
        end
    end
    return entries
end

-- A section is a yellow header, a grey helper line and a content frame, stacked inside a column inset.
local function createSection(inset, title, helperText)
    -- Only TOP* anchors are used anywhere in a section, so each frame has exactly one vertical constraint. A LEFT or RIGHT point would silently add a second one by aligning vertical centres. The initial anchors also give the helper a width, which it needs before its wrapped height can be measured.
    local section = CreateFrame("Frame", nil, inset)
    section:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD, -PAD)
    section:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -PAD, -PAD)

    local header = section:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    header:SetText(title)

    local helper = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helper:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -HEADER_GAP)
    helper:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    helper:SetJustifyH("LEFT")
    helper:SetWordWrap(true)
    helper:SetTextColor(0.6, 0.6, 0.6)
    helper:SetText(helperText)

    local content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -HEADER_GAP)
    content:SetPoint("TOPRIGHT", helper, "BOTTOMRIGHT", 0, -HEADER_GAP)
    content:SetHeight(ROW_H)

    section.header = header
    section.helper = helper
    section.content = content

    -- Section height follows the measured helper text, so long helpers never overlap the content.
    function section:Layout(contentHeight)
        content:SetHeight(math.max(contentHeight, 1))
        local h = header:GetStringHeight() + HEADER_GAP + math.ceil(helper:GetStringHeight()) + HEADER_GAP + contentHeight
        section:SetHeight(h)
        return h
    end

    return section
end

-- Stacks sections top-down inside an inset and returns the inset height they need.
local function stackSections(inset, sections)
    local previous
    for _, section in ipairs(sections) do
        section:ClearAllPoints()
        if previous then
            section:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -SECTION_GAP)
            section:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -SECTION_GAP)
        else
            section:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD, -PAD)
            section:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -PAD, -PAD)
        end
        previous = section
    end
    local total = PAD * 2
    for i, section in ipairs(sections) do
        total = total + section:GetHeight()
        if i > 1 then total = total + SECTION_GAP end
    end
    return total
end

-- Keyword rows mirror the slash command: one row is one OR group, commas inside a row are AND terms. Rows are pooled; the trailing row is always empty for the next entry.
local KeywordRows = { active = {}, pool = {} }

local function createKeywordRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetMaxLetters(256)
    editBox:SetHeight(ROW_H)
    -- InputBoxTemplate draws its left border 5px outside the frame, so offset the box to keep the visible edge flush.
    editBox:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.editBox = editBox

    local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    addBtn:SetSize(48, ROW_H)
    addBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    addBtn:SetText("Add")
    addBtn:Hide()
    row.addBtn = addBtn

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    removeBtn:SetSize(CB_SIZE, CB_SIZE)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", 2, 0)
    removeBtn:Hide()
    row.removeBtn = removeBtn

    function row:UpdateState()
        local typed = ns.trim(editBox:GetText())
        editBox:ClearAllPoints()
        editBox:SetPoint("LEFT", row, "LEFT", 6, 0)
        if row.saved and typed == row.saved then
            addBtn:Hide()
            removeBtn:Show()
            editBox:SetPoint("RIGHT", removeBtn, "LEFT", 0, 0)
        elseif typed ~= "" then
            removeBtn:Hide()
            addBtn:Show()
            editBox:SetPoint("RIGHT", addBtn, "LEFT", -GAP, 0)
        else
            addBtn:Hide()
            removeBtn:Hide()
            editBox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
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
    editBox:SetScript("OnEnterPressed", function() KeywordRows.Commit(row) end)
    addBtn:SetScript("OnClick", function() KeywordRows.Commit(row) end)
    removeBtn:SetScript("OnClick", function() KeywordRows.Delete(row) end)

    return row
end

function KeywordRows.Acquire(parent)
    local row = table.remove(KeywordRows.pool) or createKeywordRow(parent)
    row:SetParent(parent)
    row:Show()
    return row
end

function KeywordRows.Release(row)
    row.saved = nil
    row.editBox:SetText("")
    row:ClearAllPoints()
    row:Hide()
    KeywordRows.pool[#KeywordRows.pool + 1] = row
end

function KeywordRows.Add(parent, text, savedAs)
    local row = KeywordRows.Acquire(parent)
    row.saved = savedAs
    row.editBox:SetText(text or "")
    row.editBox:SetCursorPosition(0)
    KeywordRows.active[#KeywordRows.active + 1] = row
    row:UpdateState()
    return row
end

function KeywordRows.Persist()
    local store = Store.Get()
    store.keywords = {}
    for _, row in ipairs(KeywordRows.active) do
        if row.saved and row.saved ~= "" then
            store.keywords[#store.keywords + 1] = row.saved
        end
    end
    Scanner.ReloadKeywords(store)
end

function KeywordRows.EnsureTrailingEmpty(parent)
    local last = KeywordRows.active[#KeywordRows.active]
    if not last or (last.saved and last.saved ~= "") then
        KeywordRows.Add(parent, nil, nil)
    end
end

-- Lays rows out top-down and returns the height used.
function KeywordRows.Layout(container)
    for i, row in ipairs(KeywordRows.active) do
        row:ClearAllPoints()
        local y = -(i - 1) * (ROW_H + ROW_GAP)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, y)
        row:SetHeight(ROW_H)
    end
    local n = #KeywordRows.active
    return n > 0 and (n * ROW_H + (n - 1) * ROW_GAP) or ROW_H
end

function KeywordRows.Commit(row)
    local typed = ns.trim(row.editBox:GetText())
    if typed == "" then return end
    for _, other in ipairs(KeywordRows.active) do
        if other ~= row and other.saved == typed then
            row.editBox:SetText(row.saved or "")
            row.editBox:ClearFocus()
            row:UpdateState()
            return
        end
    end
    row.saved = typed
    row.editBox:ClearFocus()
    row:UpdateState()
    KeywordRows.Persist()
    if panel then panel:RefreshKeywords() end
end

function KeywordRows.Delete(row)
    for i, r in ipairs(KeywordRows.active) do
        if r == row then
            table.remove(KeywordRows.active, i)
            KeywordRows.Release(row)
            break
        end
    end
    KeywordRows.Persist()
    if panel then panel:RefreshKeywords() end
end

function KeywordRows.Populate(parent, store)
    for _, row in ipairs(KeywordRows.active) do
        KeywordRows.Release(row)
    end
    wipe(KeywordRows.active)
    for _, keyword in ipairs(store.keywords or {}) do
        KeywordRows.Add(parent, keyword, keyword)
    end
    KeywordRows.EnsureTrailingEmpty(parent)
end

-- UIPanelButtonTemplate is a three-slice button on both clients (Left, Middle, Right) and exposes no NormalTexture, so recolouring means tinting those three pieces.
local function buttonBodyTextures(button)
    local pieces = {}
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if button[key] then pieces[#pieces + 1] = button[key] end
    end
    return pieces
end

local function buildPanel()
    local frame = CreateFrame("Frame", "ChatScanFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(PANEL_W, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local version = Compat.AddonVersion()
    -- SetTitle and SetPortraitToAsset both come from PortraitFrameMixin, which ButtonFrameTemplate carries on 1.15.9 and 1.60.1 alike.
    frame:SetTitle(version and (ns.TITLE .. " " .. version) or ns.TITLE)
    frame:SetPortraitToAsset(ns.ICON)

    -- The template's single inset is replaced by two column insets in the same area, the pattern Blizzard's own multi-list frames use.
    if frame.Inset then frame.Inset:Hide() end
    local colW = (PANEL_W - INSET_LEFT - INSET_RIGHT - COL_GAP) / 2

    local leftInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    leftInset:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET_LEFT, -INSET_TOP)
    leftInset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET_LEFT, INSET_BOTTOM)
    leftInset:SetWidth(colW)

    local rightInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    rightInset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET_RIGHT, -INSET_TOP)
    rightInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET_RIGHT, INSET_BOTTOM)
    rightInset:SetWidth(colW)

    -- Attic summary line, the band between the title bar and the insets. Starts at x=62 like the template's own title text, clear of the portrait circle that reaches down into the attic on 1.15.9. Both anchors are BOTTOM* so the line has one vertical constraint.
    local summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", ATTIC_TEXT_X, -(INSET_TOP - GAP))
    summary:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -(INSET_RIGHT + PAD), -(INSET_TOP - GAP))
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(0.7, 0.7, 0.7)
    summary:SetText("Forward channel messages that match your keywords to the chat tabs you choose.")

    -- Left column
    local channelsSection = createSection(leftInset, "Scanned Channels",
        "Pick which chat channels to scan. Zone channels stay selected when you change zones.")
    local keywordsSection = createSection(leftInset, "Keywords",
        "Each row matches on its own (OR). Separate keywords in one row with commas to require all of them (AND). Press Enter or Add to save a row.")

    -- Right column
    local outputsSection = createSection(rightInset, "Output Tabs",
        "Pick which chat tabs receive matches. With none selected, matches go to the default chat frame.")
    local soundSection = createSection(rightInset, "Alert Sound",
        "Play a sound when a keyword matches, at most once every 3 seconds.")

    local channelList = { active = {}, pool = {} }
    local outputList = { active = {}, pool = {} }

    -- Sound controls: checkbox, native dropdown, preview button.
    local soundCheck = CreateFrame("CheckButton", nil, soundSection.content, "UICheckButtonTemplate")
    soundCheck:SetSize(CB_SIZE, CB_SIZE)
    soundCheck:SetPoint("TOPLEFT", soundSection.content, "TOPLEFT", 0, 0)
    setCheckboxLabel(soundCheck, "Play sound on match")
    soundCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        Store.Get().playSound = checked
        Scanner.SetSoundEnabled(checked)
    end)

    local soundDropdown = CreateFrame("DropdownButton", nil, soundSection.content, "WowStyle1DropdownTemplate")
    soundDropdown:SetSize(160, DROPDOWN_H)
    soundDropdown:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -ROW_GAP)
    soundDropdown:SetDefaultText("Choose a sound")
    soundDropdown:SetupMenu(function(_, root)
        for _, preset in ipairs(Compat.SoundPresets()) do
            root:CreateRadio(preset.name,
                function() return Scanner.GetSoundId() == preset.id end,
                function()
                    Store.Get().soundId = preset.id
                    Scanner.SetSoundId(preset.id)
                    Compat.PlaySound(preset.id)
                end)
        end
    end)

    local testBtn = CreateFrame("Button", nil, soundSection.content, "UIPanelButtonTemplate")
    testBtn:SetSize(56, ROW_H)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", GAP, 0)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function() Compat.PlaySound(Scanner.GetSoundId()) end)

    local SOUND_CONTENT_H = CB_SIZE + ROW_GAP + DROPDOWN_H

    -- Button bar: live status on the left, Start/Stop on the right.
    local startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startBtn:SetSize(96, ROW_H)
    startBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET_RIGHT, BUTTON_BAR_Y)
    local startBody = buttonBodyTextures(startBtn)
    local startHighlight = startBtn:GetHighlightTexture()

    -- Both points are LEFT/RIGHT, which share one vertical constraint: the centre line of the button row.
    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", frame, "BOTTOMLEFT", INSET_LEFT + PAD, BUTTON_BAR_Y + ROW_H / 2)
    status:SetPoint("RIGHT", startBtn, "LEFT", -GAP, 0)
    status:SetJustifyH("LEFT")

    local function tintStart(r, g, b)
        for _, tex in ipairs(startBody) do tex:SetVertexColor(r, g, b) end
        if startHighlight then startHighlight:SetVertexColor(r, g, b) end
    end

    function frame:RefreshStatus()
        if Scanner.scanning then
            startBtn:SetText("Stop")
            tintStart(1, 0.4, 0.4)
            -- A scan can be running yet unable to match, because 1.60 may withhold chat text from
            -- addons. Saying so beats showing a healthy green line that never counts anything.
            if Scanner.chatLocked then
                status:SetText("|cffff8000Chat locked by client|r  matching paused")
            else
                status:SetText("|cff40ff40Scanning|r  " .. ns.matchLabel(Scanner.matchCount))
            end
        else
            startBtn:SetText("Start")
            tintStart(1, 1, 1)
            if Scanner.matchCount > 0 then
                status:SetText("|cff999999Stopped|r  " .. ns.matchLabel(Scanner.matchCount) .. " this session")
            else
                status:SetText("|cff999999Not scanning|r")
            end
        end
    end

    startBtn:SetScript("OnClick", function()
        if Scanner.scanning then
            Scanner.Stop()
        else
            Scanner.Start()
        end
        frame:RefreshStatus()
    end)

    local channelsH, keywordsH, outputsH = CB_SIZE, ROW_H, CB_SIZE

    function frame:Resize()
        channelsSection:Layout(channelsH)
        keywordsSection:Layout(keywordsH)
        outputsSection:Layout(outputsH)
        soundSection:Layout(SOUND_CONTENT_H)
        local leftH = stackSections(leftInset, { channelsSection, keywordsSection })
        local rightH = stackSections(rightInset, { outputsSection, soundSection })
        frame:SetHeight(INSET_TOP + math.max(leftH, rightH) + INSET_BOTTOM)
    end

    function frame:RefreshChannels()
        local store = Store.Get()
        channelsH = renderCheckList(channelList, channelsSection.content, channelEntries(),
            function(entry) return store.inputChannels[entry.key] and true or false end,
            function(entry, checked)
                store.inputChannels[entry.key] = checked and true or nil
                Scanner.SetChannelEnabled(entry.key, checked)
            end,
            "(not in any channels)")
        frame:Resize()
    end

    function frame:RefreshOutputs()
        local store = Store.Get()
        outputsH = renderCheckList(outputList, outputsSection.content, Scanner.OutputWindows(),
            function(entry) return store.outputs[entry.key] and true or false end,
            function(entry, checked)
                store.outputs[entry.key] = checked and true or nil
                Scanner.SetOutputEnabled(entry.key, checked)
            end,
            "(no chat tabs available)")
        frame:Resize()
    end

    function frame:RefreshKeywords()
        KeywordRows.EnsureTrailingEmpty(keywordsSection.content)
        keywordsH = KeywordRows.Layout(keywordsSection.content)
        frame:Resize()
    end

    function frame:PopulateKeywords()
        KeywordRows.Populate(keywordsSection.content, Store.Get())
        frame:RefreshKeywords()
    end

    frame:SetScript("OnShow", function(self)
        local store = Store.Get()
        Scanner.SetSoundEnabled(store.playSound ~= false)
        Scanner.SetSoundId(store.soundId)
        soundCheck:SetChecked(store.playSound ~= false)
        soundDropdown:GenerateMenu()

        self:RefreshChannels()
        self:RefreshOutputs()
        self:PopulateKeywords()
        self:RefreshStatus()

        -- Keep the channel list live while the panel is open.
        self:RegisterEvent("CHANNEL_UI_UPDATE")
        self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    end)

    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("CHANNEL_UI_UPDATE")
        self:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    end)

    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then self:RefreshChannels() end
    end)

    Scanner.OnChanged(function()
        if frame:IsShown() then frame:RefreshStatus() end
    end)

    tinsert(UISpecialFrames, "ChatScanFrame")
    frame:Hide()
    return frame
end

function ns.TogglePanel()
    if not panel then panel = buildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- Called after slash commands change keywords so an open panel mirrors the store.
function ns.RefreshPanel()
    if panel and panel:IsShown() then
        panel:PopulateKeywords()
        panel:RefreshStatus()
    end
end
