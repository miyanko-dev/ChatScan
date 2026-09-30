# ChatScan — Memory

Updated 2026-09-30 after the Forever-only rework (3.0.0) and the owner's round-2 decisions (tooltip, every channel, Blizzard colours; still 3.0.0, unreleased). The owner's decision is WoW Forever 1.60.x only: `main` holds the Forever version and `1.15.x-backup` keeps the Classic version. Everything was verified against Gethe `forever` @ `966519cf` (1.60.1.70124) and Ketho `forever` @ `4149af64` (1.60.1.70009). The installed client is 1.60.1.70009. Nothing has run in a client yet.

## Current state

Scans every chat channel the player picks, community channels included, for keyword groups (OR across rows, AND within a row) and forwards matches to chosen chat tabs with a sound. Open it with `/cs`, the minimap button, or the Addon Compartment.

| Item | State |
|---|---|
| Version | 3.0.0, `## Interface: 16001` only, `## Category: Chat`, `AddonCompartmentFunc*` fields kept |
| Author | `miyanko` |
| Git | `main`: `fc105f1` (split), `4489dac` (fixes), `20ee3d8` (UI), `405ab65` (MEMORY.md), `5ea139b` (round 2: community channels, tooltip, colours), then the MEMORY.md commit. Not pushed. `1.15.x-backup` = `8d4c55c` (dual-client 2.1.0), local and on GitHub, untouched. `9184981` is the last Era-only build (1.0.0) and an ancestor of both |
| Libraries | LibStub 2, CallbackHandler-1.0 8, LibDataBroker-1.1 4, LibDBIcon-1.0 56, tracked in `Libs/` (upstream trunk copies, unedited). No `.pkgmeta` externals, no `.gitignore` entry for them |
| Saved variables | `ChatScanCharDB` (per character): channels, outputs, keywords, scan state, sound. `ChatScanDB` (account): only `minimap`, the LibDBIcon table. No migration: no Forever saved variables existed |
| Offline checks | `luac -p` on all Lua files. No harness in the repo. Throwaway stub harnesses outside the repo: 3.0.0 rework Core 20/20, UI 30/30; round 2 Core 36/36, UI 37/37 (community events, labels, links, colours, tooltip) |

Behaviour:

