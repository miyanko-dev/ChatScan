# ChatScan

Keyword scanner for chat channels, with a native config panel and a minimap button, for WoW Classic 1.15.x.

## How it works

ChatScan watches the chat channels you pick and forwards any message that matches your keyword rules to the chat tabs you pick. Each forwarded line is stamped with the time and the channel it came from, and the receiving tab flashes if it isn't the one you're looking at. Matches are deduplicated for 10 seconds so the same line doesn't repeat, and an optional alert sound plays on a match (throttled to once every 3 seconds).

Settings, scan state, and the minimap button position are saved per character; an active scan resumes after `/reload` or login.

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

The panel has five boxed sections in two columns (inputs on the left, outputs on the right, Control full width below), each a bordered group with a floating yellow label and a grey helper line (the same layout QuestieGuide and GatherMate2NodeAlert use):

- **Scanned Channels** — checkboxes for every chat channel you are currently in. Pick which ones to scan. The list updates by itself as you join or leave channels.
- **Keywords** — one or more rows of keyword groups. Each row matches independently (**OR**). Inside a row, separate keywords with commas to require all of them (**AND**). Matching is case-insensitive and uses plain text — no Lua patterns. Type in the trailing empty row and press the round **+** button (or Enter) to save a rule; press the **X** to remove one.
- **Channel Output** — which chat tabs receive the matches. If none are picked, matches go to the default chat frame.
- **Sound Options** — turn the alert sound on or off, pick a named sound from the list (choosing one previews it), and use **Test** to hear it again.
- **Control** — the **Start** button and the live status line.

Keywords save automatically as you add or remove them. **Start** begins scanning; while a scan is active the button turns red and reads **Stop**, and the status line on its left shows the live match count. The corner X or Escape closes the panel.

Examples:
- Row `wts thunderfury` → matches any message containing `wts thunderfury`.
- Row `lf, tank` → matches messages containing both `lf` and `tank` anywhere.
- Two rows `lf, tank` and `lf, heal` → matches `lf`+`tank` OR `lf`+`heal`.

Raid-target markers like `{star}`, `{skull}`, `{circle}` are rendered as icons in the forwarded line.

## Minimap button

The spyglass icon left-click toggles the panel. Drag to reposition around the minimap. Position and hide state are stored via LibDBIcon, so any addon-manager UI that supports LDB can manage the button.
