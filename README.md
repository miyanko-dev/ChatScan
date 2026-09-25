# ChatScan

Keyword scanner for chat channels, with a native config panel and a minimap button, for WoW Classic Era 1.15.x and WoW Forever 1.60.x.

## How it works

ChatScan watches the chat channels you pick and forwards any message that matches your keyword rules to the chat tabs you pick. Each forwarded line is stamped with the time and the channel it came from, and the receiving tab flashes if it isn't the one you're looking at. Matches are deduplicated for 10 seconds so the same line doesn't repeat, and an optional alert sound plays on a match (throttled to once every 3 seconds).

Settings, scan state, and the minimap button position are saved per character; an active scan resumes after `/reload` or login. Zone channels such as General or Trade stay selected when you change zones.

## Slash commands

| Command | Description |
|---|---|
| `/cs` | Toggle the scan panel |
| `/cs <keyword>` | Add a keyword (or `word1,word2` for an AND group) and start scanning |
| `/cs start` | Start scanning with saved settings |
| `/cs stop` | Stop the active scan |
| `/cs clear` | Empty the keyword list |

`/chatscan` is accepted as an alias.

## Panel

The panel is a standard game window (the same frame Blizzard uses for the Channels and Friends windows) with two inset columns and a button bar:

- **Scanned Channels** — checkboxes for every chat channel you are currently in. The list updates by itself as you join or leave channels.
- **Keywords** — one or more rows of keyword groups. Each row matches independently (**OR**). Inside a row, separate keywords with commas to require all of them (**AND**). Matching is case-insensitive and uses plain text — no Lua patterns. Type in the trailing empty row and press Enter or **Add** to save a rule; press the **X** to remove one.
- **Output Tabs** — which chat tabs receive the matches. If none are picked, matches go to the default chat frame.
- **Alert Sound** — turn the alert sound on or off, pick a named sound from the dropdown (choosing one previews it), and use **Test** to hear it again.
- **Button bar** — the live status on the left and **Start** on the right. While a scan is active the button turns red and reads **Stop**.

Everything saves as you change it, and channel, tab, and sound changes apply to a running scan immediately — you don't need to stop and start again. The corner X or Escape closes the panel; drag anywhere on the frame to move it.

Examples:
- Row `wts thunderfury` → matches any message containing `wts thunderfury`.
- Row `lf, tank` → matches messages containing both `lf` and `tank` anywhere.
- Two rows `lf, tank` and `lf, heal` → matches `lf`+`tank` OR `lf`+`heal`.

Raid-target markers like `{star}`, `{skull}`, `{circle}` are rendered as icons in the forwarded line, using the game's own expression renderer. Clicking a sender's name opens a whisper, and right-clicking it opens the usual player menu.

## Minimap button

The spyglass icon left-click toggles the panel. Drag to reposition around the minimap. Position and hide state are stored via LibDBIcon, so any addon-manager UI that supports LDB can manage the button.

## Files

ChatScan is one codebase serving two game versions. `Core/` is version-neutral, `UI/` holds the
frames, and `Core/Compat.lua` is the only file allowed to branch on what an API does.

| File | Role |
|---|---|
| `Core/Init.lua` | Namespace, constants and pure helpers. Touches no Blizzard API at load time |
| `Core/Compat.lua` | Every version-sensitive API, behind a feature test. The only place a guard belongs |
| `Core/Store.lua` | Per-character saved variables and upgrade migrations |
| `Core/Scanner.lua` | Keyword matching, dedup, forwarding, scan state |
| `Core/Commands.lua` | Slash commands |
| `UI/Panel.lua` | The config window |
| `UI/MinimapButton.lua` | LibDBIcon launcher |
| `Bootstrap.lua` | Login bootstrap, loads last |

## Game version support

One `ChatScan.toc` serves both clients through `## Interface: 11509, 16001`, because the two load
an identical file set. If a future change makes the UI genuinely diverge, add `ChatScan_Vanilla.toc`
listing the 1.15.x file set and let `ChatScan.toc` stay the fallback the 1.60 client picks up.

`Core/Compat.lua` covers the differences that exist today:

| Difference | Handling |
|---|---|
| Chat messaging lockdown (1.60 only) | `C_ChatInfo.InChatMessagingLockdown()` gates the chat handler. Under lockdown the message text and sender arrive as secret values, and any string operation on one aborts the handler, so ChatScan skips the message and says so once rather than failing silently |
| `NUM_CHAT_WINDOWS` deprecation | Reads `Constants.ChatFrameConstants.MaxChatWindows` first, falls back to the global, then to 10 |
| Sound presets | Resolved from `SOUNDKIT` on first use; a missing key drops its preset instead of storing a nil id |
| Addon metadata | `C_AddOns.GetAddOnMetadata` with a fallback to the old global |
| Raid target markers | `C_ChatInfo.ReplaceIconAndGroupExpressions`, so `{skull}` renders exactly as it does in Blizzard's chat, localised names included |