- No client branch, no `WOW_PROJECT_*`, no compat layer. Every API used is verified in the forever source.
- `CHAT_MSG_CHANNEL` and `CHAT_MSG_COMMUNITIES_CHANNEL` have the same 18-field payload on Forever, field 18 is `discordInfo`, and both are `SecretInChatMessagingLockdown` (`ChatInfoDocumentation.lua:1483`). ChatScan reads 1 text, 2 playerName, 8 channelIndex, 9 channelBaseName, 11 lineID, 13 bnSenderID and 17 suppressRaidIcons. Fields 8, 9, 11 and 17 are `NeverSecret`; 1, 2 and 13 are not. ChatScan filters by channelBaseName first, then checks `C_ChatInfo.InChatMessagingLockdown()`, and only then reads the rest and matches.
- While scanning, `ADDON_RESTRICTION_STATE_CHANGED` is registered too. It fires before a restriction applies and after it lifts (`RestrictedActionsDocumentation.lua`), so the lockdown is re-read one frame later with `RunNextFrame` (`Blizzard_SharedXMLBase/FunctionUtil.lua:126`).
- A match line is `[HH:MM]` (`GRAY_FONT_COLOR`), `[channel]` in the player's colour for that channel (`ChatTypeInfo["CHANNEL"..channelIndex]`, `ChatTypeInfoConstants.lua:56-75`, 20 = `MaxChatChannels`, through `CreateColor`), the sender link (`YELLOW_FONT_COLOR`), then the text. The channel tag's old light blue imitated nothing Blizzard uses, so the tag now follows the chat colour like Blizzard's own line does.
- The sender shows the way Blizzard's chat does (`Ambiguate(sender, "none")`); the link keeps the full name. Channel lines use `GetPlayerLink(..., "CHANNEL", tostring(channelIndex))`. Community lines use `C_Club.GetInfoFromLastCommunityChatLine()` and `GetPlayerCommunityLink`, or `GetBNPlayerCommunityLink` when bnSenderID is not 0, exactly like `Mainline/ChatFrameOverrides.lua:588-599`; without message info the name shows unlinked, as there. Both link types have Blizzard handlers (`Mainline/ItemRefHandlers.lua:50`, `Shared/ItemRefHandlersShared.lua:27`). `ReplaceIconAndGroupExpressions` matches Blizzard's chat code.
- Chat output starts with the shared prefix `YELLOW_FONT_COLOR:WrapTextInColorCode("[Chat Scan]:") .. " "`. No literal `|cff` codes remain in addon code.
- Output tabs are the active chat windows only (`FCF_IsChatWindowIndexActive`, `Blizzard_ChatFrameBase/Shared/FloatingChatFrame.lua:5`). A picked tab that is closed is skipped, so the line falls back to `DEFAULT_CHAT_FRAME`.
- A tab flashes only while its frame is hidden, like `ChatFrameUtil.FlashTabIfNotShown` (`Shared/ChatFrameUtil.lua:1049`).
- Every channel from `GetChannelList` is offered, community channels too (CS-9 filter reverted by the owner). A community channel is named `Community:<clubId>:<streamId>` and keyed by that raw name, so a renamed community keeps its tick. `ns.channelLabel` shows it through `ChatFrameUtil.ResolveChannelName`, as `ChatConfigFrame.lua:1724` does. It keeps the raw name in chat lockdown (`C_Club.GetClubInfo`/`GetStreamInfo` are `SecretInChatMessagingLockdown`, `ClubDocumentation.lua:400,727`, and `ResolveChannelName` does string work on those names) and before the club loads (`RequiresClubsInitialized` returns nothing).
- Channel kinds checked: world/zone channels (General, Trade, LocalDefense, LookingForGroup, Services, Newcomer and so on) and custom channels arrive on `CHAT_MSG_CHANNEL`; community channels added to a chat tab on `CHAT_MSG_COMMUNITIES_CHANNEL`. Both are covered. Not channels, so not covered: guild and officer streams (they join chat as the `GUILD`/`OFFICER`/`GUILD_DISCORD` message groups, `CommunitiesStreams.lua:429-437`), community streams not added to any chat tab (no chat channel, only `CLUB_MESSAGE_ADDED`), the Group entries of the channel list (Party/Raid/Instance chat types) and voice channels. See feature questions.
- A running scan with no keyword group or no ticked channel stays on and shows "Nothing to match" in the panel and the tooltip (`Scanner.CanMatch`).
- Keyword dedupe ignores case in both the panel and `/cs`.
- `PLAYER_LOGIN`: `Store.Init`, then `Scanner.Resume`, then the minimap button, so a library error can't stop a saved scan from resuming.

Native UI (shared spec):

- `ChatScanFrame`: `ButtonFrameTemplate`, strata `HIGH`, toplevel, clamped, drag to move, Escape via `UISpecialFrames`, title "Chat Scan" without the version, portrait = toc icon 134442. Built lazily by `buildPanel`; `ns.TogglePanel()` serves `/cs`, the minimap button and the compartment.
- The template's `Inset` is the left well (channels, keywords). One `InsetFrameTemplate` is the right well (output tabs, sound). Offsets come from `PANEL_INSET_*`.
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
5. The attic status is anchored to `frame.TitleContainer` (a `PortraitFrameBaseTemplate` parentKey in Mainline `SharedUIPanelTemplates.xml`). Check in game that it sits clear of the portrait and the close button.
6. Release workflow (`.github/workflows/release.yml`), not run yet:
   - `actions/checkout@v7`: UNVERIFIED that this major version exists. If it doesn't, the job fails at checkout.
   - `BigWigsMods/packager@v2` with a lone `## Interface: 16001`: UNVERIFIED how the packager maps 16001 to a game version. It may matter only for a CurseForge upload, which is skipped without `CF_API_KEY` and `X-Curse-Project-ID`.
   - With tracked `Libs/` and no externals, the packager needs no svn. Expected zip: tracked files minus `MEMORY.md` (`.pkgmeta` ignore). Whether dot-folders such as `.github` are left out by default is UNVERIFIED.
