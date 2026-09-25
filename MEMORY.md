# ChatScan: Development Memory

Read this before touching the code. Addon-specific facts only. Shared WoW Forever client facts live in `Cortex/WoW/Forever Client Facts.md` in the Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`). Section 5 lists what that note is now missing or has wrong.

Nothing here has run in a game client. Every claim is checked against source, not observed.

## 1. Status on 2026-09-25

| Item | State |
|---|---|
| Version | 2.0.0, WoW Forever 1.60.x only |
| Interface | `16001`, from Ketho `BlizzardInterfaceResources` `forever` README: `GetBuildInfo() => "1.60.1", "70009", "Sep 23 2026", 16001` |
| Verified against | `Gethe/wow-ui-source` `forever` @ `bd2470a` "1.60.1 (70009)", `Ketho/BlizzardInterfaceResources` `forever` @ `4149af6` |
| Installed client | `_classic_beta_` 1.60.1.69913, one build older than the source checked |
| Classic 1.15.x | Branch `1.15.x-backup` @ `9d96159` (Interface 11509, flat `ChatScan.lua`, version 1.0.0). Local only until pushed |
| Dual-client 1.3.0 WIP | Commit `eb2728c` on `main`, the uncommitted Core/UI + Compat restructure as it was found |
| Static checks | `luac -p` clean on every file. A scratch harness (not shipped) stubbing the 1.60 API passed 47 of 47 checks |
| In-game checks | None. Blocked on beta access, see section 7 |

## 2. Architecture

One client, no compatibility layer. `Core/Compat.lua` is gone. Every API is called directly because every one is verified on `forever`.

| File | Role |
|---|---|
| `ChatScan.toc` | Load order is dependency order. Libs, then Core, then UI, then Bootstrap |
| `Core/Init.lua` | Namespace, player-facing title `Chat Scan`, icon id, sound presets, helpers |
| `Core/Store.lua` | Per-character saved variables, resolved once at `PLAYER_LOGIN` and cached |
| `Core/Scanner.lua` | `CHAT_MSG_CHANNEL` handler, lockdown gate, matching, dedup, delivery, scan state |
| `Core/Commands.lua` | `/cs` and `/chatscan` |
| `UI/Design.lua` | Shared panel design. Must stay byte-identical across the author's addons (section 3) |
| `UI/Panel.lua` | Config window |
| `UI/MinimapButton.lua` | LibDataBroker launcher and LibDBIcon button, tooltip built from Blizzard's tooltip line helpers |
| `Bootstrap.lua` | `PLAYER_LOGIN` only: store, minimap button, resume |

Rules that keep it lean:

- The scanner reads settings straight from the store at match time. No mirrored runtime tables, no setter API between panel and scanner.
- Only `Scanner.OnChanged` couples scanner to UI.
- `ns.name` (`ChatScan`) is the folder and LibDBIcon key and never changes. `ns.TITLE` (`Chat Scan`) is what players read.

### Saved variables `ChatScanDB`

```
ChatScanDB = {
  minimap = { hide = false, minimapPos = 195 },   -- account-wide, owned by LibDBIcon
  ["<Name>-<Realm>"] = {
    inputChannels = { trade = true },              -- ns.channelKey(), zone suffix stripped
    outputs       = { loot = true },               -- lowercased chat tab names
    keywords      = { "wts", "lf, tank" },         -- one OR row each, commas are AND terms
    scanEnabled   = false,
    playSound     = true,
    soundId       = 3175,
  },
}
```

The 1.1.0 zone-key migration was removed. Forever has its own `WTF` tree, so no Classic save can reach it.

## 3. Shared panel design (`UI/Design.lua`)

ChatScan is the first addon ported with it, so this file is the reference copy. Copy it verbatim into the next addon. It contains no addon name, and its font objects are named `<ADDON_NAME>Font<Style>` from the toc vararg, so identical copies never share or restyle each other's fonts.

| Token | Value |
|---|---|
| `SPACE` | XS 8, S 16, M 24, L 32, XL 40, XXL 48. The only margins, paddings and gaps allowed |
| `CONTROL_H` | 24 for buttons, inputs, checkboxes and dropdowns |
| `HEADER_H` | 64: `ButtonFrameTemplate` title bar plus the portrait (62px at y +7, bottom edge near -55) |
| `FOOTER_H` | 40 = XS + CONTROL_H + XS |
| `Snap(h)` | Rounds measured heights up to 8, because text metrics are off-grid |

Five text styles come from tooltip fonts, snapped from 14/12/10 onto a 4px grid, with colours from Blizzard's tooltip helpers:

| Style | Source font | Size | Colour | Tooltip helper |
|---|---|---|---|---|
| TITLE | `GameTooltipHeaderText` | 16 | `HIGHLIGHT_FONT_COLOR` | `GameTooltip_SetTitle` |
| HEADING | `GameTooltipHeaderText` | 16 | `NORMAL_FONT_COLOR` | `AddNormalLine` |
| SUBHEADING | `GameTooltipText` | 12 | `NORMAL_FONT_COLOR` | `AddNormalLine` |
| TEXT | `GameTooltipText` | 12 | `HIGHLIGHT_FONT_COLOR` | `AddHighlightLine` |
| HELPER | `GameTooltipText` | 12 | `DISABLED_FONT_COLOR` | `AddDisabledLine` |

Built with `CreateFont` + `CopyFontObject` + `SetFontHeight`. The last one is documented as "Preserves all flags", so per-alphabet members survive. ChatScan uses HEADING, TEXT and HELPER. TITLE and SUBHEADING stay in the file because it is a shared copy. The window title is the template's own `TitleText` and is left native.

ChatScan layout: `PANEL_W` 616, so two `InsetFrameTemplate` columns of 296 with XS margins and an XS gap. Columns sit at XS from the frame edges, between `HEADER_H` and `FOOTER_H`, replacing the template's `Inset`, which is hidden. Column padding S, section gap M, heading to helper XS, helper to content XS. Checkbox rows pitch 24 with no gap. Keyword rows pitch 24 + XS. Dropdown 160, Add 48, Test 64, Start 96. Footer status text starts at XS + S so it lines up with the column content.

The input box sits XS inside its row because `InputBoxVisualTemplate` draws its left border 5px outside the frame. XS lines the visible border up with the checkbox art.

The attic summary line from the 1.3.0 WIP was dropped. The released Classic panel never had it, and every section has its own helper line.

## 4. What was verified, and where

All on `forever` @ `bd2470a` unless marked.

Chat:

- `CHAT_MSG_CHANNEL` payload (`ChatInfoDocumentation.lua`): 1 text, 2 playerName, 8 channelIndex, 9 channelBaseName, 11 lineID, 17 suppressRaidIcons. Event is `SecretInChatMessagingLockdown`. text and playerName carry no `NeverSecret`. 8, 9, 11 and 17 do, so the channel filter runs before the lockdown gate and is safe.
- `C_ChatInfo.InChatMessagingLockdown()` takes no arguments, returns `isRestricted`.
- `C_ChatInfo.ReplaceIconAndGroupExpressions(input, noIconReplacement, noGroupReplacement)` is `AllowedWhenTainted`. Blizzard's own chat passes arg17 as `noIconReplacement` (`Mainline/ChatFrameOverrides.lua:570`). ChatScan now does the same. Before, it always rendered icons.
- `GetPlayerLink(name, text, lineID, chatType, chatTarget)` in `Blizzard_SharedXML/LinkUtil.lua`. Blizzard's chatTarget for channels is `tostring(channelIndex)` (`FCFManager_GetChatTarget`). Replaces the hand-built `|Hplayer:` link.
- `Constants.ChatFrameConstants.MaxChatWindows` is used directly by Blizzard's `FloatingChatFrame.lua`, so there is no fallback to `NUM_CHAT_WINDOWS`.
- ChatFrame2 is reset as `COMBAT_LOG` and docked at 2 (`FCF_ResetChatWindow(ChatFrame2, COMBAT_LOG)`), so index 2 is still skipped.
- `GetChannelList()` returns `(id, name, disabled)` triples (`ChatConfigFrame.lua` `CreateChatChannelList`). `GetChatWindowInfo`, `FCF_StartAlertFlash`, `SELECTED_CHAT_FRAME` and `DEFAULT_CHAT_FRAME` are all present.
- Events `CHAT_MSG_CHANNEL`, `CHANNEL_UI_UPDATE`, `CHAT_MSG_CHANNEL_NOTICE` and `PLAYER_LOGIN` appear in Ketho `Events.lua`.

UI:

- `ButtonFrameTemplate`: `Inset` at (4, -60) / (-6, 26), close button via `UIPanelCloseButtonDefaultAnchors`. The Camelot override moves it to `TOPRIGHT -2, 1`. `SetTitle` comes from `TitledPanelMixin` and `SetPortraitToAsset` from `PortraitFrameMixin`.
- `InsetFrameTemplate`, `UICheckButtonTemplate` (32x32, `.Text` via parentKey), `InputBoxTemplate`, `UIPanelButtonTemplate` (three-slice `Left`/`Middle`/`Right`, no NormalTexture).
- `UIPanelCloseButton` runs `UIPanelCloseButton_OnClick`, which hides the parent. The keyword remove button now uses `UIPanelCloseButtonNoScripts`, the same art with no script.
- `WowStyle1DropdownTemplate` comes from `Blizzard_Menu/[Family]` = Mainline on Camelot, 120x25. `SetDefaultText` comes from `DropdownSelectionTextMixin`. `SetupMenu`, `GenerateMenu` and `CreateRadio` are present.
- `UISpecialFrames` is present (`Blizzard_UIParentPanelManager`). `tDeleteItem` = `table.removevalue`.
- Colours `NORMAL`, `HIGHLIGHT`, `DISABLED`, `GRAY`, `GREEN` and `WARNING_FONT_COLOR`, plus `ColorMixin:WrapTextInColorCode`, are all used by Blizzard code on `forever`.
- Tooltip helpers `GameTooltip_SetTitle`, `AddHighlightLine` and `AddInstructionLine` live in `Blizzard_SharedXML/SharedTooltipTemplates.lua`.
- All six `SOUNDKIT` keys are in `Blizzard_SharedXML/Mainline/SoundKitConstants.lua`, with the same ids as Classic.
- There is no Addon Compartment at runtime (absent from Ketho `Frames.lua`), so LibDBIcon stays the launcher. LibDBIcon guards `AddonCompartmentFrame` itself.

Icon: file id 134442 = `interface/icons/inv_misc_spyglass_03.blp` in `wowdev/wow-listfile` release `202609242243`. The listfile is game-wide, so presence in Forever's art data is not proven.

## 5. Learnings

Not verifiable, so changed or left out:

- `PlaySound(id, "Master", true)`: no Blizzard code on `forever` passes a channel string. The doc types the argument as `UISoundSubType`, with a C default, and the only nearby enum is `Si3UISoundSubType`, which is numeric. ChatScan now calls `PlaySound(id)`, so the alert plays on the default sound channel and follows the SFX toggle, not Master. This is a behaviour change. Reverting it needs an in-game check.
- `UnitName` is `SecretWhenUnitNameIdentityRestricted`. Whether `"player"` is ever secret is not stated. The store key is built once at login to keep exposure minimal.

Facts missing from or wrong in `Forever Client Facts.md` (I could not edit it from this repo):

- `Ketho/BlizzardInterfaceResources` now has a `forever` branch (`4149af6`, 1.60.1 70009). The note says it has none.
- `Gethe/wow-ui-source` `forever` moved from `70ef1b2` (69913) to `bd2470a` (70009) on 2026-09-24.
- BigWigs packager v2.6.1 (2026-09-18) supports Forever: `16???` maps to game type `forever` (also `camelot`), CurseForge game id 88568, and TOC splitting writes `_Camelot.toc`. WoWInterface uploads mark it unsupported. The old "no packager keyword for Camelot" is obsolete. The `_Camelot` suffix is the packager's choice, not proof of what the client loads.
- `WOW_PROJECT_ID` is 1 (Mainline), now confirmed by Ketho's dump, no longer "reportedly".
- The GitHub MCP was not available in this session. Every check went through raw GitHub and the GitHub API against the same two repositories.

Libraries:

- All four are needed. LibDBIcon has no native replacement (see above), and it needs LibStub, CallbackHandler-1.0 and LibDataBroker-1.1.
- Every bundled copy already matched upstream latest: LibStub 2, CallbackHandler-1.0 8, LibDataBroker-1.1 4, LibDBIcon-1.0 56. The differences were only svn `$Id$` lines and one comment URL.
- They are now pulled dynamically through `.pkgmeta` externals. This works without CurseForge hosting: the BigWigs packager fetches externals itself, skips the CurseForge upload when there is no `CF_API_KEY` or project id, and publishes a GitHub release. Its GitHub Action installs subversion when it detects svn externals (`setup-packager.sh`). `Libs/` is untracked and gitignored. The local folder keeps copies refreshed from the same upstream paths, so the in-game copy still loads.
- A local packager run needs bash 4.3+ and svn. This Mac has bash 3.2 and no svn, so no end-to-end package was built here. The first tag push is the real test.

## 6. Next steps

1. Push `main` and `1.15.x-backup` to `origin`. The backup exists only locally, and `main` is 3 commits ahead. This needs miyanko's go-ahead.
2. Tag `v2.0.0` (annotated) and confirm the `Package and release` workflow builds `ChatScan-v2.0.0.zip` with all four libs under `Libs/` and without `MEMORY.md`.
3. Create the CurseForge project under the WoW Forever game (id 88568). Then add `## X-Curse-Project-ID: <id>` to the toc and a `CF_API_KEY` repo secret, so tags upload by themselves.
4. Run the beta checklist below and write the results into section 8.
5. Copy `UI/Design.lua` verbatim into the next addon being ported.
6. Fold section 5's client facts into the vault note.

