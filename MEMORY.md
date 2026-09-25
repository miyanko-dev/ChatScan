# ChatScan — Development Memory

The single persistent note for this addon. Read it before touching the code instead of re-deriving anything. Everything here was established without a running client; nothing has ever been loaded by a game client, so sections 9 and 10 are the parts that still matter. Consolidated on 2026-09-19 from `NEXT-STEPS.md` and `Tools/README.md` (both deleted). Supersedes the 1.2.0 note.

**Verified against:** `forever` @ `70ef1b2` (1.60.1.69913), 2026-09-21.

**Shared 1.60 client facts are not in this file.** They live in one place: `Cortex/WoW/Forever Client Facts.md` in the Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`). Read that first — this note records only what is specific to this addon, and never restates a fact about the client. Companions there: `Two-Version Addon Architecture.md` (layout), `UI Compatibility Analysis.md` (templates and widgets). Run `../check-client-facts.sh` to see whether any of it has gone stale.

---

## 1. Status on 2026-09-19

ChatScan 1.3.0 is restructured into `Core/` + `UI/`, statically verified against both target clients, and expected to work. **All changes are uncommitted** and **no in-game test has ever been run.**

| Item | State |
|---|---|
| Version | 1.3.0 (committed state is still 1.0.0) |
| Target clients | Classic Era 1.15.x (`## Interface: 11509`), WoW Forever 1.60.x (`## Interface: 16001`) |
| Verified against | `Gethe/wow-ui-source` `classic_era` @ `33e177d` "1.15.9 (69722)" and `forever` @ `70ef1b2` "1.60.1 (69913)" |
| Locally installed | **Forever beta only** (`_classic_beta_`, 1.60.1.69913). Classic Era is not installed |
| Repo | `miyanko-dev/ChatScan`, branch `main`, HEAD `9814b43` |
| Working tree | ` D ChatScan.lua`, ` M ChatScan.toc`, ` M README.md`, `?? Bootstrap.lua`, `?? Core/`, `?? UI/`, `?? Tools/`, `?? MEMORY.md` |
| Static checks | Pass: syntax, toc resolution, load order, 38-case headless harness (re-run 2026-09-19: `38 passed, 0 failed`) |
| In-game checks | **None run.** Blocked on Forever beta access; miyanko will run section 10 himself once he has it |

---

## 2. How to resume

1. `lua Tools/harness.lua .` → expect `38 passed, 0 failed`. Takes a second and catches anything structural. Lua 5.2+ (Homebrew `lua` 5.5 works).
2. Seam check: `grep -rE 'GetBuildInfo|WOW_PROJECT|11509|16001' Core UI Bootstrap.lua` must return **nothing**. Any hit means a version branch escaped `Core/Compat.lua`.
3. Confirm every toc entry still resolves and nothing on disk is unlisted (section 4).
4. The highest-value unknown is check 1 in section 10. Until answered, the addon's core function on Forever is unproven.

---

## 3. Architecture and the rules that keep it working

One codebase, two game versions, following the playbook.

- `Core/` is version-neutral: **no** unguarded API call and **no** version branch.
- `Core/Compat.lua` is the **only** file allowed to branch on what an API does. If it grows, the Core/UI boundary is in the wrong place.
- Guards test for the **API**, never the interface number: `if C_Foo and C_Foo.Bar then`.
- Every file shares the namespace table from the toc vararg: `local ADDON_NAME, ns = ...`.
- Load order in the toc **is** the dependency order. A file-scope `local X = ns.Y` requires `Y` exported by an earlier toc entry. Only two files do this: `Core/Scanner.lua` captures `ns.Compat`; `UI/Panel.lua` captures `ns.Scanner`, `ns.Store` and `ns.Compat`. Everything else resolves at call time.
- `Bootstrap.lua` loads last and only wires `ADDON_LOADED` and `PLAYER_LOGIN`.

### Why there is only one toc

