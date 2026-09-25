local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

-- Spaced name for everything the player reads. ns.name stays unspaced because it is the
-- addon folder and the LibDBIcon registry key, neither of which may change.
ns.TITLE = "Chat Scan"
ns.PREFIX = NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. ns.TITLE .. "]:") .. " "

-- interface/icons/inv_misc_spyglass_03.blp, the same file id as the toc's IconTexture.
ns.ICON = 134442

ns.DEDUP_TTL = 10
ns.DEDUP_MAX = 20
ns.SOUND_THROTTLE = 3.0

-- Named alerts for the sound picker, so the player never types a raw sound kit id.
ns.SOUNDS = {
    { name = "Minimap Ping", id = SOUNDKIT.MAP_PING },
    { name = "Whisper", id = SOUNDKIT.TELL_MESSAGE },
    { name = "Raid Warning", id = SOUNDKIT.RAID_WARNING },
    { name = "Ready Check", id = SOUNDKIT.READY_CHECK },
    { name = "Auction Window", id = SOUNDKIT.AUCTION_WINDOW_OPEN },
    { name = "Alarm Clock", id = SOUNDKIT.ALARM_CLOCK_WARNING_1 },
}
ns.DEFAULT_SOUND_ID = SOUNDKIT.MAP_PING

-- ChatFrame2 is always reset and docked as the combat log, so it never receives forwarded lines.
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

-- Zone channels carry a " - Zone" suffix, so it is dropped to keep a scan alive across zone
-- changes. Custom channel names cannot contain spaces, so they are never truncated.
function ns.channelKey(name)
    local key = strlower(name or ""):gsub("%s+%-%s+.*$", "")
    return key
end