## 7. Beta checklist

`/console scriptErrors 1` first. Record build, character and zone for each item.

Critical:

1. `/dump C_ChatInfo.InChatMessagingLockdown()` on a normal realm, in the open world. `false` means ChatScan works. `true` means addons cannot read chat there, and items 12 to 20 cannot be tested.
2. `/dump select(4, GetBuildInfo())` returns `16001`, and ChatScan is listed and enabled at character select with the spyglass icon.
3. Log in: no Lua error, and no Chat Scan output on a fresh install.
4. Repeat item 1 inside a dungeon, a battleground and during combat, to learn where lockdown starts.

Panel:

5. `/cs` opens `Chat Scan 2.0.0` with the spyglass portrait. Two equal columns, an 8px gap and 8px outer margins. Nothing overlaps the portrait or the close button. `/framestack` should show the columns 296 wide and the frame height a multiple of 8.
6. Type: section headings 16px gold, helper lines 12px grey and readable, checkbox labels 12px white. Headings should not look oversized next to the 12px window title. If they do, the shared design changes in every addon.
7. Keyword input: the visible border lines up with the checkbox art above it, and the Add, X and dropdown arrow are neither clipped nor squashed at 24px height.
8. Escape and the corner X close the window. Dragging moves it and keeps it on screen. It grows as channels are joined, without the footer overlapping.
9. Start is bottom right with the status text on the same line. While scanning the button is red and reads Stop.

