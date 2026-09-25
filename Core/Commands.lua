local _, ns = ...

local function startFromCommand()
    if not ns.Scanner.scanning then
        ns.Scanner.Start()
    end
end

SLASH_CHATSCAN1 = "/cs"
SLASH_CHATSCAN2 = "/chatscan"
SlashCmdList["CHATSCAN"] = function(msg)
    local raw = ns.trim(msg)
    local lower = raw:lower()

    if raw == "" then
        ns.TogglePanel()
        return
    end

    if lower == "start" then
        if ns.Scanner.scanning then
            ns.notify("Already scanning.")
        else
            ns.Scanner.Start()
        end
        return
    end

    if lower == "stop" then
        if ns.Scanner.scanning then
            ns.Scanner.Stop()
        else
            ns.notify("Not scanning.")
        end
        return
    end

    if lower == "clear" then
        local store = ns.Store.Get()
        if #store.keywords == 0 then
            ns.notify("Keyword list is already empty.")
            return
        end
        store.keywords = {}
        ns.Scanner.ReloadKeywords(store)
        ns.notify("Keyword list cleared.")
        ns.RefreshPanel()
        return
    end

    -- Anything else is a keyword row, optionally a comma-separated AND group.
    local store = ns.Store.Get()
    for _, existing in ipairs(store.keywords) do
        if existing:lower() == lower then
            ns.notify("Already tracking: " .. existing)
            startFromCommand()
            return
        end
    end
    store.keywords[#store.keywords + 1] = raw
    ns.Scanner.ReloadKeywords(store)
    ns.notify("Added keyword: " .. raw)
    ns.RefreshPanel()
    startFromCommand()
end
