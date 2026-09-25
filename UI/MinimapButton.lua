local _, ns = ...

local COMMANDS = {
    { "/cs <KEYWORD>", "adds a keyword and starts scanning." },
    { "/cs <KW1>,<KW2>", "adds an AND combination." },
    { "/cs start", "begins a scan." },
    { "/cs stop", "ends the scan." },
    { "/cs clear", "empties the keyword list." },
}

-- Written with Blizzard's tooltip line helpers so the colours match every native tooltip.
local function showTooltip(tooltip)
    local Scanner = ns.Scanner
    GameTooltip_SetTitle(tooltip, ns.TITLE)
    if Scanner.scanning and Scanner.chatLocked then
        GameTooltip_AddHighlightLine(tooltip, WARNING_FONT_COLOR:WrapTextInColorCode("Chat locked by client") .. ", matching paused.")
    elseif Scanner.scanning then
        GameTooltip_AddHighlightLine(tooltip, GREEN_FONT_COLOR:WrapTextInColorCode("Scanning") .. ", " .. ns.matchLabel(Scanner.matchCount) .. " this session.")
        if Scanner.lastMatchSender then
            GameTooltip_AddHighlightLine(tooltip, string.format("Last: %s at %s", Scanner.lastMatchSender, Scanner.lastMatchStamp))
        end
    end
    GameTooltip_AddInstructionLine(tooltip, "Left-click to toggle the panel.")
    for _, command in ipairs(COMMANDS) do
        GameTooltip_AddHighlightLine(tooltip, NORMAL_FONT_COLOR:WrapTextInColorCode(command[1]) .. " " .. command[2])
    end
end

function ns.SetupMinimapButton()
    local dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(ns.name, {
        type = "launcher",
        text = ns.TITLE,
        icon = ns.ICON,
        OnClick = function(_, button)
            if button == "LeftButton" then ns.TogglePanel() end
        end,
        OnTooltipShow = showTooltip,
    })
    LibStub("LibDBIcon-1.0"):Register(ns.name, dataObject, ns.Store.Minimap())
end
