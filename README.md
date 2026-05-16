# ChatScan

Keyword scanner for chat channels, with a minimap button and a native config panel, for WoW Classic 1.15.x.

## How it works

ChatScan watches the chat channels you choose and prints any message that matches your keyword rules into the chat tabs you choose. Matches are deduplicated for a few seconds so the same line doesn't repeat, and an optional alert sound plays on a match.

There are no slash commands — everything is driven from the panel. Click the minimap button to open it.

## Panel

The minimap button (spyglass icon) toggles the panel. The panel has four sections:

- **Channels** — checkboxes for every chat channel you are currently in. Pick which ones to scan.
- **Keywords** — one or more rows of keyword groups. Each row matches independently (OR). Inside a row, separate keywords with commas to require all of them (AND). Example: a row of `wts, dreamfoil` matches lines that contain both `wts` and `dreamfoil`.
- **Channel Match Display** — which chat tabs receive the matches. If none are picked, matches go to the default chat frame.
- **Options** — toggle the alert sound on or off.

**Save** stores your keywords without starting a scan. **Start** saves and starts scanning; while a scan is active the button turns red and reads **Stop**. The scan state is remembered per character and resumes after `/reload` or login.

## Minimap button

Left-click toggles the panel. Drag to reposition around the minimap. Position and hide state are stored via LibDBIcon, so any addon-manager UI that supports LDB can manage the button.
