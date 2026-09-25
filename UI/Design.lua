local ADDON_NAME, ns = ...

-- Shared panel design, copied verbatim into every miyanko addon so their panels read as one family.
-- Edit it in all of them or in none. Nothing in this file may name a specific addon.

local Design = {}
ns.Design = Design

-- Margins, paddings and gaps come only from this scale.
Design.SPACE = { XS = 8, S = 16, M = 24, L = 32, XL = 40, XXL = 48 }

-- One height for every control, so buttons, inputs, checkboxes and dropdowns share a row rhythm.
Design.CONTROL_H = 24

-- ButtonFrameTemplate reserves a title bar plus the portrait that reaches down into the attic,
-- and a button bar below the content: one control with XS above and below it.
Design.HEADER_H = 64
Design.FOOTER_H = Design.SPACE.XS + Design.CONTROL_H + Design.SPACE.XS

-- Rounds a measured height up to the grid, because text metrics are not grid-aligned.
function Design.Snap(height)
    return math.ceil(height / Design.SPACE.XS) * Design.SPACE.XS
end

-- Tooltip fonts and line colours, sized onto a 4px grid (16 and 12) instead of the tooltip's 14/12/10.
-- Font names carry the addon name so each copy owns its fonts and no copy can restyle another's.
local function defineFont(style, source, height, color)
    local font = CreateFont(ADDON_NAME .. "Font" .. style)
    font:CopyFontObject(source)
    font:SetFontHeight(height)
    font:SetTextColor(color:GetRGB())
    return font
end

-- Colours follow Blizzard's tooltip helpers: GameTooltip_SetTitle, AddNormalLine, AddHighlightLine
-- and AddDisabledLine.
Design.FONT = {
    TITLE = defineFont("Title", GameTooltipHeaderText, 16, HIGHLIGHT_FONT_COLOR),
    HEADING = defineFont("Heading", GameTooltipHeaderText, 16, NORMAL_FONT_COLOR),
    SUBHEADING = defineFont("Subheading", GameTooltipText, 12, NORMAL_FONT_COLOR),
    TEXT = defineFont("Text", GameTooltipText, 12, HIGHLIGHT_FONT_COLOR),
    HELPER = defineFont("Helper", GameTooltipText, 12, DISABLED_FONT_COLOR),
}