Channels and keywords:

10. Join Trade and General. Both are listed with full names. Leave one while the panel is open and the list updates.
11. Type `wts`: Add appears. Enter keeps the text, Add turns into X, and a new empty row appears. X removes the row. `/reload` keeps the list.

Matching, needs a second character:

12. Tick Trade and the Loot tab, add `wts`, then Start. The status reads `Scanning 0 matches`, not the warning colour.
13. Post `WTS {skull} Thunderfury` in Trade. Exactly one line in Loot with `[HH:MM] [Trade - City] [Name-Realm]:`, the skull icon rendered, the Loot tab flashing while another tab is selected, and one alert sound.
14. Post `WTS {rt3} thing`: the icon renders.
15. Left-click the sender opens a whisper. Right-click opens the player menu with no error. This exercises `GetPlayerLink`'s lineID and channel target.
16. Repeat within 10 s: not shown. After 10 s: shown.
17. A non-match in Trade, and a match in unticked General: nothing forwarded.
18. Untick Loot while scanning: the match goes to the default frame. Untick Trade: nothing.
19. Change zone and post in General with General ticked: it still matches.
20. Is the sender shown with `-Realm`? If Blizzard's chat drops the realm for your own realm and ChatScan does not, note it. That is cosmetic, not a bug.

Sound:

