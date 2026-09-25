local _, ns = ...

function ns.SetupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if LDBIcon:IsRegistered(ns.name) then return end

    local dataObject = LDB:NewDataObject(ns.name, {
        type = "launcher",
        text = ns.name,
        icon = ns.ICON,
        OnClick = function(_, button)
            if button == "LeftButton" then
                ns.TogglePanel()
            end
        end,
        OnTooltipShow = function(tt)
            local Scanner = ns.Scanner
            tt:AddLine(ns.name)
            if Scanner.scanning and Scanner.chatLocked then
                tt:AddLine("|cffff8000Chat locked by client|r, matching paused.", 1, 1, 1)
            elseif Scanner.scanning then
                tt:AddLine("|cff00ff00Scanning|r, " .. ns.matchLabel(Scanner.matchCount) .. " this session.", 1, 1, 1)
                if Scanner.lastMatchSender then
                    tt:AddLine(string.format("Last: %s at %s", Scanner.lastMatchSender, Scanner.lastMatchStamp or "?"), 1, 1, 1)
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

    LDBIcon:Register(ns.name, dataObject, ns.Store.Minimap())
end
