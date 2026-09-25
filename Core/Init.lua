local ADDON_NAME, ns = ...

-- Namespace root. Holds only values and helpers that need no Blizzard API at load time, so this
-- file is safe to load first on any client. Anything version-sensitive lives in Core/Compat.lua.

ns.name = ADDON_NAME
ns.PREFIX = "|cffffff00[ChatScan]:|r "
ns.ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

ns.DEDUP_TTL = 10
ns.DEDUP_MAX = 20
ns.SOUND_THROTTLE = 3.0

-- SOUNDKIT.MAP_PING, held as a literal so a saved sound id stays valid even if the constant
-- table is renamed. Core/Compat.lua resolves the named presets from SOUNDKIT itself.
ns.DEFAULT_SOUND_ID = 3175

-- ChatFrame2 is the combat log on both clients and never receives forwarded lines.
ns.COMBAT_LOG_INDEX = 2

function ns.notify(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. msg)
end

function ns.matchLabel(count)
    return string.format("%d match%s", count, count == 1 and "" or "es")
end

function ns.trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

-- Zone channels carry their zone as a " - Zone" suffix in both GetChannelList and
-- CHAT_MSG_CHANNEL, so the suffix is dropped to keep a scan alive across zone changes.
-- Custom channel names cannot contain spaces, so they are never truncated.
function ns.channelKey(name)
    local key = strlower(name or "")
    key = key:gsub("%s+%-%s+.*$", "")
    return key
end
