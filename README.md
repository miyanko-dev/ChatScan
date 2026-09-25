# Chat Scan

Watches the chat channels you pick and forwards any message matching your keyword rules to the chat tabs you pick.

## Features

- Keyword rules with **OR** across rows and **AND** within a row, case-insensitive plain text
- Route matches to any chat tabs you choose; the receiving tab flashes if you are not looking at it
- Each forwarded line is stamped with its time and source channel
- Click the sender's name to whisper, right-click for the usual player menu
- Matches deduplicated for 10 seconds, so the same line never repeats
- Optional alert sound with preview, throttled to once every 3 seconds
- Raid-target markers like `{star}` and `{skull}` rendered as icons, exactly as the game's own chat does
- Zone channels such as General and Trade stay selected when you change zones
- Minimap button (spyglass) and a native config panel
- Settings, scan state and button position saved per character; an active scan resumes after login or `/reload`

## Installation

1. Copy the `ChatScan/` folder into the `Interface/AddOns/` folder of your WoW Forever installation.
2. Restart the game or `/reload`.
3. Enable **Chat Scan** in the AddOns list.

## Usage

Open the panel with `/cs` or the minimap button, then:

- **Scanned Channels**: tick the channels to watch. The list updates as you join and leave channels.
- **Keywords**: type a rule in the trailing empty row and press **Add** or Enter. Commas inside a row require all of those words. Press the **X** to remove a rule.
- **Output Tabs**: pick the chat tabs that receive matches. With none picked, matches go to the default chat frame.
- **Alert Sound**: turn the alert on, pick a sound, and **Test** it.
- **Start**: begins the scan. The button turns red and reads **Stop**, and the status line shows the live match count.

Channel, tab and sound changes apply to a running scan straight away. Escape or the corner X closes the panel; drag it anywhere.

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

## Chat lockdown

WoW Forever can withhold chat text from addons in some situations (chat messaging lockdown). While it does, Chat Scan pauses matching, says so once in chat, and shows **Chat locked by client** in the panel and the minimap tooltip. Matching resumes by itself when the text is readable again.

## Requirements

WoW Forever 1.60.x.
