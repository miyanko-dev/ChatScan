# ChatScan — Memory

Updated 2026-09-25 after the dual-client port with native UI (decision: every addon in the folder supports both clients, with each client's own look). Verified against Gethe `forever` @ `bd2470a` (1.60.1.70009), Gethe `classic_era` @ `33e177d` (1.15.9.69722) and the matching Ketho dumps. Nothing has run in a client.

## Current state

Scans chat channels for keyword groups (OR across rows, AND within a row) and forwards matches to chosen chat tabs with a sound. Open it with `/cs`, the minimap button, or the Addon Compartment on Forever.

| Item | State |
|---|---|
| Version | 2.1.0, both clients from one toc, `## Interface: 11509, 16001`, plus the `AddonCompartmentFunc*` fields |
| Author | `miyanko` |
| Git | Committed and pushed on 2026-09-25: `main` = `origin/main`. `1.15.x-backup` = `9184981` (vanilla 1.0.0) is pushed too |
| Libraries | LibStub, CallbackHandler, LibDataBroker and LibDBIcon. `Libs/` is gitignored and fetched from `.pkgmeta` externals; a fresh clone has no `Libs/` |

Behaviour:

- There's no Lua client branch. Every API exists on both clients.
- The `CHAT_MSG_CHANNEL` payload is identical on both; Forever only appends `discordInfo`.
- On 1.60 that event is `SecretInChatMessagingLockdown`. ChatScan filters by the `NeverSecret` channel fields first, then checks `C_ChatInfo.InChatMessagingLockdown()`, which exists on both and is false on Era, and only then matches.
- A match line shows the sender the way Blizzard's chat does (`Ambiguate(sender, "none")`). The link keeps the full name.

Native UI:

- `ButtonFrameTemplate` and `InsetFrameTemplate`, with each client's own art.
- `UI/Design.lua` now holds only Blizzard font objects (`GameFontNormal`, `GameFontHighlight`, `GameFontDisableSmall`) and Blizzard's `PANEL_INSET_*` offsets.
- `WowStyle1DropdownTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButtonNoScripts` and `InputBoxTemplate`.

## Blockers, issues, challenges

1. When chat messaging lockdown is active on Forever isn't in the source. If it covers normal open-world play, ChatScan can't work there.
2. `PlaySound(id)` is called without a channel, so the alert follows the SFX toggle.
3. Unverified: could `UnitName("player")` ever be secret at login? That would break `Store.Init`.
4. The panel grows with its content and doesn't scroll. It fits unless there are very many channels and keywords.
5. The red tint on the Stop button isn't Blizzard styling. It's kept because the README documents it.
6. Nothing has been packaged end to end (bash 3.2, no svn). There's no `_classic_era_` install, and the installed beta is 69913 against source 70009.

## Next steps

1. Tag `v2.1.0` when releasing and check the zip has all four libs and no `MEMORY.md`.
2. Run `/console scriptErrors 1` first.

Both clients:

- [ ] `/cs` opens the panel with the portrait and the version in the title. Escape closes it, and it drags.
- [ ] Tick Trade and Loot, add `wts`, press Start. A second character posts `WTS {skull} Thunderfury`. One line lands in Loot with time, channel, a clickable sender and the icon. The tab flashes and one sound plays.
- [ ] Shift-click and right-click the sender. A repeat within 10 s is hidden.
- [ ] The sound dropdown previews each sound, and Test replays it.
- [ ] `/reload` resumes the scan. `/cs stop` then `/reload` doesn't. `/cs <kw>`, `start`, `stop` and `clear` all work.

Era:

- [ ] The panel shows the classic frame art, the classic dropdown and the 32px remove buttons.

Forever:

- [ ] The panel shows Mainline art. The Addon Compartment lists Chat Scan: click toggles, hover shows the tooltip.
- [ ] Check `/dump C_ChatInfo.InChatMessagingLockdown()` in the open world, a dungeon, a battleground and in combat. This settles issue 1.
- [ ] Mute SFX with Master on and record whether the alert plays.
