local _, ns = ...

local function startIfIdle()
    if not ns.Scanner.scanning then ns.Scanner.Start() end
end

-- Stores a keyword row, then starts. A row already tracked (any case) is not stored twice.
local function addKeyword(raw)
    local keywords = ns.Store.Get().keywords
    local lower = raw:lower()
    for _, existing in ipairs(keywords) do
        if existing:lower() == lower then
            ns.notify("Already tracking: " .. existing)
            startIfIdle()
            return
        end
    end
    keywords[#keywords + 1] = raw
    ns.Scanner.ReloadKeywords()
    ns.notify("Added keyword: " .. raw)
    ns.RefreshPanel()
    startIfIdle()
end

local function clearKeywords()
    local store = ns.Store.Get()
    if #store.keywords == 0 then
        ns.notify("Keyword list is already empty.")
        return
    end
    store.keywords = {}
    ns.Scanner.ReloadKeywords()
    ns.notify("Keyword list cleared.")
    ns.RefreshPanel()
end

SLASH_CHATSCAN1 = "/cs"
SLASH_CHATSCAN2 = "/chatscan"
SlashCmdList.CHATSCAN = function(msg)
    local raw = ns.trim(msg)
    local command = raw:lower()

    if raw == "" then
        ns.TogglePanel()
    elseif command == "start" then
        if ns.Scanner.scanning then ns.notify("Already scanning.") else ns.Scanner.Start() end
    elseif command == "stop" then
        if ns.Scanner.scanning then ns.Scanner.Stop() else ns.notify("Not scanning.") end
    elseif command == "clear" then
        clearKeywords()
    else
        addKeyword(raw)
    end
end
