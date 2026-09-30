# ChatScan — Memory

Updated 2026-09-30 after the Forever-only rework (3.0.0) and the owner's round-2 decisions (tooltip, every channel, Blizzard colours, match lines built like Blizzard's channel lines, chat types including Guild Discord, and community streams outside chat tabs; still 3.0.0, unreleased). The owner's decision is WoW Forever 1.60.x only: `main` holds the Forever version and `1.15.x-backup` keeps the Classic version. Everything was verified against Gethe `forever` @ `966519cf` (1.60.1.70124) and Ketho `forever` @ `4149af64` (1.60.1.70009). The installed client is 1.60.1.70009. Nothing has run in a client yet.

## Current state

Scans the chat the player picks (channels including community channels, community streams outside chat tabs, and the chat types guild, officer, Guild Discord, party, raid, instance, say, yell, emote, whisper and Battle.net whisper) for keyword groups (OR across rows, AND within a row) and forwards matches to chosen chat tabs with a sound. Open it with `/cs`, the minimap button, or the Addon Compartment.

| Item | State |
|---|---|
| Version | 3.0.0, `## Interface: 16001` only, `## Category: Chat`, `AddonCompartmentFunc*` fields kept |
| Author | `miyanko` |
| Git | `main`: `fc105f1` (split), `4489dac` (fixes), `20ee3d8` (UI), `405ab65` (MEMORY.md), `5ea139b` (round 2: community channels, tooltip, colours), `e454960` (MEMORY.md), `1251793` (native sender colour and channel link), `6291587` (MEMORY.md), `90dce95` (chat types, community streams), `b9e1bd5` (MEMORY.md), `8cd975f` (Guild Discord), then the own-whispers commit with this MEMORY.md. Not pushed. `1.15.x-backup` = `8d4c55c` (dual-client 2.1.0), local and on GitHub, untouched. `9184981` is the last Era-only build (1.0.0) and an ancestor of both |
| Libraries | LibStub 2, CallbackHandler-1.0 8, LibDataBroker-1.1 4, LibDBIcon-1.0 56, tracked in `Libs/` (upstream trunk copies, unedited). No `.pkgmeta` externals, no `.gitignore` entry for them |
| Saved variables | `ChatScanCharDB` (per character): `inputChannels` (channels and community streams, keyed by lowercased channel name, `community:<clubId>:<streamId>` for both community paths), `chatTypes` (`CHAT_GROUPS` keys), outputs, keywords, scan state, sound. `ChatScanDB` (account): only `minimap`, the LibDBIcon table. No migration: no Forever saved variables existed |
| Offline checks | `luac -p` on all Lua files. No harness in the repo. Throwaway stub harnesses outside the repo (`scratchpad/cs2`): 3.0.0 rework Core 20/20, UI 30/30; round 2 Core 37/37, UI 40/40; chat types and streams Core 60/60, UI 54/54; with Guild Discord Core 66/66, UI 56/56; with own whispers Core 71/71, UI 56/56 (per-type filter, prefixes, links incl. Discord, colours, letterbox, lockdown gates, stream lines, joined-stream skip, stream list rules) |

Behaviour:

- No client branch, no `WOW_PROJECT_*`, no compat layer. Every API used is verified in the forever source.
- Every chat event ChatScan reads (`CHAT_MSG_CHANNEL`, `CHAT_MSG_COMMUNITIES_CHANNEL` and the chat type events) has the same 18-field payload on Forever, field 18 is `discordInfo`, and all but `CHAT_MSG_GUILD_DISCORD` are `SecretInChatMessagingLockdown` (`ChatInfoDocumentation.lua`; Guild Discord is only `SynchronousEvent`, same NeverSecret fields, and is gated the same way so one lockdown rule covers every source). NeverSecret: 3 languageName, 4 channelName, 6 specialFlags, 7 zoneChannelID, 8 channelIndex, 9 channelBaseName, 10 languageID, 11 lineID, 14 isMobile, 15 isSubtitle, 16 hideSenderInLetterbox, 17 suppressRaidIcons. Secret in lockdown: 1 text, 2 playerName, 5 playerName2, 12 guid, 13 bnSenderID, 18 discordInfo. `onChatMessage` drops field 16 lines (Blizzard never prints them), filters by the tick (the event's chat type, or field 9 for channels), then checks `C_ChatInfo.InChatMessagingLockdown()`, and only then matches field 1 and builds the line.
- While scanning, `ADDON_RESTRICTION_STATE_CHANGED` is registered too. It fires before a restriction applies and after it lifts (`RestrictedActionsDocumentation.lua`), so the lockdown is re-read one frame later with `RunNextFrame` (`Blizzard_SharedXMLBase/FunctionUtil.lua:126`).
- `Core/Lines.lua` builds every line like `MessageFormatter` in `Mainline/ChatFrameOverrides.lua:548-666`: `ReplaceIconAndGroupExpressions(text, suppressRaidIcons, not CanChatGroupPerformExpressionExpansion(chatGroup))`, `RemoveExtraSpaces`, the mobile icon when field 14 is set, `FormatDiscordMessage` for Discord senders, then channel link (channels only, `|Hchannel:channel:N|h[N. Name]|h` via `LinkUtil.FormatLink` and `ResolvePrefixedChannelName`; empty channel name means no link, as there), then `ChatFrameUtil.GetOutMessageFormatKey(type)` (`CHAT_<TYPE>_GET`, e.g. `|Hchannel:GUILD|h[Guild]|h %s: `, `%s whispers: `, `%s says: `, `[Raid Warning] %s: `; each has one `%s`) around `GetPFlag(flags, zoneID, channelIndex)` plus the sender link, then the text. `ChatScan` puts its grey `[HH:MM]` in front. The line is added with `ChatTypeInfo[type]` r, g, b and id (`CHANNELn` for both channel events), so a later colour change recolours it via `ChatFrameMixin:UpdateColorByID` (`Shared/ChatFrame.lua:235`).
- The sender name comes from `ChatFrameUtil.GetDecoratedSenderName` (`Shared/ChatFrameUtil.lua:1061`), called with payload fields 1 to 14 and discordInfo exactly as the chat frame calls it (`ChatFrameOverrides.lua:319`): ambiguated, class coloured only when `ShouldColorChatByClass(ChatTypeInfo[type])` says so, timerunning icon, sender-name filters. It is bracketed except for `EMOTE`, as there. Links follow the chat frame: `GetPlayerLink(name, display, lineID, chatGroup, chatTarget)` with `chatGroup = ChatFrameUtil.GetChatCategory(type)` and `chatTarget = FCFManager_GetChatTarget(...)`; `GetBNPlayerLink` for `BN_WHISPER`; `GetDiscordUserLink` for Discord senders in `GUILD` and `GUILD_DISCORD`, and a Discord sender in `GUILD_DISCORD` gets an extra space after the pflag (`pflag .. " " .. link`, `ChatFrameOverrides.lua:604-605,647-648`); community channel lines use `C_Club.GetInfoFromLastCommunityChatLine()` with `GetPlayerCommunityLink`/`GetBNPlayerCommunityLink` (`ChatFrameOverrides.lua:588-599`), unlinked without message info. Handlers: `Mainline/ItemRefHandlers.lua:50`, `Shared/ItemRefHandlersShared.lua:27,29`. Not copied: the language header (needs the receiving frame's default language), the recent-allies icon (a local function in `ChatFrameOverrides.lua`) and the censored-line path.
- Chat output starts with the shared prefix `YELLOW_FONT_COLOR:WrapTextInColorCode("[Chat Scan]:") .. " "`. No literal `|cff` codes remain in addon code.
- Output tabs are the active chat windows only (`FCF_IsChatWindowIndexActive`, `Blizzard_ChatFrameBase/Shared/FloatingChatFrame.lua:5`). A picked tab that is closed is skipped, so the line falls back to `DEFAULT_CHAT_FRAME`.
- A tab flashes only while its frame is hidden, like `ChatFrameUtil.FlashTabIfNotShown` (`Shared/ChatFrameUtil.lua:1049`).
- Every channel from `GetChannelList` is offered, community channels too (CS-9 filter reverted by the owner). A community channel is named `Community:<clubId>:<streamId>` and keyed by that raw name, so a renamed community keeps its tick. The panel's `channelLabel` shows it through `ChatFrameUtil.ResolveChannelName`, as `ChatConfigFrame.lua:1724` does. It keeps the raw name in chat lockdown (`C_Club.GetClubInfo`/`GetStreamInfo` are `SecretInChatMessagingLockdown`, `ClubDocumentation.lua:400,727`, and `ResolveChannelName` does string work on those names) and before the club loads (`RequiresClubsInitialized` returns nothing).
- Chat types (`ns.CHAT_GROUPS` in `Core/Init.lua`, labels are Blizzard's chat settings strings `GUILD_CHAT`, `OFFICER_CHAT`, `GUILD_DISCORD_CHAT`, `PARTY`, `RAID`, `INSTANCE_CHAT`, `SAY`, `YELL`, `EMOTE`, `WHISPER`, `BN_WHISPER`): Guild = `CHAT_MSG_GUILD`, `CHAT_MSG_OFFICER`, `CHAT_MSG_GUILD_DISCORD` (format `CHAT_GUILD_DISCORD_GET`, colour `ChatTypeInfo.GUILD_DISCORD`); Group = `CHAT_MSG_PARTY` + `_PARTY_LEADER`, `CHAT_MSG_RAID` + `_RAID_LEADER` + `_RAID_WARNING`, `CHAT_MSG_INSTANCE_CHAT` + `_INSTANCE_CHAT_LEADER`; Nearby = `CHAT_MSG_SAY`, `CHAT_MSG_YELL`, `CHAT_MSG_EMOTE`; Whispers = `CHAT_MSG_WHISPER` + `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_BN_WHISPER` + `CHAT_MSG_BN_WHISPER_INFORM` (the player's own outgoing whispers: prefix `CHAT_WHISPER_INFORM_GET`/`CHAT_BN_WHISPER_INFORM_GET` = `To %s: `, colour `ChatTypeInfo.WHISPER_INFORM`/`BN_WHISPER_INFORM`, chat group `WHISPER`/`BN_WHISPER`, `GetBNPlayerLink` for the Battle.net one as `ChatFrameOverrides.lua:602` does; the name is the recipient). All events are registered while scanning, so tick changes apply at once.
- Own lines are forwarded on purpose everywhere (channels, streams, every chat type, own outgoing whispers): the owner said "don't skip them at all for now, as I need that to test the addon properly in game". Skipping them is a later decision. Blizzard's rule that hides a whisper to a GM from normal chat frames (`ChatFrameOverrides.lua:558`) is not copied, so such a whisper forwards too.
- Left out on purpose: `CHAT_MSG_TEXT_EMOTE` (canned `/wave` text the client writes, no words from the sender), `CHAT_MSG_AFK`/`CHAT_MSG_DND` (auto-replies). `CHAT_MSG_EMOTE` stays: `/e` text is typed by the sender. Same payload and secret rules for all, the two `_INFORM` events included (`SecretInChatMessagingLockdown`, same NeverSecret fields), and the same gating.
- Community streams outside chat tabs: `CLUB_MESSAGE_ADDED(clubId, streamId, messageId)` is not secret (`ClubDocumentation.lua:1356`); `C_Club.GetMessageInfo` is `SecretInChatMessagingLockdown` (`:646`), so `onClubMessage` filters by the tick first, skips streams that are joined chat channels (`ChatFrameUtil.GetCommunitiesChannelLocalID ~= 0`, the check `CommunitiesStreams.lua:14-18` uses; those arrive as `CHAT_MSG_COMMUNITIES_CHANNEL`, so no message forwards twice), checks lockdown, then reads the message (nil or destroyed is skipped). The line is `[Community - Stream] ` (`ChatFrameUtil.GetCommunityAndStreamName`) plus `COMMUNITIES_CHAT_MESSAGE_FORMAT` (`[%s]: %s`) with the author as `CommunitiesChatMixin:FormatMessage` builds it (`Blizzard_Communities/CommunitiesChatFrame.lua:295`): `GetBNPlayerCommunityLink` for Battle.net clubs, a `RAID_CLASS_COLORS`-coloured `GetPlayerCommunityLink` for character clubs, timerunning icon; colour `ChatFrameUtil.GetCommunitiesChannelColor`. The Discord author branch is not copied: Discord posts only in guild streams, which ChatScan reads as Guild chat.
- Panel stream list: `C_Club.GetSubscribedClubs()`, non-guild clubs, `C_Club.GetStreams`, only streams with `C_Club.IsSubscribedToStream` and no chat channel; names via `GetCommunityAndStreamName`. Club and stream data are secret in lockdown (`streamId` is not NeverSecret), so the list shows "Hidden while chat is locked" then. It refreshes on `CHANNEL_UI_UPDATE`, `CHAT_MSG_CHANNEL_NOTICE` and the `CLUB_*` add/remove/update/subscribe events while shown.
- Not scanned: voice channels, NPC and system chat.
- A running scan with no keyword group or nothing ticked (channels, streams and chat types together, `countSources`) stays on and shows "Nothing to match" in the panel and the tooltip (`Scanner.CanMatch`).
- Keyword dedupe ignores case in both the panel and `/cs`.
- `PLAYER_LOGIN`: `Store.Init`, then `Scanner.Resume`, then the minimap button, so a library error can't stop a saved scan from resuming.

Native UI (shared spec):

- `ChatScanFrame`: `ButtonFrameTemplate`, strata `HIGH`, toplevel, clamped, drag to move, Escape via `UISpecialFrames`, title "Chat Scan" without the version, portrait = toc icon 134442. Built lazily by `buildPanel`; `ns.TogglePanel()` serves `/cs`, the minimap button and the compartment.
- The template's `Inset` is the left well (Scanned Channels, Community Streams, Keywords). One `InsetFrameTemplate` is the right well (Chat Types, Output Tabs, Alert Sound). Chat Types is a grid of four titled blocks (Guild, Group, Nearby, Whispers), two per row, titles in `GameFontHighlightSmall`, each a column of 24px `UICheckButtonTemplate` ticks. Offsets come from `PANEL_INSET_*`.
- The live status sits in the attic, from `TitleContainer`'s bottom-left to the right well's top-right, vertically centred.
- Start/Stop is a `MagicButtonTemplate` anchored `BOTTOMRIGHT` with zero offsets, then `MagicButton_OnLoad`. The running state shows only through the label (Start/Stop) and the status line. The old red tint is gone.
- Controls: `UIPanelButtonTemplate` (Add, Test), `UICheckButtonTemplate` shrunk to 24px, `InputBoxTemplate`, `WowStyle1DropdownTemplate` (25px), `UIPanelCloseButtonNoScripts` (24px) for row remove. Fonts: `GameFontNormal`, `GameFontHighlight`, `GameFontDisableSmall`. Colours (panel and tooltip): `GREEN_FONT_COLOR`, `WARNING_FONT_COLOR`, `GRAY_FONT_COLOR`.
- Minimap: LibDBIcon with an LDB `launcher` named `ChatScan`, icon 134442, left-click toggles, db `ChatScanDB.minimap`. Tooltip (shared with the compartment): `GameTooltip_SetTitle`, one status line (`Not scanning`, `Chat locked by client`, `Nothing to match` or `Scanning, N matches`), one `GameTooltip_AddInstructionLine`. The slash-command list and the last-match line are gone, and so are `Scanner.lastMatchSender`/`lastMatchStamp`.
- The panel grows with its content and doesn't scroll, so no `ScrollFrameTemplate` is used.
- `UI/Design.lua` is gone. Its constants live in `UI/Panel.lua`.

## Audit 2026-09-30 (Forever-only): status

| ID | Finding | Status |
|---|---|---|
| CS-1 | `## Interface: 11509, 16001` | Done: `16001`, version 3.0.0 (`fc105f1`) |
| CS-2 | Settings keyed by `UnitName-GetRealmName`, ignoring the surname | Done: `## SavedVariablesPerCharacter: ChatScanCharDB`, account data only in `ChatScanDB` (`4489dac`) |
| CS-3 | Closed tabs offered, and a closed pick swallowed matches | Done: `FCF_IsChatWindowIndexActive` filter (`4489dac`) |
| CS-4 | Era comments, Era-only close-button sizing | Done (`fc105f1`) |
| CS-5 | Minimap setup before resume; `Libs/` ignored | Done: resume first, `Libs/` tracked, externals dropped (`fc105f1`) |
| CS-6 | "Chat locked" went stale in a quiet channel | Done: `ADDON_RESTRICTION_STATE_CHANGED` + `RunNextFrame` re-read (`4489dac`) |
| CS-7 | Comment overstated `issecretvalue` | Done: comment softened. The optional `issecretvalue(msg)` guard is not added; it waits for the in-game check (`4489dac`) |
| CS-8 | Flashed when `frame ~= SELECTED_CHAT_FRAME` | Done: flashes when `not frame:IsShown()` (`4489dac`) |
| CS-9 | Community channels tickable but never matched | Superseded: filter added in `4489dac`, reverted in `5ea139b` because the owner wants community channels scanned; they are now read from `CHAT_MSG_COMMUNITIES_CHANNEL` |
| CS-10 | Panel dedupe case-sensitive; stale "Scanning" with nothing to match | Done: `:lower()` compare, "Nothing to match" status (`4489dac`) |
| CS-11 | No `## Category` | Done: `## Category: Chat` (`fc105f1`) |
| CS-12 | One-consumer `UI/Design.lua` | Done: folded into `UI/Panel.lua` (`20ee3d8`) |
| CS-13 | README for Classic; release workflow unverified | README done. Workflow: stale svn comment removed; the rest stays UNVERIFIED (see issue 6) |

## Blockers, issues, challenges

1. Lockdown scope: `SecretInChatMessagingLockdown` is documented as active during encounter, challenge-mode and PvP-match restrictions, and on communication-restricted maps such as dungeons and raids (`SecretPredicatesDocumentation.lua`). The open world isn't listed. Confirm in game.
2. `PlaySound(id)` is called without a channel, so the alert follows the SFX toggle.
3. The panel grows with its content and doesn't scroll. It fits unless there are very many channels and keywords.
4. UNVERIFIED assumptions kept in code:
   - `GetChannelList` lists community channels added to a chat tab under `Community:<clubId>:<streamId>`. Blizzard's `ChatConfigFrame.lua:1724` resolves community names from it, which says so.
   - The community event's channelBaseName (field 9) is that same `Community:<clubId>:<streamId>` name. Blizzard's chat frame compares field 9 with the names it joined through `AddChannel` (`ChatFrameOverrides.lua:336-341`, `ChatFrameUtil.lua:987`), which says so.
   - `C_Club.GetInfoFromLastCommunityChatLine()` read in an addon's handler returns the line of the event being handled. Blizzard's chat frame reads it the same way in its own handler of the same event.
   - `C_ChatInfo.InChatMessagingLockdown()` reports the new state one frame after `ADDON_RESTRICTION_STATE_CHANGED`. The docs only say the event fires before a restriction applies and after it lifts.
   - A docked tab that isn't selected has a hidden chat frame, so it flashes. Blizzard's `FlashTabIfNotShown` relies on the same.
   - `GetChannelList` names are never secret in lockdown (undocumented; unchanged since 3.0.0).
   - `CLUB_MESSAGE_ADDED` fires for every subscribed stream, not only the one open in the Communities frame, and `C_Club.IsSubscribedToStream` is true for the streams a player normally reads. If streams subscribe only while focused, the Community Streams list stays short or empty (ChatScan never calls `FocusStream`, so it changes no Communities state).
   - A community message's `content` is plain text that keyword matching can read (its type is `kstringClubMessage`).
   - Calling `ChatFrameUtil.GetDecoratedSenderName` from addon code outside lockdown behaves as in Blizzard's handler. It runs other addons' sender-name filters through Blizzard's secure registry, the same as for Blizzard's own lines.
5. The attic status is anchored to `frame.TitleContainer` (a `PortraitFrameBaseTemplate` parentKey in Mainline `SharedUIPanelTemplates.xml`). Check in game that it sits clear of the portrait and the close button.
6. Release workflow (`.github/workflows/release.yml`), not run yet:
   - `actions/checkout@v7`: UNVERIFIED that this major version exists. If it doesn't, the job fails at checkout.
   - `BigWigsMods/packager@v2` with a lone `## Interface: 16001`: UNVERIFIED how the packager maps 16001 to a game version. It may matter only for a CurseForge upload, which is skipped without `CF_API_KEY` and `X-Curse-Project-ID`.
   - With tracked `Libs/` and no externals, the packager needs no svn. Expected zip: tracked files minus `MEMORY.md` (`.pkgmeta` ignore). Whether dot-folders such as `.github` are left out by default is UNVERIFIED.
7. Nothing has been packaged end to end (bash 3.2, no svn locally).

## Feature questions for the owner

Round 1 (tooltip content, community channels), the sender colour and channel link, chat types, community streams outside chat tabs and Guild Discord chat are all decided and implemented (`5ea139b`, `1251793`, `90dce95`, `8cd975f`). Own lines: the owner decided not to skip them for now (in-game testing), and own outgoing whispers are forwarded too. Open:

1. Later: skip the player's own lines once in-game testing is done?
   - Keep: no change.
   - Skip own lines: drop the two `_INFORM` events from `CHAT_GROUPS` and compare the sender with the player (`guid == UnitGUID("player")` after the lockdown check; `author.isSelf` for streams). About 6 lines.

## Next steps

1. In game: run the Forever checks below with `/console scriptErrors 1`.
2. Push `main` and tag `v3.0.0`. Watch the first workflow run (issue 6). Check the zip has all four libs and no `MEMORY.md`.
3. Optional: tag `9184981` as `v1.0.0-classic`.

Forever checks:

- [ ] `/cs` opens the panel: portrait, title "Chat Scan" without a version, status line under the title right of the portrait, Start at the bottom right. Escape closes it, it drags, and it opens above the normal UI panels.
- [ ] Tick Trade and Loot, add `wts`, press Start. The button reads Stop and the status shows green "Scanning". A second character posts `WTS {skull} Thunderfury`. One line lands in Loot with time, channel, a clickable sender and the icon. The Loot tab flashes only while it's not the shown tab, and one sound plays.
- [ ] Close the Loot tab while it's the only pick: the next match lands in the default chat frame, and Loot is no longer listed under Output Tabs.
- [ ] Shift-click and right-click the sender. A repeat within 10 s is hidden.
- [ ] The sound dropdown previews each sound, and Test replays it.
- [ ] Untick every channel mid-scan: the status reads "Nothing to match". Tick one again: "Scanning".
- [ ] Type `WTS` when `wts` is saved: no second row.
- [ ] A community channel added to a chat tab appears under Scanned Channels with its community and stream name, not `Community:<id>:<id>`.
- [ ] Tick it, add a keyword, and have a community member post it: the line lands in that channel's colour with the tag `[N. Community - Stream]`. Right-click the sender: the community menu opens. Repeat for a Battle.net community.
- [ ] A forwarded line looks like the same message in a Blizzard tab: same `[2. Trade - City]` tag, same colour. Click the tag: the edit box opens on that channel. Right-click it: the channel menu. With "colour names by class" on for that channel the sender is class coloured, with it off the name is in the channel colour.
- [ ] Change a channel's colour in the chat settings: already forwarded lines from that channel recolour, like Blizzard's. The `[Chat Scan]:` prefix is yellow.
- [ ] Chat Types: tick Guild Chat and have a guildie post a keyword: `[Guild] [Name]: text` in guild green, the `[Guild]` tag opens guild chat on click. Repeat for Guild Discord Chat (a Discord post shows `[Guild Discord]`, the Discord icon and a Discord user link; an in-game post a normal player link), Party (and a Party Leader line), Raid (leader and raid warning), Instance, Say (`Name says:`), Yell, Emote (`Name text`, no brackets), Whisper (`Name whispers:`) and a Battle.net whisper (BN link, right-click opens the Battle.net menu). Your own outgoing whisper forwards as `To [Name]: text` (and `To` a Battle.net friend with a BN link) under the same ticks; your own channel, group and say lines forward too. `/wave` never forwards.
- [ ] Community Streams: a community stream not in any chat tab is listed with its community and stream name. Tick it, have a member post a keyword: the line `[Community - Stream] [Name]: text` lands once, in the community colour. Add the stream to a chat tab: it moves to Scanned Channels, stays ticked, and the next message still lands once.
- [ ] Check whether streams you have not opened in the Communities frame are listed and deliver (`/dump C_Club.IsSubscribedToStream(clubId, streamId)`). This settles the new UNVERIFIED subscription item.
- [ ] Open the panel in a locked dungeon: Community Streams reads "Hidden while chat is locked", no errors.
- [ ] Hover the minimap button and the compartment entry: title, one status line, "Left-click to toggle the panel." and nothing else.
- [ ] Open the panel in a locked dungeon: community channels show the raw `Community:<id>:<id>` name without errors.
- [ ] `/reload` resumes the scan. `/cs stop` then `/reload` doesn't. `/cs <kw>`, `start`, `stop` and `clear` all work.
- [ ] A second character starts with empty settings; the minimap button position is shared.
- [ ] The Addon Compartment lists Chat Scan: click toggles, hover shows the tooltip.
- [ ] Enter a dungeon while scanning with no chat traffic: "Chat locked by client" appears without waiting for a message (if the dungeon locks chat), and clears after leaving.
- [ ] Check `/dump C_ChatInfo.InChatMessagingLockdown()` in the open world, a city, a dungeon, a battleground and during an encounter. This settles issue 1.
- [ ] In a locked dungeon: `/run local f=CreateFrame("Frame") f:RegisterEvent("CHAT_MSG_CHANNEL") f:SetScript("OnEvent",function(_,_,m) print(pcall(issecretvalue,m)) end)`, then wait for a channel message. This decides the optional CS-7 guard.
- [ ] Mute SFX with Master on and record whether the alert plays.