`ChatScan.toc` carries `## Interface: 11509, 16001` and serves both clients because both load an **identical file set**. The playbook's `UI/Vanilla` + `UI/Modern` split was considered and rejected: every template, mixin, constant and event the panel uses exists on both clients (section 8), so splitting would duplicate ~570 lines of `UI/Panel.lua` for no gain and create exactly the drift pitfall the playbook warns about.

**When to split:** the moment a client genuinely needs a different file. Then add `ChatScan_Vanilla.toc` listing the 1.15.x file set and leave `ChatScan.toc` as the fallback the 1.60 client resolves. Two identical file lists are a liability.

---

## 4. File map

| File | Role |
|---|---|
| `ChatScan.toc` | Single toc, both clients. Comment block inside explains the decision |
| `Core/Init.lua` | Namespace, constants, pure helpers. Touches no Blizzard API at load time |
| `Core/Compat.lua` | Every version-sensitive API behind a feature test. The only place a guard belongs |
| `Core/Store.lua` | Per-character saved variables and the 1.1.0 → 1.2.0 channel-key migration |
| `Core/Scanner.lua` | Parsing, matching, dedup, forwarding, scan state, the lockdown gate |
| `Core/Commands.lua` | Slash commands |
| `UI/Panel.lua` | The config window |
| `UI/MinimapButton.lua` | LibDBIcon launcher |
| `Bootstrap.lua` | Login bootstrap, loads last |
| `Tools/harness.lua` | Headless test harness. **Not in the toc**, never loaded by the client |
| `MEMORY.md` | This file |

Toc load order: Libs (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0), `Core\Init`, `Core\Compat`, `Core\Store`, `Core\Scanner`, `Core\Commands`, `UI\Panel`, `UI\MinimapButton`, `Bootstrap`. Bundled libraries, unmodified: LibStub r2, CallbackHandler-1.0 r8, LibDataBroker-1.1 r4, LibDBIcon-1.0 r56.

### `Core/Compat.lua` covers today

| Difference | Handling |
|---|---|
| Chat messaging lockdown (1.60 only) | `Compat.ChatPayloadReadable()` wraps `C_ChatInfo.InChatMessagingLockdown()` and gates the chat handler (section 5) |
| `NUM_CHAT_WINDOWS` deprecation | `Compat.MaxChatWindows()` reads `Constants.ChatFrameConstants.MaxChatWindows` first, then the global, then 10; resolved on first use |
| Sound presets | Resolved from `SOUNDKIT` on first use; a missing key drops its preset instead of storing a nil id |
| Addon metadata | `C_AddOns.GetAddOnMetadata` with fallback to the old global |
| Raid target markers | `C_ChatInfo.ReplaceIconAndGroupExpressions`, so `{skull}` renders as in Blizzard's chat, localised names included |

---

## 5. The one real compatibility bug found, and fixed

On 1.60, `CHAT_MSG_CHANNEL` is declared `SecretInChatMessagingLockdown = true`, and of its payload fields **`text` and `playerName` carry no `NeverSecret` flag**. While lockdown is active those two arrive as *secret values*, and any string operation on one aborts the calling handler.

The 1.2.0 handler did three immediately: `strlower(msg)` in `matchesKeywords`, concatenation of `sender` and `msg` in `isDuplicate`, and a `gsub` over `msg` in `renderIcons`. Every incoming channel message on a locked-down 1.60 realm would have thrown.

Classic Era has no secret system: `SecretInChatMessagingLockdown` appears **zero** times in its API documentation. On `forever` it appears 51 times: on **48 `CHAT_MSG_*` events** and on three `C_ChatInfo` functions, `GetChatLineText`, `GetChatLineSenderName`, `GetChatLineSenderGUID`. Those three would be the obvious workaround (read the line back by `lineID`), so the workaround is closed off too. There is no way to read channel text under lockdown.

### The fix

