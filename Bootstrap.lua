local _, ns = ...

-- Loads last, so every Core and UI file has registered itself. Saved variables are in place by
-- PLAYER_LOGIN, and nothing reads settings before it: slash commands and the panel need a player.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    ns.Store.Init()
    ns.SetupMinimapButton()
    ns.Scanner.Resume()
end)
