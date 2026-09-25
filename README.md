# ChatScan

Watches the chat channels you pick and forwards any message matching your keyword rules to the chat tabs you pick.

## Features

- Keyword rules with **OR** across rows and **AND** within a row, case-insensitive plain text
- Route matches to any chat tabs you choose; the receiving tab flashes if you are not looking at it
- Each forwarded line is stamped with its time and source channel
- Matches deduplicated for 10 seconds, so the same line never repeats
- Optional alert sound with preview, throttled to once every 3 seconds
- Raid-target markers like `{star}` and `{skull}` rendered as icons
- Minimap button (spyglass) and a full config panel
- Settings, scan state and button position saved per character; an active scan resumes after login or `/reload`

## Installation

1. Copy the `ChatScan/` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Chat Scan** in the AddOns list.

## Usage

Open the panel with `/cs` or the minimap button, then:

- **Scanned Channels** — tick the channels to watch. The list updates as you join and leave channels.
- **Keywords** — type a rule in the trailing empty row and press **+** or Enter. Commas inside a row require all of those words.
- **Channel Output** — pick the chat tabs that receive matches. With none picked, matches go to the default chat frame.
- **Sound Options** — turn the alert on, pick a sound, and **Test** it.
- **Control** — **Start** begins the scan; the button turns red and the status line shows the live match count.

| Rule | Matches |
| --- | --- |
| `wts thunderfury` | any message containing `wts thunderfury` |
| `lf, tank` | messages containing both `lf` and `tank` |
| `lf, tank` and `lf, heal` as two rows | `lf`+`tank` **or** `lf`+`heal` |

## Commands

| Command | Description |
| --- | --- |
| `/cs` | Toggle the scan panel |
| `/cs <keyword>` | Add a keyword (or `word1,word2` for an AND group) and start scanning |
| `/cs start` | Start scanning with saved settings |
| `/cs stop` | Stop the active scan |
| `/cs clear` | Empty the keyword list |

`/chatscan` works as an alias.

## Requirements

WoW Classic Era 1.15.x.