`Core/Compat.lua` exposes `Compat.ChatPayloadReadable()`. `Core/Scanner.lua` calls it **before unpacking the payload**; there is no safe way to inspect the fields first. Under lockdown the message is skipped, `Scanner.chatLocked` is set, and the user is told **once per transition**. `UI/Panel.lua` shows an amber "Chat locked by client" status and the minimap tooltip matches, so a scan that cannot match never shows a healthy green "Scanning" line. Forwarding a secret value was never an option: building the output line concatenates it.

### Which secret-related API to use

| Function | Arguments | Declared on `forever` | Safe for addon code? |
|---|---|---|---|
| `C_ChatInfo.InChatMessagingLockdown()` | **none** | no restriction | **Yes. Use this.** Cannot be handed a secret. Exists on both clients; 1.15 always returns false |
| `issecretvalue(v)` | a value | `SecretArguments = "AllowedWhenUntainted"` | **Inferred no** |
| `canaccessvalue(v)` | a value | `SecretArguments = "AllowedWhenUntainted"` | **Inferred no**, same annotation |
| `C_ChatInfo.ReplaceIconAndGroupExpressions(text, noIcon, noGroup)` | a string | `SecretArguments = "AllowedWhenTainted"` | **Yes**, one of only two functions accepting secrets from tainted code |

The inference: addon execution is tainted, and the client binary contains `"%s. Secret values are only allowed during untainted execution for this argument."`, so an `AllowedWhenUntainted` function handed a secret from addon code is expected to raise the very error it is meant to detect. **A declaration plus a binary string, not observed behaviour.** The design does not depend on it: the argument-free gate is correct regardless. See open question 2. The only two `AllowedWhenTainted` functions on `forever` are `C_ChatInfo.IsTimerunningPlayer` and `C_ChatInfo.ReplaceIconAndGroupExpressions`.

---

## 6. What else changed in 1.3.0

| Change | Why |
|---|---|
| Flat files → `Core/` + `UI/` + `Bootstrap.lua` | Playbook layout; `Core.lua` split into pure `Init.lua` and guarded `Compat.lua` |
| Raid markers via `C_ChatInfo.ReplaceIconAndGroupExpressions` | Native on both, handles localised marker names and `{rt1}`–`{rt8}`, which the hand-rolled 8-name `gsub` did not. `ns.RAID_ICONS` is gone |
| Sound presets resolved lazily from `SOUNDKIT`, missing keys dropped | A missing key used to store a nil id and silently kill the alert |
| `Compat.MaxChatWindows()` resolved on first use | A late-populated `Constants` table now wins over the fallback |
| Dropdown height 24, not 22 | Native is 60×24 on 1.15 and 120×25 on 1.60; 22 sat under both |
| Panel and minimap tooltip show a locked state | Section 5 |
| `Tools/harness.lua` added to the repo | The previous harness lived in a session scratchpad and was lost |

Carried over from 1.2.0 and still true: the panel is built entirely on native templates with no raw texture path and no `SetBackdrop`; zone channels are keyed without their ` - Zone` suffix with old keys migrated on load; sender links carry `name:lineID:CHANNEL`; the Start button is tinted through `Left`/`Middle`/`Right` because `UIPanelButtonTemplate` exposes no `NormalTexture` on either client; section frames use only `TOP*` anchors so no frame gets two vertical constraints; channel and output toggles apply to a running scan.

---

## 7. Data and constants

### SavedVariables `ChatScanDB`

```
ChatScanDB = {
  minimap = { hide = false, minimapPos = 195 },   -- account-wide, owned by LibDBIcon
  ["<Name>-<Realm>"] = {                          -- per character
    inputChannels = { ["trade"] = true, ... },    -- keys are ns.channelKey(), zone suffix stripped
    outputs       = { ["loot"]  = true, ... },    -- keys are lowercased chat tab names
    keywords      = { "wts", "lf, tank" },        -- one string per OR row, commas are AND terms
    scanEnabled   = false,                        -- drives Scanner.Resume() on login
    playSound     = true,
    soundId       = 3175,
  },
}
```

