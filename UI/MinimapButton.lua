local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")

-- One short line on the scan state, in the colours of the panel's status line.
local function statusLine()
    local Scanner = ns.Scanner
    if not Scanner.scanning then
        return UI.Color.muted:WrapTextInColorCode("Not scanning")
    elseif Scanner.chatLocked then
        return UI.Color.warn:WrapTextInColorCode("Chat locked by client")
    elseif not Scanner.CanMatch() then
        return UI.Color.warn:WrapTextInColorCode("Nothing to match")
    end
    return UI.Color.good:WrapTextInColorCode("Scanning") .. ", " .. ns.matchLabel(Scanner.matchCount)
end

-- The lines under the launcher's title, written with Blizzard's tooltip line helpers so the colours
-- match every native tooltip.
local function fillTooltip(tooltip)
    GameTooltip_AddHighlightLine(tooltip, statusLine())
    GameTooltip_AddInstructionLine(tooltip, "Left-click to toggle the panel.")
end

local function onClick(button)
    if button == "LeftButton" then ns.TogglePanel() end
end

-- The minimap button and the addon menu entry share this click and tooltip. The minimap position
-- lives in the account-wide db table, so it survives the rename of the launcher.
function ns.SetupLauncher()
    UI.CreateLauncher({
        title = ns.TITLE,
        icon = ns.ICON,
        db = ns.Store.Minimap(),
        onClick = onClick,
        tooltip = fillTooltip,
    })
end
