local _, ns = ...

-- Builds forwarded lines the way Blizzard prints them. The scanner calls these only outside chat
-- lockdown, because they read payload fields and club data that are secret during it.
local Lines = {}
ns.Lines = Lines

local function isFromDiscord(discordInfo)
    return discordInfo and discordInfo.userID and discordInfo.userID ~= 0
end

-- Channels take the colour the player set for that channel number; every other chat its own type.
local function chatColor(chatType, channelIndex)
    if chatType == "CHANNEL" or chatType == "COMMUNITIES_CHANNEL" then
        return ChatTypeInfo["CHANNEL" .. channelIndex] or ChatTypeInfo.CHANNEL
    end
    return ChatTypeInfo[chatType]
end

-- Blizzard's own sender decoration: ambiguated name, class colour when that chat type's setting
-- asks for it, otherwise uncoloured so it takes the line colour. Blizzard's chat passes the first
-- 14 payload fields and discordInfo, so the helper gets exactly those.
local function decoratedSender(event, ...)
    local text, sender, language, channelName, sender2, flags, zoneID, channelIndex, baseName, languageID, lineID, guid, bnSenderID, isMobile, _, _, _, discordInfo = ...
    return ChatFrameUtil.GetDecoratedSenderName(event, text, sender, language, channelName, sender2, flags, zoneID, channelIndex, baseName, languageID, lineID, guid, bnSenderID, isMobile, discordInfo)
end

-- Community lines link through the community message, as Blizzard's chat does, so the right-click
-- menu offers the community actions. The last community line is read inside its own event, like
-- Blizzard's chat reads it; without it the name shows unlinked, as there.
local function communityLink(sender, display, bnSenderID)
    local messageInfo, clubId, streamId = C_Club.GetInfoFromLastCommunityChatLine()
    if not messageInfo then return display end
    local id = messageInfo.messageId
    if bnSenderID and bnSenderID ~= 0 then
        return GetBNPlayerCommunityLink(sender, display, bnSenderID, clubId, streamId, id.epoch, id.position)
    end
    return GetPlayerCommunityLink(sender, display, clubId, streamId, id.epoch, id.position)
end

-- The link type Blizzard's chat uses for this chat. The link keeps the full name so a whisper
-- reaches the right player, and carries lineID, chat group and target so the right-click menu works.
local function senderLink(event, chatType, chatGroup, ...)
    local _, sender, _, _, _, _, _, channelIndex, _, _, lineID, _, bnSenderID, _, _, _, _, discordInfo = ...
    local chatTarget = FCFManager_GetChatTarget(chatGroup, sender, channelIndex)

    -- Blizzard brackets the name everywhere but in an emote.
    local display = decoratedSender(event, ...)
    if chatType ~= "EMOTE" then display = "[" .. display .. "]" end

    if chatType == "COMMUNITIES_CHANNEL" then
        return communityLink(sender, display, bnSenderID)
    elseif chatType == "BN_WHISPER" or chatType == "BN_WHISPER_INFORM" then
        return GetBNPlayerLink(sender, display, bnSenderID, lineID, chatGroup, chatTarget)
    elseif (chatType == "GUILD" or chatType == "GUILD_DISCORD") and isFromDiscord(discordInfo) then
        return GetDiscordUserLink(display, bnSenderID, discordInfo.userID, lineID, chatGroup, chatTarget)
    end
    return GetPlayerLink(sender, display, lineID, chatGroup, chatTarget)
end

-- The channel link Blizzard's chat prints: left-click opens chat on that channel, right-click its
-- menu. Chat that is not a channel has an empty channel name, and Blizzard prints no link then.
local function channelLink(channelName, channelIndex)
    if channelName == "" then return "" end
    local display = "[" .. ChatFrameUtil.ResolvePrefixedChannelName(channelName) .. "]"
    return LinkUtil.FormatLink(LinkTypes.Channel, display, "channel", channelIndex) .. " "
end

-- Blizzard's line for a chat event (MessageFormatter in ChatFrameMixin:MessageEventHandler): the
-- channel link, the chat type's own prefix around the flagged sender link, then the text. Returns
-- the line and the chat type's colour and id, so a later colour change recolours the line too.
function Lines.Chat(event, ...)
    local msg, _, _, channelName, _, flags, zoneID, channelIndex, _, _, _, _, _, isMobile, _, _, suppressRaidIcons, discordInfo = ...
    local chatType = event:sub(10)
    local chatGroup = ChatFrameUtil.GetChatCategory(chatType)
    local info = chatColor(chatType, channelIndex)

    local noExpansion = not ChatFrameUtil.CanChatGroupPerformExpressionExpansion(chatGroup)
    local text = RemoveExtraSpaces(C_ChatInfo.ReplaceIconAndGroupExpressions(msg, suppressRaidIcons, noExpansion))
    if isMobile then text = ChatFrameUtil.GetMobileEmbeddedTexture(info.r, info.g, info.b) .. text end
    if isFromDiscord(discordInfo) then text = ChatFrameUtil.FormatDiscordMessage(discordInfo, text) end

    -- Blizzard spaces the Discord flag from a Discord sender in Guild Discord lines only.
    local pflag = ChatFrameUtil.GetPFlag(flags, zoneID, channelIndex)
    if chatType == "GUILD_DISCORD" and isFromDiscord(discordInfo) then pflag = pflag .. " " end
    local sender = pflag .. senderLink(event, chatType, chatGroup, ...)
    local line = channelLink(channelName, channelIndex) .. ChatFrameUtil.GetOutMessageFormatKey(chatType):format(sender) .. text
    return line, info.r, info.g, info.b, info.id
end

-- The author as Blizzard's Communities chat shows it (CommunitiesChatMixin:FormatMessage): a
-- Battle.net community link, a class-coloured character link, or the bare name for other clubs.
-- Discord authors only post in guild streams, which ChatScan reads as Guild or Guild Discord chat.
local function streamAuthor(clubId, streamId, message)
    local author, id = message.author, message.messageId
    local name = author.name or " "
    local shown = author.timerunningSeasonID and TimerunningUtil.AddSmallIcon(name) or name
    if author.clubType == Enum.ClubType.BattleNet then
        return GetBNPlayerCommunityLink(name, shown, author.bnetAccountId, clubId, streamId, id.epoch, id.position)
    elseif author.clubType == Enum.ClubType.Character or author.clubType == Enum.ClubType.Guild then
        local classInfo = author.classID and C_CreatureInfo.GetClassInfo(author.classID)
        local classColor = classInfo and RAID_CLASS_COLORS[classInfo.classFile]
        if classColor then shown = classColor:WrapTextInColorCode(shown) end
        return GetPlayerCommunityLink(name, shown, clubId, streamId, id.epoch, id.position)
    end
    return name
end

-- A stream message the way Blizzard's Communities chat prints it, behind the community and stream
-- name so the line says where it came from. Returns the line and the stream's community colour.
function Lines.Stream(clubId, streamId, message)
    local tag = "[" .. ChatFrameUtil.GetCommunityAndStreamName(clubId, streamId) .. "] "
    local line = tag .. COMMUNITIES_CHAT_MESSAGE_FORMAT:format(streamAuthor(clubId, streamId, message), message.content)
    return line, ChatFrameUtil.GetCommunitiesChannelColor(clubId, streamId)
end