Same variable name on both clients, one schema, one migration path. The only migration is `migrateChannelKeys` in `Core/Store.lua`, folding pre-1.2.0 suffixed zone-channel keys (`general - elwynn forest`) onto the bare key (`general`). It rebuilds the table only when a stale key is present, so the common path allocates nothing.

### Behavioural constants (`Core/Init.lua`)

| Constant | Value | Meaning |
|---|---|---|
| `DEDUP_TTL` | 10 | seconds an identical sender+message is suppressed |
| `DEDUP_MAX` | 20 | recent-match ring size |
| `SOUND_THROTTLE` | 3.0 | seconds between alert sounds |
| `DEFAULT_SOUND_ID` | 3175 | `SOUNDKIT.MAP_PING`, kept literal so a saved id survives a constant rename |
| `COMBAT_LOG_INDEX` | 2 | ChatFrame2, never offered as an output |
| `ICON` | `Interface\Icons\INV_Misc_Spyglass_03` | single place to change the icon |

### Panel layout constants (`UI/Panel.lua`, top of file)

`INSET_TOP 60` / `INSET_BOTTOM 26` / `INSET_LEFT 4` / `INSET_RIGHT 6` mirror `ButtonFrameTemplate`'s own `Inset` anchors, identical on both clients. Then `PANEL_W 620`, `COL_GAP 4`, `PAD 12`, `GAP 8`, `SECTION_GAP 16`, `ROW_H 22`, `DROPDOWN_H 24`, `ROW_GAP 4`, `CB_SIZE 24`, `HEADER_GAP 6`, `BUTTON_BAR_Y 4`, `ATTIC_TEXT_X 62`. These are the knobs for any "panel looks wrong" report.

### Slash commands (`Core/Commands.lua`)

`/cs` toggles the panel; `/cs <keyword>` adds a keyword (`word1,word2` = AND group) and starts; `/cs start`; `/cs stop`; `/cs clear`. `/chatscan` is an alias.

---

## 8. What was verified, and how

Confirmed present and equivalent on **both** branches, each in a file that client's load manifest reaches:

- `ButtonFrameTemplate`: `Inset` anchored `TOPLEFT 4,-60` / `BOTTOMRIGHT -6,26`, byte-identical, which is why one set of `INSET_*` constants fits both. Era inherits `PortraitFrameTemplate`, Forever inherits `ButtonFrameBaseTemplate`. **No template in either inheritance chain declares a frame-level `OnShow`, `OnHide` or `OnEvent`**, so `UI/Panel.lua` setting its own clobbers nothing. The one frame-level script in either chain is Era's `PortraitFrameTemplateNoCloseButton`, which carries an `OnLoad` (`PortraitFrameTemplateMixin:OnLoad`, swapping to high-res atlases when `useHighResolutionUITextures` is set). The addon never sets `OnLoad`, so that survives.
- `PortraitFrameMixin` on both, supplying `SetTitle` and `SetPortraitToAsset`. The real portrait path is `PortraitContainer.portrait`, **not** `frame.portrait` as the 1.2.0 note claimed.
- `InsetFrameTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButton`.
- `UICheckButtonTemplate` with its `.Text` region, identical on both. `UI/Panel.lua` creates checkboxes **unnamed**; the template declares `<FontString name="$parentText" parentKey="Text">`. Safe: `.Text` comes from `parentKey`, which is name-independent; the template's `UICheckButtonFontString_SetParentKeyAlias` OnLoad only does `parent.text = fontString`. An unnamed parent simply means no global is created.
- `InputBoxTemplate` on both, though 1.15 defines it in `SecureUIPanelTemplates.xml` and 1.60 in `Shared/InputBox/InputBoxTemplates.xml`.
- `WowStyle1DropdownTemplate` as a real `DropdownButton` frame type with `SetupMenu` and `root:CreateRadio`. Era `Blizzard_Menu/Classic/MenuTemplates.xml` at 60×24, Forever `Mainline/` at 120×25. **The largest assumed risk in the 1.2.0 note, and it holds.**
- `UISpecialFrames` (`Blizzard_UIParentPanelManager/Shared/`), `FCF_StartAlertFlash`, `SELECTED_CHAT_FRAME`, `DEFAULT_CHAT_FRAME`.
- `Constants.ChatFrameConstants.MaxChatWindows` = 10 on both. **Gotcha:** this client-side table is *not* the bare Lua global `ChatFrameConstants` in `Blizzard_ChatFrameBase/Shared/ChatFrameConstants.lua`, which has no `MaxChatWindows`. Two same-named tables.
- All six `SOUNDKIT` preset ids.
- `CHAT_MSG_CHANNEL` payload order: arg 9 `channelBaseName` (matches `GetChannelList()` names), arg 11 `lineID`.
- `C_ChatInfo.InChatMessagingLockdown` and `C_ChatInfo.ReplaceIconAndGroupExpressions`.

