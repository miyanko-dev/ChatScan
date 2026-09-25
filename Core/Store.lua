local _, ns = ...

local Store = {}
ns.Store = Store

local store

-- Resolved once at login and cached. UnitName is flagged SecretWhenUnitNameIdentityRestricted on
-- 1.60, so the key is not rebuilt from it on every settings change.
function Store.Init()
    ChatScanDB = ChatScanDB or {}
    ChatScanDB.minimap = ChatScanDB.minimap or { hide = false, minimapPos = 195 }

    local key = UnitName("player") .. "-" .. GetRealmName()
    store = ChatScanDB[key] or {}
    ChatScanDB[key] = store

    store.inputChannels = store.inputChannels or {}
    store.outputs = store.outputs or {}
    store.keywords = store.keywords or {}
    store.scanEnabled = store.scanEnabled or false
    if store.playSound == nil then store.playSound = true end
    store.soundId = store.soundId or ns.DEFAULT_SOUND_ID
end

-- The per-character settings table. Valid from PLAYER_LOGIN on, which precedes every caller.
function Store.Get()
    return store
end

function Store.Minimap()
    return ChatScanDB.minimap
end