7. Nothing has been packaged end to end (bash 3.2, no svn locally).

## Feature questions for the owner

Round 1 (tooltip content, community channels) is decided and implemented in `5ea139b`. Open:

1. Sender colour. Today the sender is `YELLOW_FONT_COLOR`. Blizzard's chat colours the sender by class when the channel's "colour names by class" setting is on (`ChatFrameUtil.ShouldColorChatByClass`, `ChatFrameUtil.lua:891,1100`).
   - Keep yellow: no change.
   - Follow Blizzard: read field 12 (guid, not `NeverSecret`, so after the lockdown check), then `GetPlayerInfoByGUID` and `RAID_CLASS_COLORS` when the setting is on. About 8 lines in `Core/Scanner.lua`.
2. Chat that is not a channel: guild and officer chat (guild community streams included), party, raid and instance chat, say and yell, whispers. None is scanned.
   - Leave: no change.
   - Scan them: one event per chat type, and a "chat types" list in the panel next to the channels. A medium feature, about 60 to 100 lines, plus UI space.
3. Community streams not added to any chat tab. They are no chat channel and never reach the chat events.
   - Leave: no change; the player adds the stream to a chat tab to scan it.
   - Scan them: `CLUB_MESSAGE_ADDED` with `C_Club.GetMessageInfo`, and stream listing from `C_Club.GetSubscribedClubs`/`GetStreams`. A new path of about 50 lines, with its own secret rules to verify.
4. Channel tag as a link. Blizzard's chat makes the channel tag a `|Hchannel:channel:N|h` link that opens the edit box on that channel (`ChatFrameOverrides.lua:655-658`). ChatScan's tag is plain text.
   - Keep plain: no change.
   - Link it: one line in `channelTag`.

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
- [ ] Tick it, add a keyword, and have a community member post it: the line lands with the channel tag in that channel's colour. Right-click the sender: the community menu opens. Repeat for a Battle.net community.
- [ ] Change a channel's colour in the chat settings: the next match's tag uses the new colour. The `[Chat Scan]:` prefix is yellow.
- [ ] Hover the minimap button and the compartment entry: title, one status line, "Left-click to toggle the panel." and nothing else.
- [ ] Open the panel in a locked dungeon: community channels show the raw `Community:<id>:<id>` name without errors.
- [ ] `/reload` resumes the scan. `/cs stop` then `/reload` doesn't. `/cs <kw>`, `start`, `stop` and `clear` all work.
- [ ] A second character starts with empty settings; the minimap button position is shared.
- [ ] The Addon Compartment lists Chat Scan: click toggles, hover shows the tooltip.
- [ ] Enter a dungeon while scanning with no chat traffic: "Chat locked by client" appears without waiting for a message (if the dungeon locks chat), and clears after leaving.
- [ ] Check `/dump C_ChatInfo.InChatMessagingLockdown()` in the open world, a city, a dungeon, a battleground and during an encounter. This settles issue 1.
- [ ] In a locked dungeon: `/run local f=CreateFrame("Frame") f:RegisterEvent("CHAT_MSG_CHANNEL") f:SetScript("OnEvent",function(_,_,m) print(pcall(issecretvalue,m)) end)`, then wait for a channel message. This decides the optional CS-7 guard.
- [ ] Mute SFX with Master on and record whether the alert plays.