### Expected cosmetic difference, not a bug

Era draws explicit textures (rock background, portrait ring, bottom button-bar ridge from `UI-Frame-BtnCornerLeft/Right` and `_UI-Frame-BtnBotTile`). Forever drives the border from `layoutType = "PortraitFrameTemplate"` in `Mainline/NineSliceLayouts.lua` with `UI-Frame-Metal-*` atlases and has **no** bottom ridge under the button bar. Both reserve the same 60px top and 26px bottom bands, so the Start button and status line land identically. **The button bar looks plainer on Forever. That is correct.**

### Toc suffix probe, closed enough to act on

The 1.60 binary contains `%s%%s.toc` followed by a `%s.toc` fallback, and the only flavor token in its addon-loader string block is `Camelot` (no `_Camelot` literal). The suffix spelling stays unproven; the **plain `<Addon>.toc` fallback is certain**, which is what ChatScan relies on. Multi-value `## Interface:` lines are proven in the wild on both clients: `Questie-Classic.toc` ships `11508, 11509` for Era, and `SpeedyAutoLoot` ships `11509, 16001, 20506, 50504, 38002, 120100` in one toc in this very folder.

### How to re-verify against the UI source

Use GitHub MCP against `Gethe/wow-ui-source`, pinned to the branch and commit matching the installed build (`.build.info`). GitHub code search only indexes the **default** branch: use it to find *where* a symbol lives, then fetch that path on `classic_era` / `forever` explicitly. Fetching a branch's full tree at once is the cheapest way to answer "which file defines X":

```sh
curl -sL "https://api.github.com/repos/Gethe/wow-ui-source/git/trees/forever?recursive=1"
```

**Caveat:** Gethe's `forever` export is a full manifest containing files for every game type, and it can omit files a toc references. Presence in the tree proves a file exists in the build; **absence proves nothing**. Client-side facts (string tables, toc resolution) are better checked with `strings` on `_classic_beta_/World of Warcraft Beta.app/Contents/MacOS/World of Warcraft`.

### Headless harness (`Tools/harness.lua`)

A stub WoW client that loads `ChatScan.toc`'s file list in order and drives the store, the scanner, the panel and every slash command, including an active 1.60 chat messaging lockdown.

```sh
lua Tools/harness.lua .        # → 38 passed, 0 failed
```

Exits non-zero on the first failing expectation. Lua 5.2 or newer; shims the 5.1 globals `unpack` and `loadstring` that WoW provides. From a test: toggle lockdown with `M.lockdown = true`, advance the dedup clock with `M.advance(seconds)`, inspect forwarded lines in `M.chatOutput`.

