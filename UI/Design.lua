local _, ns = ...

-- Text roles and control metrics for the panel. Everything here is Blizzard's own, so the panel
-- draws native faces, sizes and spacing instead of a custom kit.

local Design = {}
ns.Design = Design

-- The roles Blizzard's panels use: gold headings, white body text and grey help text.
Design.FONT = {
    HEADING = GameFontNormal,
    TEXT = GameFontHighlight,
    HELPER = GameFontDisableSmall,
}

-- ButtonFrameTemplate's own inset offsets (PANEL_INSET_* in Mainline/SharedUIPanelTemplates.lua):
-- the attic under the title and portrait, and the button bar under the content.
Design.HEADER_H = -PANEL_INSET_ATTIC_OFFSET
Design.FOOTER_H = PANEL_INSET_BOTTOM_BUTTON_OFFSET
Design.INSET_LEFT = PANEL_INSET_LEFT_OFFSET
Design.INSET_RIGHT = PANEL_INSET_RIGHT_OFFSET

-- MagicButton_OnLoad's placement for a button in the bottom-right corner of the button bar.
Design.BAR_BUTTON_X = -6
Design.BAR_BUTTON_Y = 4

-- UIPanelButtonTemplate and InputBoxTemplate art heights, and a row sized to the 24px close button
-- that removes a keyword row.
Design.BUTTON_H = 22
Design.INPUT_H = 20
Design.ROW_H = 24
