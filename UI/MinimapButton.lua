local _, ns = ...

-- One short line on the scan state, in the colours of the panel's status line.
local function statusLine()
    local Scanner = ns.Scanner
    if not Scanner.scanning then
        return GRAY_FONT_COLOR:WrapTextInColorCode("Not scanning")
    elseif Scanner.chatLocked then
        return WARNING_FONT_COLOR:WrapTextInColorCode("Chat locked by client")
    elseif not Scanner.CanMatch() then
        return WARNING_FONT_COLOR:WrapTextInColorCode("Nothing to match")
    end
    return GREEN_FONT_COLOR:WrapTextInColorCode("Scanning") .. ", " .. ns.matchLabel(Scanner.matchCount)
end

-- Written with Blizzard's tooltip line helpers so the colours match every native tooltip.
local function showTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, ns.TITLE)
    GameTooltip_AddHighlightLine(tooltip, statusLine())
    GameTooltip_AddInstructionLine(tooltip, "Left-click to toggle the panel.")
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

-- The toc names these three globals for the Addon Compartment, which calls them with the addon name
-- first.
function ChatScan_CompartmentClick()
    ns.TogglePanel()
end

function ChatScan_CompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    showTooltip(GameTooltip)
    GameTooltip:Show()
end

function ChatScan_CompartmentLeave()
    GameTooltip:Hide()
end