**What it proves:** load order, that every `ns.*` capture resolves against an earlier toc entry, keyword matching and dedup, channel-key normalisation across a zone change, delivery routing and tab flashing, the lockdown gate engaging and lifting, panel construction on `ButtonFrameTemplate`, and slash-command control flow. In detail: store migration from a 1.1.0-shaped save, a full match with native icon rendering and a `player:name:lineID:CHANNEL` link, delivery to the right tab, tab flash, sound, dedup and TTL expiry, non-match and unscanned-channel rejection, a match surviving a zone change, lockdown engaging and lifting with a once-only notice, panel construction on `ButtonFrameTemplate` with title and portrait, all four slash commands.

**What it cannot prove:** rendering, layout against real font metrics, taint, real event delivery, whether lockdown is active on a live realm, what a genuine secret value does to a string operation, anything about art files.

---

## 9. Open questions

Ordered by cost if the answer is bad.

1. **Is chat messaging lockdown on by default on a normal 1.60 realm?** Nothing static answers this. If yes, ChatScan's core function is unavailable on Forever until Blizzard changes policy, and so is every other chat-scanning addon. Check 1 in section 10.
2. **Do `issecretvalue` / `canaccessvalue` raise for a tainted caller holding a secret?** Section 5 infers yes; not observed. ChatScan does not depend on the answer. **SuperSocial does** (section 12).
3. **Does `## Interface: 16001` load on 1.60.1?** Derived from the build and matching four other addons in this folder, but no addon has been *confirmed* loading on this client. If ChatScan is missing from the addon list, first suspect.
4. **Does `Interface\Icons\INV_Misc_Spyglass_03` exist in Forever's art data?** Icon file names are not in the UI source repos. A missing icon shows as a green-and-black question mark. `ns.ICON` in `Core/Init.lua` is the single place to change it.
5. **Is `## IconTexture: 134442` a valid file id on both clients?** Only affects the character-select addon list.
6. **Does the panel render cleanly at 620px wide on both?** All layout arithmetic was done against source constants, never measured. `ATTIC_TEXT_X = 62` clears the portrait on 1.15; Forever's portrait geometry differs and the summary line may need adjusting.
7. **Does `WowStyle1DropdownTemplate` look right at 160×24?** Native is 60×24 on Era and 120×25 on Forever; watch for a squashed or clipped arrow. Era justifies its label `RIGHT`, Forever `LEFT`: native behaviour, not a bug.
8. **Where does the minimap button land on the Camelot minimap skin?** LibDBIcon r56 computes positions from `Minimap` dimensions and `GetMinimapShape`. Camelot has its own minimap `Skin.lua`, so the button may sit off the ring until dragged.
9. **Does hiding `frame.Inset` leave any artifact?** The template's own inset is hidden in favour of the two column insets. Hiding a parent hides its children, so this should be clean.

---

## 10. In-game verification, in priority order

Blocked: the client is installed but miyanko does not have Forever beta access yet. He will run this himself once he does, so leave it unrun rather than re-planning it.

Run on Forever 1.60.1 first. `/console scriptErrors 1` first.

### Critical, before anything else

1. **`/dump C_ChatInfo.InChatMessagingLockdown()`** on a normal realm. `false` → ChatScan works fully, continue. `true` → addons cannot read chat text on this realm at all; ChatScan will say so and pause, and everything from step 7 down is untestable. Open question 1, the single most important thing to establish.
2. **`/dump select(4, GetBuildInfo())`**: confirm `16001` (open question 3).

### Load

3. Addon appears **enabled** in the character-select addon list with the spyglass icon (exercises `## IconTexture`, question 5).
4. Log in. No Lua error, no `[ChatScan]` chat output on a fresh install.
5. Spyglass sits on the minimap ring. Drag a quarter turn, `/reload`, it returns where dropped. *Failure:* question 4 (wrong icon) or 8 (wrong position).

### Panel

6. `/cs` opens the window. Check: title reads `ChatScan 1.3.0` and the portrait shows the spyglass; two inset columns of roughly equal width, 4px gap, even margins; the grey summary line sits between title bar and insets and does **not** overlap portrait or close button; section headers yellow, helper lines grey and fully readable; Start bottom right, status text to its left on the same line. *Failure:* question 6; knobs in section 7.
7. Escape closes it. The corner X closes it. Dragging moves it and it stays on screen.
8. With one or two channels joined the window is short; join several more and reopen: it grows without the button bar overlapping the columns.
9. The button bar looks plainer than on Era (no bottom ridge). **Expected**, section 8.

