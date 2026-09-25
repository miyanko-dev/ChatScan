local _, ns = ...

-- The only file that touches a Blizzard API whose presence or behaviour differs between
-- Classic Era 1.15.x and WoW Forever 1.60.x. Every guard tests for the API itself, never for
-- the interface number, so a client that gains or loses one needs no change here.
-- If this file starts growing, the Core/UI boundary is drawn in the wrong place.

local Compat = {}
ns.Compat = Compat

local maxChatWindows
local soundPresets

-- Both clients report 10. NUM_CHAT_WINDOWS still resolves on both, but only through
-- Blizzard_DeprecatedChatInfo, which derives it from this constant and is marked for removal.
-- Resolved on first use rather than at load, so a late-populated Constants table still wins.
function Compat.MaxChatWindows()
    if not maxChatWindows then
        local constants = Constants and Constants.ChatFrameConstants
        maxChatWindows = (constants and constants.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
    end
    return maxChatWindows
end

-- Named alerts for the sound picker, so the user never types a raw id. All six keys exist in the
-- SoundKitConstants of both clients; a key that ever goes missing drops its preset rather than
-- storing a nil id that would later silence the alert.
local PRESET_ORDER = {
    { name = "Minimap Ping",   key = "MAP_PING" },
    { name = "Whisper",        key = "TELL_MESSAGE" },
    { name = "Raid Warning",   key = "RAID_WARNING" },
    { name = "Ready Check",    key = "READY_CHECK" },
    { name = "Auction Window", key = "AUCTION_WINDOW_OPEN" },
    { name = "Alarm Clock",    key = "ALARM_CLOCK_WARNING_1" },
}

function Compat.SoundPresets()
    if not soundPresets then
        soundPresets = {}
        for _, preset in ipairs(PRESET_ORDER) do
            local id = SOUNDKIT and SOUNDKIT[preset.key]
            if type(id) == "number" then
                soundPresets[#soundPresets + 1] = { name = preset.name, id = id }
            end
        end
    end
    return soundPresets
end

function Compat.PlaySound(id)
    PlaySound(id or ns.DEFAULT_SOUND_ID, "Master", true)
end

function Compat.AddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then return nil end
    local ok, version = pcall(getMetadata, ns.name, "Version")
    return ok and version or nil
end

-- 1.60 flags 51 CHAT_MSG_* events SecretInChatMessagingLockdown. While that lockdown is active
-- the text and playerName fields of CHAT_MSG_CHANNEL arrive as secret values, and any string
-- operation on one raises out of addon code: strlower, concatenation and gsub all abort.
--
-- issecretvalue cannot be used to test them. It is declared SecretArguments =
-- "AllowedWhenUntainted", and addon execution is tainted, so handing it a secret raises the very
-- error it is meant to prevent ("Secret values are only allowed during untainted execution").
-- This no-argument gate is the supported check. It exists on 1.15.x as well, where there is no
-- secret system and it always reports false, so no version branch is needed.
function Compat.ChatPayloadReadable()
    local inLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not inLockdown then return true end
    local ok, locked = pcall(inLockdown)
    return not (ok and locked)
end

-- Native raid-target rendering, so {skull} and {rt3} resolve exactly as they do in Blizzard's own
-- chat, localised names included. Group expressions stay untouched to match how a scanned line
-- read before. Present on both clients with the same signature.
function Compat.RenderChatExpressions(text)
    local replace = C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions
    if not replace then return text end
    local ok, rendered = pcall(replace, text, false, true)
    return (ok and rendered) or text
end
