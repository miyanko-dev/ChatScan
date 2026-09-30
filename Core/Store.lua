local _, ns = ...

local Store = {}
ns.Store = Store

local store

-- Scan settings are per character (ChatScanCharDB), so the client keeps characters apart instead of
-- a name key. ChatScanDB holds only what every character shares: the minimap button.
function Store.Init()
    ChatScanDB = ChatScanDB or {}
    ChatScanDB.minimap = ChatScanDB.minimap or { hide = false, minimapPos = 195 }

    ChatScanCharDB = ChatScanCharDB or {}
    store = ChatScanCharDB

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
