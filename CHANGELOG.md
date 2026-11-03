# Stinkie UI changelog

## 0.20.2
- Fixed: after a /reload inside an arena or Solo Shuffle, party frames vanished and Precognition / enemy kick tracking stopped for the rest of the match. Blizzard locks aura icons against addons while auras are secret; Stinkie UI now styles icons fully when they're created and saves any later restyle until the match ends.
- Fixed: font refreshes no longer error on aura icon text during matches.
- Nameplates: a plate whose unit changes sides (Solo Shuffle rounds, arena gates) is set up again, so enemy plates get their auras and castbar.
- New: /stinkie auras prints how your target's nameplate aura icons are set up.

## 0.20.1
- Default settings updated to Stinkie's current setup, now including chat (17 px text, no brackets, "From" whispers, whispers in their own tab, 12-hour timestamps), GCD History on, decor auto-confirm on, larger cooldown numbers, and slightly bigger battleground titles. Existing profiles are unchanged.

## 0.20.0
- New Chat page: flat chat windows and tabs, font / size / outline / spacing, messages kept across reloads and into your next login, copy window, timestamps (HH:MM or HH:MM:SS, in the line or in their own column), short channel names, no brackets, no realm names, sender levels, class colors, colors per chat type and channel, whispers in their own tab, flashing tabs, hide until mouseover.
- New Miscellaneous page: GCD History and Auto-Confirm Decor Purchases.
- Action bars: show or hide cooldown numbers, and set their size.

## 0.19.3
- CurseForge and Wago project IDs added for automatic uploads.

## 0.19.2
- Default layout is now Stinkie's own setup (sizes, positions, fonts, glows). Existing profiles are unchanged.
- Enemy kick timers use a rewritten interrupt table: Shadow Silence 30 s and Counterspell 24 s.
- YouTube link on the General page.
- Battleground title size: one setting (Horde / Alliance title).

## 0.19.1
- Countdown text size for Arena Assist and party CC / trinket icons.
- Nameplate name length moved to its own section.

## 0.19.0
- Party test mode: in range, looping casts. Trinket side option. Debuffs toggle keeps crowd control.
- WoW Forever support.
