# Stinkie UI changelog

## 0.33.0
- Fixed: "Auras cannot be accessed when secret while tainted by StinkieUI" (Edit Mode, scenario / Maw buffs) and gaps in the quest tracker after finishing a quest. Cause: the Objectives module ran Blizzard's tracker update itself and hid the tracker with Hide(), which made Blizzard's own tracker code run as Stinkie UI. It no longer calls the tracker's update code; hiding is now transparency only (it also works in combat now). New text sizes show on the tracker's next update.
- The "MovementSpeed_OnUpdate ... secret number" error in the character window came from 0.31's stat-list edit and was already fixed in 0.32.0.
- Nameplates: the healer cross never shows on classes that have no healing spec (hunters, mages, rogues, warlocks, warriors, death knights, demon hunters), whatever a role source says.
- Nameplates: important units (Grounding Totem, Psyfiend, ...) are bigger (width and height sliders, up to 3x / 4x a normal plate) with a border in the important color, and a plate is checked again when its name arrives (fresh totems often get their name a moment later, so they were missed).
- Nameplates: a friendly player you target gets the full-size plate and the target border (option).
- Nameplates: friendly flag carriers in battlegrounds and Blitz show the flag (their carry aura) where enemy carriers show the carrier icon.
- Battleground frames: teammates show their flag / orb carry aura. Temple of Kotmogu: one orb with the stack count on it, instead of an orb next to an orb debuff.
- Flag Cap Indicator: only in Warsong Gulch and Twin Peaks (no more NOT ON CAP in Temple of Kotmogu).
- Queue Time & MMR: four equal columns (bracket, time, estimate, MMR). N/A for unrated queues and for a bracket whose saved match came without an MMR; "MMR unknown" until you play a match there. Default width 440.
- Match History: rated matches wait up to ~8 seconds for the game to fill in rating and MMR changes before saving, so wins and losses no longer save as +0. An MMR of 0 from the game is saved as "no MMR".
- Match History: the search box also narrows Match Stats groups (search a player while grouped by teammate or opponent to get that player's row). New grouping: Map + faction (battlegrounds). Delete match and Delete all are removed.
- Options: a search box at the top of the menu finds any page or option and jumps to it.
- Arena frames: big DEAD across a dead enemy's frame, and FEIGN for Feign Death when the game reports it (size option).
- Arena / Solo Shuffle info (round 3 of 6, timer): its own position and size, and the Stinkie UI font and text size (BG Score page).
- Party frames: your own frame only shows while you're in a group. Party members out of sight (another zone, far away) no longer show odd buffs like Enlisted; their icons come back when they're near.
- Action bars: the vehicle / taxi exit button stays visible when Action Bar 1 is faded.

## 0.32.0
- Fixed: in Solo Shuffle and Blitz the character window broke (no stats, titles or equipment sets, gear couldn't be changed). Almost certainly caused by Stinkie UI editing Blizzard's stat list to show stats at 0: that tainted it, and in rated PvP the game's hidden stat values then made Blizzard's own code fail. Stinkie UI no longer touches that list; stats at 0 and movement speed are now its own rows under Blizzard's list, and are skipped in rated PvP where the numbers are hidden.
- Match History: queue time for every new match, counting only the time you spent waiting outside other matches (a Blitz queue that runs on while you play a Shuffle doesn't count that Shuffle). New Queue column in the match list, Avg queue in Match Stats, and the average in the summary. Imported Rated Tracker matches keep their queue times.
- Queue Time & MMR: the spec icon you're queued as on each queue, a "Queued as" line on top (both optional), and hidden while you're in an arena or battleground (optional). Solo Shuffle and Blitz MMR come from the spec you queued as. No match yet in a bracket or spec: "MMR unknown, play a game". Default width 360 (was 300).
- Character Sheet: hovering a stat also highlights that stat's row. Equip and Save buttons and the three side tabs (stats, titles, equipment sets) are flat in Stinkie UI's style.
- New Buff Frame page (Miscellaneous): Blizzard's buff and debuff icons get zoomed icons, a 1px border and your fonts for duration and stack count. Auto hide in arenas and battlegrounds (on by default), dungeons, raids, in combat or always; debuffs only if you choose; mouse over the spot to see them. Layout stays in Edit Mode.
- Arena frames: the border on your target is thicker (3 px, outside the frame) with thickness and color options.
- Removed the personal DR timers from PvP Assist.

## 0.31.0
- New Window Mover (Miscellaneous), replacing BlizzMove: drag Blizzard's windows by any empty part of them, Ctrl + mouse wheel over a window to make it bigger or smaller. Positions and sizes are remembered across sessions (or just until logout) and put back whenever the window opens or Blizzard re-arranges its side panels. Alt + right-click resets one window; a button resets them all. Optional key to hold while dragging; add any other window by name. Windows Blizzard protects (spellbook, map) only move out of combat. It switches itself off while BlizzMove is enabled, since both would fight over the same windows: disable BlizzMove to use it.
- The character and inspect window sizes are the same setting in Window Mover and on the Character Sheet page.

## 0.30.0
- Match History window: drag the bottom-right corner to resize it; its size and position are remembered.
- Queue Time & MMR: shows how much your last game changed your MMR (+73 in green, -40 in red). Solo Shuffle and Blitz use your current spec's last game.
- Character Sheet: roomier layout. The window and character area are wider and taller, with more space between item slots and between the weapons (adjustable, or off). Item text is wider to match.
- Character Sheet: gems and empty sockets sit beside each icon on the outside (above the weapons) instead of in the text.
- Character Sheet: window size is re-applied every time the window opens, so a resize sticks. Default window opacity is 55% (profiles still on 95% move to 55%).

## 0.29.0
- Match Stats: click any column heading to sort by it; click again to reverse. (Replaces the Sort dropdown.)
- Match Stats: new groupings, Opponent (every enemy you've faced, like Teammate) and Faction (the side you fought on in Blitz and battlegrounds; arenas have no sides).
- Match History: a "my spec" filter in the top bar, so e.g. grouping by map shows how one spec does on each map.
- Match History: skirmishes, brawls and unrated games (battlegrounds, Solo Shuffle, Blitz) are no longer saved. Each can be turned back on. Matches already saved stay.
- Character Sheet: item level and PvP item level are on the same line as the upgrade track.

## 0.28.1
- Fixed: the character window's item details stopped after the first slot ("CharacterSheet.lua:291: attempt to call a nil value").
- Character Sheet: every secondary and tertiary stat (crit, haste, mastery, versatility, leech, avoidance, speed) now shows even at 0, plus a movement speed row. Option to hide the ones you have none of (Blizzard's default).
- Character Sheet: PvP item level only appears on items (and in the overall line) when it differs from the normal item level. Item levels refresh on their own when they change, including entering and leaving PvP.

## 0.28.0
- Character Sheet: flat look for the character and inspect windows. Blizzard's frame art, portrait, marble background, slot frames and stat-pane gradients are gone; flat window and tabs with 1px borders, zoomed item icons with a border in the item's quality color, thin accent lines under the stat headings. Both windows are bigger by default (120%) and can be resized with a slider or by dragging the bottom-right corner.
- Objectives: flat headers (thin accent line instead of the gradient), flat progress bars with a 1px border, quest item buttons with zoomed icons. The background now defaults to 0% opacity (profiles still on 0.27's 50% are moved to 0%).
- Fixed: the Rated Tracker import stopped partway with "integer overflow attempting to store 4294967295". Values Rated Tracker saved as "unknown" (4294967295) are now treated as missing, very large numbers are saved safely, and a match that can't be converted is skipped instead of stopping the import. Run the import again: matches already brought in are skipped.

## 0.27.0
- New Flag Cap Indicator (BG Score page): Warsong Gulch and Twin Peaks show each flag that's out under the score: the carrier, yards to their cap spot, and ON CAP (flashing) / NOT ON CAP / DROPPED, plus seconds until they reach the cap. Size, width, layout, colors, fonts and position are all adjustable; it can also be moved anywhere. Cap spots are learned from where each flag is picked up and remembered per map.
- New BG Timers page: bars for assaulted bases, the predicted winner and final score, and your next resurrection while dead. Each kind can be turned off. Base capture times are set per map (Arathi Basin, Battle for Gilneas and Deepwind Gorge at 60 s to start).
- New Match History (/mh): every arena, Solo Shuffle, Blitz, rated BG, skirmish, battleground and brawl is saved when it ends, with rating and MMR before and after, comps, talents and every player's full scoreboard line. Browse and filter matches, open any match's scoreboard, and see Match Stats: win rates with a 95% range by map, comp, spec, teammate, hero talents, MMR, length, time of day and weekday, plus rating trend, streaks and CSV export. The window is its own addon (StinkieUI_History) that only loads when opened.
- Match History: import your Rated Tracker history (Match History page, the /mh window, or /mh import). Rated Tracker has to be enabled for that session; its files aren't changed and matches already saved are skipped. Imported matches show what Rated Tracker didn't record (hero talents, PvP talents, item level) as "not recorded", and keep its queue times and Solo Shuffle round details (teammates and first death per round). Single Shuffle rounds it had filed as 2v2 / 3v3 games get their own "Shuffle rounds (imported)" bracket.
- New Queue Time & MMR (Match History group): while you're queued, each queue's bracket, time waited, Blizzard's estimated wait and your MMR (and optionally rating) in that bracket. Movable, resizable, optional background and border. MMR is from your last match in that bracket on that character, since the game only reveals MMR at the end of a match.
- New Character Sheet page: beside each item on your character window (and when inspecting others) its name or upgrade track ("Mythic 6/6" in the track's color), item level, PvP item level for gear that scales in PvP, gem icons (empty sockets too), and the enchant, or "Enchant Missing" in red on helm, shoulders, chest, legs, boots, rings and weapons. Backgrounds: any warband camp, flat dark, Blizzard's, or any texture / atlas, with adjustable darkening. Hovering a secondary or tertiary stat highlights the items that have it. Item level to two decimals, with overall and PvP.
- New Objectives page (Miscellaneous): font sizes and outline for the quest / objective tracker, scale, a flat background with opacity (Blizzard's off), and hiding it in arenas, battlegrounds, raids, Mythic+ or other dungeons.
- New Party Targets frames (Unit Frames > Party Targets, off by default). Blank in arenas and battlegrounds, where Blizzard blocks party targets, so hidden there by default.
- Default settings updated to Stinkie's setup: Flag Cap Indicator side by side, 229 x 40, larger text, green ON CAP / red NOT ON CAP, yards instead of NOT ON CAP; BG Timers 270 x 26 with bigger text. Existing profiles are unchanged.
- Options reorganized: Unit Frames is one group (Player, Target, Target of Target, Focus, Pet, Party, Party Targets), Miscellaneous holds GCD History & Decor, Minimap, Damage Meter and Objectives, Match History holds History & Import and Queue Time & MMR, and pages are renamed Arena Frames, Battleground Frames and Combat Indicator. The "hide Blizzard raid frames" option moved to Battleground Frames.

## 0.26.1
- Default settings updated to Stinkie's current setup: bigger Big Debuffs (60 px, 3 crowd control icons), Howl of Terror added to DR timers, XP / honor bars on mouseover, wider nameplates (210) with larger target arrows and healer crosses, nameplate stacking tuned (spacing 0.6, slide speed 0.05), battleground frames lower with softer out-of-range fading, larger chat text (19), Command Demon on cooldown bar 1. Existing profiles are unchanged.

## 0.26.0
- PvP Assist: DR timers for your own crowd control (Fear by default; add Mortal Coil or others by spell ID and DR category). When your CC lands, the enemy's nameplate and a movable list show the DR window counting down, marked 50% (next one is half length) or IMM (immune). The game hides real DR in Midnight, so this is an estimate from your casts: 20 s reset after the CC (patch 12.1), assuming it ran its full length.

## 0.25.1
- Custom cooldown bars: spells that change into another spell (Command Demon and other overrides) now show the current spell's icon and cooldown, including pet abilities, which report their cooldowns through the pet bar. Updates when you summon a different demon.

## 0.25.0
- Party crowd control icons and the Healer in CC warning glow bright blue (pulsing) when the crowd control is a Magic debuff, i.e. one Singe Magic or another magic dispel can remove. Works in arena: the game itself picks the glow per dispel type. Toggle on the PvP Assist page (/reload to apply).

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
