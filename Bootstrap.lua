local ADDON_NAME, ns = ...

-- Login bootstrap only. Loads last so every Core and UI file has already registered itself.

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ns.Store.Get()
    elseif event == "PLAYER_LOGIN" then
        ns.SetupMinimapButton()
        ns.Scanner.Resume()
    end
end)
