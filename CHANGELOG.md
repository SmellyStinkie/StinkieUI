# Stinkie UI changelog

## 0.24.0
- Nameplates: stacking controls. Turn stacking on or off for enemies and friendlies, set the stacking box height (how far stacked plates climb), and, where the game still has them, vertical spacing, slide speed and distance from the screen top. /stinkie plates lists what this game version supports.

## 0.23.0
- Big Debuffs: crowd control and defensives / offensive cooldowns are now two rows, each placed left or right of the nameplate (default: defensives / offensives left, crowd control right). On the same side, crowd control sits next to the bar.

## 0.22.1
- Fixed: Blizzard Cooldown Manager rows didn't center when the bar is positioned by its left or right edge in Edit Mode (Blizzard shrinks the bar to the icons showing). Rows now center on the full bar as placed in Edit Mode.

## 0.22.0
- Target and focus frames: elite / boss star (gold; silver for rares), with size and corner options.
- Orb carrier icon redrawn as a Temple of Kotmogu style ball (soccer-ball panels, shading and shine), on nameplates and battleground frames.
- Flag / orb icons over nameplates sit just above the name instead of above the icon slot. New position choice (above name / left of bar / old spot) and X / Y offsets.
- Nameplate spec icons no longer have a border (it showed as an empty box when there was no icon).

## 0.21.1
- Fixed: pinging a Stinkie UI unit frame could leave the ping cursor stuck (you couldn't click anything until you pinged again). When the game hides the unit's identity from addons, the frame now declines the ping instead of breaking Blizzard's ping code.

## 0.21.0
- Arena Assist is now PvP Assist (your settings carry over).
- New Big Debuffs: crowd control (Fear, Mortal Coil, stuns...), major defensives and offensive cooldowns shown big to the right of enemy nameplates, with size, count, offset and glow options. By default they're no longer repeated in the small aura row.
- Action bars: the XP / honor bar (and the second status bar) can be set to show only on mouseover.
- Battlegrounds: Blizzard raid frames hide automatically in Blitz and battlegrounds up to 15 players (not in 40-player ones). Toggle on the Battleground Score page.
- Battlegrounds: out-of-range fading follows the game's range updates and re-checks 10 times a second (was 4).
- Combat logging: turns on once per instance and prints one message (was 3 or more).
- Nameplates: target arrow size up to 80.
- Fixed: an error while restyling aura icons in town after a match (icon width can be a hidden value).

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