21. The dropdown lists six sounds, the current one marked, and each plays on pick. Test replays it.
22. With in-game SFX volume muted but Master on, does the alert still play? It is not expected to, now that `"Master"` is gone (section 5). Decide whether that is acceptable.
23. Untick "Play sound on match": the line arrives with no sound.

Persistence and commands:

24. `/reload` while scanning prints `Scanning N channel(s)...` and the panel shows Stop. After `/cs stop` and a `/reload`, nothing resumes.
25. Settings survive logout. A second character gets empty, independent settings.
26. `/cs thunderfury` adds and starts. `/cs stop`, `/cs start` and `/cs clear` work, and an open panel updates. `/chatscan` behaves the same.

Minimap:

27. The spyglass sits on the Camelot minimap ring, drags around it, and stays put after `/reload`. The tooltip shows state, a green left-click hint and the commands.

Lockdown, if item 1 or 4 ever returns `true`:

28. While scanning, one chat notice, `Chat locked by client` in the panel and the tooltip, and no Lua error. When it lifts, one "readable again" notice and matching resumes.

## 8. Test results

Empty.

## 9. If something breaks

| Symptom | Look at |
|---|---|
| Missing from the addon list | `## Interface` against `/dump select(4, GetBuildInfo())` |
| Error at login | `Store.Init` in `Core/Store.lua`. Is `UnitName("player")` secret there? |
| Scanning but never matching | `/dump C_ChatInfo.InChatMessagingLockdown()` |
| Error opening the panel | `buildPanel` in `UI/Panel.lua`. `/framestack` shows how far it got |
| Wrong layout | Tokens in `UI/Design.lua` (shared, change in every addon) or the width constants at the top of `UI/Panel.lua` |
| No sound | `/run PlaySound(3175)`. If silent with SFX muted, see checklist item 22 |
| Libs missing after a fresh clone | Run the packager, or copy the four paths listed in `.pkgmeta` into `Libs/` |