### Channels and keywords

10. Join Trade and General. Both appear as checkboxes labelled with full names including zone. Tick Trade.
11. Leave a channel while the panel is open. The list updates within a second.
12. Type `wts` into the empty keyword row. An Add button appears. Enter. The row keeps the text, Add becomes an X, a new empty row appears below.
13. Press the X. The row disappears. `/reload`: remaining keywords still listed.

### Matching, needs a second character or a friend

14. Tick the Loot tab under Output Tabs, add keyword `wts`, press **Start**. Button turns **red** and reads **Stop** (grey means the three-slice tint is wrong for this client). Status reads `Scanning 0 matches`, **not** amber "Chat locked by client".
15. Post `WTS {skull} Thunderfury` in Trade from the other character. Confirm all five: one line in the **Loot** tab; prefixed `[HH:MM]` and `[Trade - City]`; `{skull}` rendered as the icon; the Loot tab flashes while another tab is viewed; the alert sound plays once.
16. Post `WTS {rt3} thing`: `{rt3}` must render too. New in 1.3.0.
17. Left-click the sender's name → whisper window. Right-click → player menu, no Lua error. This is what the `lineID` in the link is for.
18. Repost the same message within 10 seconds → **not** shown again. After 10 seconds → shown.
19. Non-matching message in Trade → nothing. Matching message in General (unticked) → nothing.
20. **Live toggles while scanning:** untick the Loot tab, post a match → default chat frame. Untick Trade, post a match → nothing. Re-tick both → resumes.
21. **Zone-change test:** tick General, start, confirm a match in General, walk to a different zone, post another matching message in General. **It must still match.** If not, `ns.channelKey` in `Core/Init.lua` is not stripping this client's zone suffix format.

### Sound

22. Open the sound dropdown: six named entries, the current one marked. Pick each: each plays immediately. **Test** replays the current one. *Failure:* question 7.
23. Untick "Play sound on match", post a match → line arrives, no sound.

### Persistence

24. With a scan running, `/reload` → scan resumes and prints `Scanning N channel(s)...`. Panel: Start shows **Stop** in red, match count reset to 0 (expected, per session).
25. `/cs stop`, `/reload` → nothing resumes, nothing printed.
26. Log out and in → keywords, channels, output tabs and sound choice survive.
27. Second character → independent and empty settings. Switch back → intact.
28. **Upgrade path**, if an old save exists: with a `ChatScanDB` from 1.0.0/1.1.0 that had a zone channel ticked, load 1.3.0 and confirm it is still ticked and `WTF/Account/<name>/SavedVariables/ChatScan.lua` now shows `general` rather than `general - elwynn forest`.

### Commands

29. `/cs` toggles. `/cs thunderfury` adds and starts. `/cs stop`. `/cs start`. `/cs clear` empties the list and an open panel updates live. `/chatscan` identical.

### Then

30. Install Classic Era 1.15.x and repeat 3–29. That half has never been exercised on any client.

---

## 11. Remaining development tasks

1. **Commit the work.** Uncommitted across three versions (1.1.0, 1.2.0, 1.3.0). `ChatScan.lua` is tracked-and-deleted, so use `git add -A`, not `git add .`. Decide whether `MEMORY.md` and `Tools/` ship in the published package; probably not: leave them out or add a `.pkgmeta` `ignore` entry.
2. **Run the in-game checklist** (section 10) and fold results into section 14. Waiting on beta access; miyanko's own task, not one to hand off.
3. **Install Classic Era** and test the 1.15 half.
4. **Add `.pkgmeta` and a release workflow.** The playbook has a worked example: BigWigs packager for the Vanilla build (`fetch-depth: 0` is mandatory or the changelog comes out empty) plus a separate zip step for 1.60, since there is no packager keyword or flavor id for Camelot. Do not invent one.
5. **Decide the lib update policy.** LibDBIcon r56 and friends are vendored and unmanaged; a `.pkgmeta` `externals` block would pull them at build time.
6. **Revisit the toc split** only if a client-specific file ever appears (section 3).

