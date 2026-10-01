local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")

local function startIfIdle()
    if not ns.Scanner.scanning then ns.Scanner.Start() end
end

-- Stores a keyword row, then starts. A row already tracked (any case) is not stored twice.
local function addKeyword(raw)
    local keywords = ns.Store.Get().keywords
    local lower = raw:lower()
    for _, existing in ipairs(keywords) do
        if existing:lower() == lower then
            UI.Print(ns.TITLE, "Already tracking: " .. existing)
            startIfIdle()
            return
        end
    end
    keywords[#keywords + 1] = raw
    ns.Scanner.ReloadKeywords()
    UI.Print(ns.TITLE, "Added keyword: " .. raw)
    ns.RefreshPanel()
    startIfIdle()
end

local function clearKeywords()
    local store = ns.Store.Get()
    if #store.keywords == 0 then
        UI.Print(ns.TITLE, "Keyword list is already empty.")
        return
    end
    store.keywords = {}
    ns.Scanner.ReloadKeywords()
    UI.Print(ns.TITLE, "Keyword list cleared.")
    ns.RefreshPanel()
end

-- A bare /cs toggles the panel, a command word runs it, anything else is a keyword row.
local function handleSlash(msg)
    local raw = ns.trim(msg)
    local command = raw:lower()

    if raw == "" then
        ns.TogglePanel()
    elseif command == "start" then
        if ns.Scanner.scanning then UI.Print(ns.TITLE, "Already scanning.") else ns.Scanner.Start() end
    elseif command == "stop" then
        if ns.Scanner.scanning then ns.Scanner.Stop() else UI.Print(ns.TITLE, "Not scanning.") end
    elseif command == "clear" then
        clearKeywords()
    else
        addKeyword(raw)
    end
end

UI.RegisterSlash("CHATSCAN", { "/cs", "/chatscan" }, handleSlash)
