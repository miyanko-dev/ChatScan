local _, ns = ...

local Store = {}
ns.Store = Store

local function playerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function newCharacterStore()
    return {
        inputChannels = {},
        outputs = {},
        keywords = {},
        scanEnabled = false,
        playSound = true,
        soundId = ns.DEFAULT_SOUND_ID,
    }
end

-- Versions up to 1.1.0 saved zone channels with their zone suffix. Fold those onto the suffix-free key so existing selections survive the upgrade. Only rebuilds when a suffixed key is actually present, so the common path allocates nothing.
local function migrateChannelKeys(channels)
    local stale = false
    for name in pairs(channels) do
        if name ~= ns.channelKey(name) then
            stale = true
            break
        end
    end
    if not stale then return channels end

    local migrated = {}
    for name, on in pairs(channels) do
        if on then migrated[ns.channelKey(name)] = true end
    end
    return migrated
end

-- Returns the per-character store, creating and repairing it as needed. Safe to call from any event, including before PLAYER_LOGIN.
function Store.Get()
    ChatScanDB = ChatScanDB or {}
    if type(ChatScanDB.minimap) ~= "table" then
        ChatScanDB.minimap = { hide = false, minimapPos = 195 }
    end

    local key = playerKey()
    ChatScanDB[key] = ChatScanDB[key] or newCharacterStore()
    local store = ChatScanDB[key]

    store.inputChannels = migrateChannelKeys(store.inputChannels or {})
    store.outputs = store.outputs or {}
    store.keywords = store.keywords or {}
    if store.scanEnabled == nil then store.scanEnabled = false end
    if store.playSound == nil then store.playSound = true end
    if type(store.soundId) ~= "number" or store.soundId <= 0 then
        store.soundId = ns.DEFAULT_SOUND_ID
    end
    return store
end

function Store.Minimap()
    Store.Get()
    return ChatScanDB.minimap
end