---

## 12. Cross-addon implications

The other addons in `_classic_beta_/Interface/AddOns` share this playbook and this client pair, so findings travel.

- **SuperSocial** guards `InChatMessagingLockdown` in its `Core/Compat.lua` and reached the same conclusion independently. **But** it also exposes `ns.CanAccess = canaccessvalue or ...`, and `canaccessvalue` carries the same `AllowedWhenUntainted` annotation as `issecretvalue`. If open question 2 resolves badly, that call site is latent-broken. Its harness convention (`Tools/harness.lua`, `lua Tools/harness.lua . vanilla|camelot`) is what `Tools/` here was modelled on, and its toc carries the same "one toc, here's why" comment block.
- **PlayerArmoryLink** and **TargetFinder** also call `canaccessvalue` on unit names (with nil screened out); same latent exposure.
- **SpeedyAutoLoot** registers `CHAT_MSG_*` with no lockdown guard. Third-party, not ours, but the addon most likely to throw on a locked-down realm: a useful canary.
- **TargetFinder, PlayerArmoryLink, TradeCountdownRemover, QuestieGuide** register no `CHAT_MSG_*` events and are unaffected by this issue.

---

## 13. If something breaks

| Symptom | Look at |
|---|---|
| Addon missing from the list | `ChatScan.toc` interface number vs `/dump select(4, GetBuildInfo())` |
| Error at login | `Bootstrap.lua` (15 lines), then `Core/Store.lua`. `/dump Constants.ChatFrameConstants` exists? |
| Scanning but never matching, no error | `/dump C_ChatInfo.InChatMessagingLockdown()`, open question 1 |
| Amber "Chat locked by client" | Working as designed; the client is withholding chat text |
| Error opening the panel | `UI/Panel.lua` `buildPanel`; the error names the failing call; `/framestack` over a half-built window shows how far it got |
| Panel opens but looks wrong | Layout constants in section 7; `/framestack` shows real sizes |
| Nothing forwarded | `/dump ChatScanDB["<Name>-<Realm>"]` against `/dump GetChannelList()` |
| Wrong tab receives lines | `/dump GetChatWindowInfo(1)` … `(10)`; `outputs` keys are lowercased tab names |
| Start button stays grey | `/framestack` over it, check for `Left`/`Middle`/`Right` regions |
| Raid markers not rendering | `/dump C_ChatInfo.ReplaceIconAndGroupExpressions("{skull}")` |

```
/console scriptErrors 1
/dump C_ChatInfo.InChatMessagingLockdown()
/dump select(4, GetBuildInfo())
/dump GetChannelList()
/dump ChatScanDB
/framestack
```

---

## 14. Test results

Empty. Fill in per step with date, build, character, zone and observed output.

---

## 15. Git state, committing and reverting

Working tree as of 2026-09-19 against HEAD `9814b43`: ` D ChatScan.lua` (became `Bootstrap.lua`), ` M ChatScan.toc`, ` M README.md`, `?? Bootstrap.lua Core/ UI/ Tools/ MEMORY.md`.

Commit: `git add -A && git commit`.

Revert to committed 1.0.0 (a single flat `ChatScan.lua`): `git checkout -- ChatScan.lua ChatScan.toc README.md && rm -rf Core UI Tools Bootstrap.lua MEMORY.md`. That also discards the uncommitted 1.1.0 and 1.2.0 work folded into this build: the `## Interface: 11509, 16001` line, the version bumps, the removed Murloc sound preset, the native `ButtonFrameTemplate` panel and every fix in section 6.
