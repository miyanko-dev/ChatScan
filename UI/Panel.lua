local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")
local Scanner = ns.Scanner
local Store = ns.Store

-- Two equal wells side by side, one gap apart, inside the template's own inset margins. A well is
-- wide enough for the 12px helper lines and for two chat type blocks side by side.
local COLUMN_W = 40 * UI.GRID
local PANEL_W = PANEL_INSET_LEFT_OFFSET + 2 * COLUMN_W + UI.Space.gap - PANEL_INSET_RIGHT_OFFSET

-- The template's attic and button bar, above and below the wells.
local CHROME_H = -PANEL_INSET_ATTIC_OFFSET + PANEL_INSET_BOTTOM_BUTTON_OFFSET

-- Two chat type blocks share a row of the Chat Types section.
local BLOCK_W = (COLUMN_W - 2 * UI.Space.padding) / 2

local ADD_W = 7 * UI.GRID
local TEST_W = 8 * UI.GRID

local panel

-- A checkbox list with a pool, so channel joins and tab changes never leak frames.
local function createCheckList(container, emptyText)
    local list = { active = {}, pool = {} }

    -- The empty note fills the first row, so an empty list keeps the height of one entry.
    local empty = UI.CreateText(container, "muted")
    empty:SetPoint("TOPLEFT")
    empty:SetPoint("TOPRIGHT")
    empty:SetHeight(UI.Size.row)
    empty:SetText(emptyText)

    function list:SetEmptyText(text)
        empty:SetText(text)
    end

    -- Renders entries top-down and returns the height used.
    function list:Render(entries, isChecked, onClick)
        for _, checkbox in ipairs(self.active) do
            checkbox:Hide()
            self.pool[#self.pool + 1] = checkbox
        end
        wipe(self.active)
        empty:SetShown(#entries == 0)

        for i, entry in ipairs(entries) do
            local checkbox = table.remove(self.pool) or UI.CreateCheckbox(container)
            checkbox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * UI.Size.row)
            checkbox.Text:SetText(entry.name)
            checkbox:SetChecked(isChecked(entry))
            checkbox:SetScript("OnClick", function(self) onClick(entry, self:GetChecked()) end)
            checkbox:Show()
            self.active[i] = checkbox
        end
        return math.max(#entries, 1) * UI.Size.row
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

-- Subscribed community streams that are in no chat tab, so they reach the scan only as community
-- messages; a stream in a chat tab is a chat channel and listed with the channels. Guild streams
-- are Guild and Officer chat under Chat Types. The key is the stream's channel name, so a stream
-- keeps its tick when it moves into or out of a chat tab. Callers skip this in chat lockdown,
-- where club and stream data are secret; before the clubs load the C_Club calls return nothing.
local function streamEntries()
    local entries = {}
    for _, club in ipairs(C_Club.GetSubscribedClubs() or {}) do
        if club.clubType ~= Enum.ClubType.Guild then
            for _, stream in ipairs(C_Club.GetStreams(club.clubId) or {}) do
                local clubId, streamId = club.clubId, stream.streamId
                local localID = ChatFrameUtil.GetCommunitiesChannelLocalID(clubId, streamId)
                if C_Club.IsSubscribedToStream(clubId, streamId) and not (localID and localID ~= 0) then
                    entries[#entries + 1] = {
                        name = ChatFrameUtil.GetCommunityAndStreamName(clubId, streamId),
                        key = ns.channelKey(ChatFrameUtil.GetCommunitiesChannelName(clubId, streamId)),
                    }
                end
            end
        end
    end
    return entries
end

-- The chat type ticks, one titled block per CHAT_GROUPS group, two blocks side by side. A block has
-- a white heading line one gap above its ticks, and block rows sit one section break apart, so each
-- title reads as part of its own group. Returns the checkboxes by key and the height used.
local function createChatTypeGrid(content, onClick)
    local checks, top, rowH = {}, 0, 0
    for i, group in ipairs(ns.CHAT_GROUPS) do
        local column = (i - 1) % 2
        if column == 0 and i > 1 then
            top = top + rowH + UI.Space.section
            rowH = 0
        end
        local x = column * BLOCK_W

        local title = UI.CreateText(content, "body")
        title:SetHeight(UI.Size.heading)
        title:SetPoint("TOPLEFT", x, -top)
        title:SetText(group.title)
        local ticksTop = top + UI.Size.heading + UI.Space.gap

        for j, chatType in ipairs(group.types) do
            local checkbox = UI.CreateCheckbox(content, chatType.label)
            checkbox:SetPoint("TOPLEFT", x, -(ticksTop + (j - 1) * UI.Size.row))
            checkbox:SetScript("OnClick", function(self) onClick(chatType.key, self:GetChecked()) end)
            checks[chatType.key] = checkbox
        end
        rowH = math.max(rowH, ticksTop - top + #group.types * UI.Size.row)
    end
    return checks, top + rowH
end

-- A library section whose body holds a muted helper line and, one gap below it, the section's own
-- content. The helper's two anchors give it the width it needs to measure its wrap.
local function createSection(column, title, helperText)
    local section = UI.CreateSection(column, title)

    local helper = UI.CreateText(section.body, "muted")
    helper:SetPoint("TOPLEFT")
    helper:SetPoint("TOPRIGHT")
    helper:SetText(helperText)

    section.content = CreateFrame("Frame", nil, section.body)

    -- The helper's wrapped height is snapped, so the content starts on the grid and a long helper
    -- line never overlaps it.
    function section:Layout(contentHeight)
        local offset = UI.Snap(helper:GetStringHeight()) + UI.Space.gap
        self.content:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -offset)
        self.content:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -offset)
        self.content:SetHeight(contentHeight)
        self:SetBodyHeight(offset + contentHeight)
    end

    return section
end

-- Chains sections down a well from its padded top, one section break apart.
local function stackSections(sections)
    for i, section in ipairs(sections) do
        if i == 1 then
            section:SetPoint("TOPLEFT", UI.Space.padding, -UI.Space.padding)
            section:SetPoint("TOPRIGHT", -UI.Space.padding, -UI.Space.padding)
        else
            UI.StackBelow(section, sections[i - 1])
        end
    end
end

-- The height a well needs for its laid-out sections and its padding.
local function columnHeight(sections)
    local height = 2 * UI.Space.padding + (#sections - 1) * UI.Space.section
    for _, section in ipairs(sections) do
        height = height + section:GetHeight()
    end
    return height
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
    row:SetHeight(UI.Size.row)

    local editBox = UI.CreateEditBox(row)
    editBox:SetMaxLetters(256)
    row.editBox = editBox

    local addBtn = UI.CreateButton(row, "Add", ADD_W)
    addBtn:SetPoint("RIGHT")

    local removeBtn = UI.CreateRemoveButton(row)
    removeBtn:SetPoint("RIGHT")

    function row:UpdateState()
        local typed = ns.trim(editBox:GetText())
        local isSaved = self.saved ~= nil and typed == self.saved
        local isTyped = typed ~= "" and not isSaved
        addBtn:SetShown(isTyped)
        removeBtn:SetShown(isSaved)

        -- The box sits in by the template's left cap, so its visible border lines up with the column.
        editBox:ClearAllPoints()
        editBox:SetPoint("LEFT", UI.Native.inputArt, 0)
        if isSaved then
            editBox:SetPoint("RIGHT", removeBtn, "LEFT", -UI.Space.gap, 0)
        elseif isTyped then
            editBox:SetPoint("RIGHT", addBtn, "LEFT", -UI.Space.gap, 0)
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

-- Keeps one empty row at the end, lays rows out top-down one gap apart and returns the height used.
local function layoutKeywordRows(parent)
    local last = KeywordRows.active[#KeywordRows.active]
    if not last or last.saved then addKeywordRow(parent, nil) end

    local pitch = UI.Size.row + UI.Space.gap
    for i, row in ipairs(KeywordRows.active) do
        local y = -(i - 1) * pitch
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    end
    return #KeywordRows.active * pitch - UI.Space.gap
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

-- The template's Inset becomes the left well and a second inset the right one, one gap apart and
-- both on Blizzard's own inset offsets.
local function createColumns(frame)
    local left = frame.Inset
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + COLUMN_W, PANEL_INSET_BOTTOM_BUTTON_OFFSET)

    local right = UI.CreateInset(frame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", UI.Space.gap, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET)
    return left, right
end

-- The alert toggle, a sound picker that previews each pick, and a Test button. Returns the toggle,
-- the picker and the height they use.
local function createSoundControls(content)
    local soundCheck = UI.CreateCheckbox(content, "Play sound on match")
    soundCheck:SetPoint("TOPLEFT")
    soundCheck:SetScript("OnClick", function(self)
        Store.Get().playSound = self:GetChecked()
    end)

    local soundDropdown = UI.CreateDropdown(content)
    soundDropdown:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -UI.Space.gap)
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

    local testBtn = UI.CreateButton(content, "Test", TEST_W)
    testBtn:SetPoint("LEFT", soundDropdown, "RIGHT", UI.Space.gap, 0)
    testBtn:SetScript("OnClick", function() PlaySound(Store.Get().soundId) end)

    -- The dropdown keeps the template's own height, so its slot is snapped to the grid.
    return soundCheck, soundDropdown, UI.Size.row + UI.Space.gap + UI.Snap(soundDropdown:GetHeight())
end

-- The live status sits in the attic, right of the portrait and centred between title bar and wells.
local function createStatusLine(frame, right)
    local status = UI.CreateText(frame, "body")
    status:SetPoint("TOPLEFT", frame.TitleContainer, "BOTTOMLEFT")
    status:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT")
    status:SetJustifyV("MIDDLE")
    return status
end

-- Events that change the channel or community stream lists while the panel is open.
local LIST_EVENTS = {
    "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE",
    "CLUB_ADDED", "CLUB_REMOVED", "CLUB_UPDATED", "CLUB_STREAMS_LOADED", "CLUB_STREAM_ADDED",
    "CLUB_STREAM_REMOVED", "CLUB_STREAM_UPDATED", "CLUB_STREAM_SUBSCRIBED", "CLUB_STREAM_UNSUBSCRIBED",
}

local function buildPanel()
    -- The window starts at its empty height; Resize grows it with the content on every show.
    local frame = UI.CreateWindow({
        name = "ChatScanFrame", title = ns.TITLE, icon = ns.ICON,
        width = PANEL_W, height = CHROME_H,
    })
    local left, right = createColumns(frame)

    local channelsSection = createSection(left, "Scanned Channels",
        "Pick which chat channels to scan. Zone channels stay selected when you change zones.")
    local streamsSection = createSection(left, "Community Streams",
        "Community streams that are in none of your chat tabs. A stream in a chat tab is listed under Scanned Channels.")
    local keywordsSection = createSection(left, "Keywords",
        "Each row matches on its own (OR). Separate keywords in one row with commas to require all of them (AND). Press Enter or Add to save a row.")
    local chatTypesSection = createSection(right, "Chat Types",
        "Pick which chat outside the channels to scan.")
    local outputsSection = createSection(right, "Output Tabs",
        "Pick which chat tabs receive matches. With none selected, matches go to the default chat frame.")
    local soundSection = createSection(right, "Alert Sound",
        "Play a sound when a keyword matches, at most once every 3 seconds.")
    local leftSections = { channelsSection, streamsSection, keywordsSection }
    local rightSections = { chatTypesSection, outputsSection, soundSection }
    stackSections(leftSections)
    stackSections(rightSections)

    local channelList = createCheckList(channelsSection.content, "Not in any channels")
    local streamList = createCheckList(streamsSection.content, "")
    local outputList = createCheckList(outputsSection.content, "No chat tabs available")
    local chatChecks, chatTypesH = createChatTypeGrid(chatTypesSection.content, function(key, checked)
        Store.Get().chatTypes[key] = checked or nil
        frame:RefreshStatus()
    end)
    local soundCheck, soundDropdown, soundH = createSoundControls(soundSection.content)
    local status = createStatusLine(frame, right)

    -- The primary action takes the button bar's bottom-right corner.
    local startBtn = UI.AddBarButton(frame, "Start", function()
        if Scanner.scanning then Scanner.Stop() else Scanner.Start() end
    end)

    -- The button label and the status line show whether a scan runs.
    function frame:RefreshStatus()
        local count = ns.matchLabel(Scanner.matchCount)
        if Scanner.scanning then
            startBtn:SetText("Stop")
            -- A running scan can be unable to match while the client withholds chat text, or once
            -- every keyword or source is gone.
            if Scanner.chatLocked then
                status:SetText(UI.Color.warn:WrapTextInColorCode("Chat locked by client") .. "  matching paused")
            elseif not Scanner.CanMatch() then
                status:SetText(UI.Color.warn:WrapTextInColorCode("Nothing to match") .. "  add a keyword and tick a source")
            else
                status:SetText(UI.Color.good:WrapTextInColorCode("Scanning") .. "  " .. count)
            end
        else
            startBtn:SetText("Start")
            if Scanner.matchCount > 0 then
                status:SetText(UI.Color.muted:WrapTextInColorCode("Stopped") .. "  " .. count .. " this session")
            else
                status:SetText(UI.Color.muted:WrapTextInColorCode("Not scanning"))
            end
        end
    end

    local channelsH, streamsH, keywordsH, outputsH = UI.Size.row, UI.Size.row, UI.Size.row, UI.Size.row

    -- The window grows with its content: the attic, the taller well and the button bar.
    function frame:Resize()
        channelsSection:Layout(channelsH)
        streamsSection:Layout(streamsH)
        keywordsSection:Layout(keywordsH)
        chatTypesSection:Layout(chatTypesH)
        outputsSection:Layout(outputsH)
        soundSection:Layout(soundH)
        self:SetHeight(CHROME_H + math.max(columnHeight(leftSections), columnHeight(rightSections)))
    end

    -- Channels and community streams render together, because a stream moves from one list to the
    -- other when it joins or leaves a chat tab. Stream data is secret in chat lockdown, so the
    -- stream list says so instead.
    function frame:RefreshChannels()
        local channels = Store.Get().inputChannels
        local function isChecked(entry) return channels[entry.key] end
        local function onClick(entry, checked)
            channels[entry.key] = checked or nil
            self:RefreshStatus()
        end
        channelsH = channelList:Render(channelEntries(), isChecked, onClick)

        local locked = C_ChatInfo.InChatMessagingLockdown()
        streamList:SetEmptyText(locked and "Hidden while chat is locked" or "No other community streams")
        streamsH = streamList:Render(locked and {} or streamEntries(), isChecked, onClick)
        self:Resize()
    end

    function frame:RefreshChatTypes()
        local chatTypes = Store.Get().chatTypes
        for key, checkbox in pairs(chatChecks) do checkbox:SetChecked(chatTypes[key]) end
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

    -- The channel and stream lists stay live while the panel is open.
    frame:SetScript("OnShow", function(self)
        soundCheck:SetChecked(Store.Get().playSound)
        soundDropdown:GenerateMenu()
        self:RefreshChannels()
        self:RefreshChatTypes()
        self:RefreshOutputs()
        self:PopulateKeywords()
        self:RefreshStatus()
        FrameUtil.RegisterFrameForEvents(self, LIST_EVENTS)
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

    -- The keyword rows and ns.RefreshPanel reach the panel outside the toggle.
    panel = frame
    return frame
end

-- One toggle for /cs, the minimap button and the addon menu; the panel is built on first use.
ns.TogglePanel = UI.CreateToggle(buildPanel)

-- Called after slash commands change keywords, so an open panel mirrors the store.
function ns.RefreshPanel()
    if panel and panel:IsShown() then panel:PopulateKeywords() end
end
