# ChatScan

Keyword scanner for chat channels, with a native config panel and a minimap button, for WoW Classic 1.15.x.

## How it works

ChatScan watches the chat channels you pick and forwards any message that matches your keyword rules to the chat tabs you pick. Matches are deduplicated for 10 seconds so the same line doesn't repeat, and an optional alert sound plays on a match (throttled to once every 3 seconds).

Settings, scan state, and the minimap button position are saved per character; an active scan resumes after `/reload` or login.

## Slash commands

| Command | Description |
|---|---|
| `/cs` | Toggle the scan panel |
| `/cs start` | Start scanning with saved settings |
| `/cs stop` | Stop the active scan |

`/chatscan` is accepted as an alias.

## Panel

The panel has four sections:

- **Channels** — checkboxes for every chat channel you are currently in. Pick which ones to scan.
- **Keywords** — one or more rows of keyword groups. Each row matches independently (**OR**). Inside a row, separate keywords with commas to require all of them (**AND**). Matching is case-insensitive and uses plain text — no Lua patterns.
- **Channel Match Display** — which chat tabs receive the matches. If none are picked, matches go to the default chat frame.
- **Options** — toggle the alert sound on or off.

**Save** stores your keywords without starting a scan. **Start** saves and starts scanning; while a scan is active the button turns red and reads **Stop**.

Examples:
- Row `wts thunderfury` → matches any message containing `wts thunderfury`.
- Row `lf, tank` → matches messages containing both `lf` and `tank` anywhere.
- Two rows `lf, tank` and `lf, heal` → matches `lf`+`tank` OR `lf`+`heal`.

Raid-target markers like `{star}`, `{skull}`, `{circle}` are rendered as icons in the forwarded line.

## Minimap button

The spyglass icon left-click toggles the panel. Drag to reposition around the minimap. Position and hide state are stored via LibDBIcon, so any addon-manager UI that supports LDB can manage the button.
