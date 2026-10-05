# ChatScan

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no compat layer.
- `main` holds the Forever version. `1.15.x-backup` keeps the Classic version and stays untouched.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`.

## Rules

- Chat payload fields 1, 2, 5, 12, 13 and 18 are secret during chat lockdown. Filter by tick first, then check `C_ChatInfo.InChatMessagingLockdown()`, and only then read the text. Guild Discord goes through the same gate.
- `Core/Lines.lua` builds every forwarded line like Blizzard's `MessageFormatter` in `Mainline/ChatFrameOverrides.lua`, so tags, colours and links match Blizzard's own lines.
- The player's own lines are forwarded on purpose, for in-game testing.
- Left out on purpose: `CHAT_MSG_TEXT_EMOTE`, `CHAT_MSG_AFK`, `CHAT_MSG_DND`, voice channels, NPC and system chat.
- The UI is built from LibNativeUI-1.0: `UI.Font` roles, `UI.Space` and the 8 px grid. No local layout constants, no literal `|cff` codes.
- The window has a fixed 674x600 size and each well scrolls. Keep the minimap icon. No options page.

## Libraries

- `Libs/` holds tracked, unedited upstream copies. No `.pkgmeta` externals.
- ChatScan holds the reference copy of LibNativeUI-1.0, and every other addon carries a byte-identical copy. Change it only by raising `MINOR` and copying it to all of them. `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua` must print one hash.

## Checks

- Run `luac -p` on every Lua file after a change. The repo has no test harness.
- Turn on `/console scriptErrors 1` before testing in game.

## Release

1. Push `main` and tag `vX.Y.Z` with an annotated tag.
2. `.github/workflows/release.yml` packages it with the BigWigsMods packager.
3. Check that the zip holds all five libraries.
