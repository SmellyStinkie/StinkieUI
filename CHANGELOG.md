# Stinkie UI changelog

## 0.39.1
- Quest marker: the off-screen arrow now sits near the edge of the screen, with a slider for the gap.
- Quest marker: hides while you're inside the quest's area with objectives left, and comes back to point at the turn-in once the quest is done.
- Fixed: on WoW Forever, the side tabs in Collections (Mounts, Pets, Toys, Heirlooms, Wardrobe) lost their icons with the flat skin, and the selected tab now shows.

## 0.39.0
- New Quest marker (Objectives page, off until you turn it on): a small nameplate in the world on the quest you're actively tracking, with the quest name and distance in yards, in place of Blizzard's diamond. It shows at long range, shrinks with distance and becomes an arrow at the edge of the screen when the spot is off screen. Works for quests ready to turn in. Height above the spot, arrow size, color and text options.
- All unit frames (player, target, target of target, focus, pet, party, party targets, arena): choose whether names show first, last or both, and an option to show level. Nameplates get the same name choice.
- Target markers: show above nameplates (on by default, with a size option), and optionally on party frames.
- New swing timer look (Castbars page): flat melee, off-hand and ranged bars on WoW Forever, with colors and text options, and an option to show them only while you're attacking. Size and position stay in Edit Mode.
- Battleground frames: option to show buffs beside each ally, or only the buffs you cast.
- Miscellaneous: new options to accept and turn in quests, repair, sell junk and release in battlegrounds, all off by default. Hold Shift at an NPC to do quests yourself; reward choices and quests that cost gold, currency or flag you for PvP stay with you.
- Miscellaneous: option to hide red error messages like Not enough mana, and their voice lines.
- Action bars: Lock buttons option, and with keybinds off they can show on the bar under your mouse.
- Damage Numbers: a Show your healing numbers option. `/stinkie dmg` also reports the font the game is using.
- New `/rl` reloads the UI. New `/stinkie quest` reports what the Quest marker can see.
- Fixed: Character Sheet window opacity did nothing with the whole-window background.
- Fixed: hiding or showing action bars on mouseover now stays changed after a reload for bars the default layout hides.
- Fixed: with Include me on, Party Targets showed your own target while you were solo.

## 0.38.0
- Performance:
  - Cursor ring: only moves when the mouse moves (it was re-placed every frame), and shows only in combat by default.
  - GCD History: stops running when no icons are on screen (it ran every frame), and is off by default for new profiles.
  - Action bar fade: does nothing when no bar is set to mouseover. Chat tab fading / flashing runs 5 times a second instead of 10. Minimap button fading only runs in mouseover mode.
  - New `/stinkie cpu`: measures Stinkie UI for 30 seconds and prints which parts use the most (events, nameplates, unit frames, castbars, timers), plus the game's own figure.
  - Your existing settings don't change; turn the cursor ring to combat-only (Cursor page) and GCD History off (GCD History & Decor page) to get the savings there.
- Match History loads the last 12 months by default (setting: 0-60 months, 0 = everything). Older matches stay saved; a Load all button in the window brings them in for that session. With a big Rated Tracker import this keeps the window's memory down.
- New Window Skins page (Miscellaneous): the flat look on Friends / Social, Group Finder and PvP, Adventure Guide, Warband Collections, Achievements, Guild and Communities, Professions, Housing Dashboard, and the Game Menu background. Each window is restyled once when it first opens. Bags, talents / spellbook and the map are left alone.
  - Title bars: a slightly darker band with a thin accent line, and the window name in the Stinkie UI font centered on the window (Blizzard left room for the portrait, so titles sat off center). Achievements: a centered two-line title bar (the name, with your points and shield under it) instead of the old banner; on the Statistics tab it says Statistics. Game Menu: flat header.
- Party frames hide while you're in a raid group (option, on by default).
- New Damage Numbers page (Miscellaneous): the Stinkie UI font for the damage and healing numbers over targets (moved here from General; needs a relog), plus height above the target, size, sideways scatter, fall speed and sideways flight, through the game's own settings. Options the game version doesn't have say so; /stinkie dmg lists them.
- Character Sheet: a thin durability line beside each item with durability: green when repaired, yellow at half, red when broken (width option).
- Damage Numbers: drives Midnight's renamed settings (the "_v2" ones, e.g. WorldTextScale_v2). Height now uses the setting that measures from the target's nameplate (WorldTextScreenY_v2, default 0.015 of the screen height); the old world-height setting didn't visibly move the numbers and is put back to its default. New Critical hits section: crit height and crit pop size. /stinkie dmg also lists every world-text setting the game has, with its value.
- Dropdowns (Match History, Match Stats and the options) close when you click anywhere else, or click the dropdown again.
- `/st` opens Stinkie UI too (same as `/stinkie`); `/st m` and `/st mh` open Match History.
- Match History: battleground and Blitz matches save the final score (Alliance - Horde, read from the score bar when the match ends) and show it on the match's page. Matches recorded before this have no score. `/stinkie score` prints what the score bar holds, for maps it reads wrong.
- Match History: MMR shows N/A when the game gave none (0 or missing), in the list, on the match's page and in the player table.
- Match Stats: the Net rating column is gone; the per-game column is now called Rating/game.
- Match History no longer records your item level, and the match page no longer shows it.

## 0.37.2
- Removes the leftover PvPDR.lua (unused since 0.32; it was still shipping in the zip). No changes in game.

## 0.37.1
- Nameplates: stacking is off by default for enemies and friendlies (plates no longer push each other apart); existing profiles are switched off once. Turn it back on under Nameplates.
- Match History: the list fills the window (22 rows, no empty space at the bottom), and the scroll bar works with the mouse: click anywhere on it to jump, or drag.
- Match History search: every word you type must match (e.g. "pinkie nagrand"), and it now also matches specs and classes ("frost", "mage"), the bracket ("shuffle"), the result ("win", "loss") and the character, as well as maps and player names.
- Match History: the Import Rated Tracker button is gone from the window; it's on the options page (Match History > History & Import).
- Options: the search box at the top of the menu has a visible outline and "Search all options..." hint; a page that fails to build no longer stops the search.

## 0.37.0
- New default layout from Stinkie's current settings: character sheet (warband camp background, 144% size, darker character area, longer item names), queue display (bigger, no "Queued as" line), objectives (bigger text, also hidden in dungeons), buff frame (also hidden in dungeons and raids), party targets on, flag cap bars, Return to Graveyard spot and more. Only new profiles start from it; your saved settings don't change. Window positions remembered by Window Mover aren't part of it.
- WoW Forever: no red "missing enchant" cross on the character sheet (Forever's enchantable slots aren't known yet; enchanted items still get the check). Forever is now also recognized by its interface number if the game's project constants are missing.
- Stinkie UI is built for Midnight and WoW Forever from one build going forward.
- Character Sheet: your name and "Level 90 ..." are centered over the character again (the window is wider than Blizzard's, so they had drifted off center).
- Character Sheet: a small arrow under the trinkets hides or shows the right side (stats, titles, equipment sets); the window gets narrower while it's hidden, and it remembers.
- Character Sheet: no more dark vertical bars beside the item columns. With the background across the window, only the name band at the top and the stat sheet get the darker shade; the item columns share the character's lighter one.

## 0.36.0
- New Tooltip page (Miscellaneous):
  - Size slider.
  - Position: at the mouse (default, offset +128 / +25, both adjustable), at a fixed spot you drag when unlocked, or Blizzard's own spot.
  - Combat: show, hide unit tooltips, or hide all; hold Shift to see them anyway.
  - Health bar on or off.
  - The unit's target: "Target: Name" in class color, or YOU in red when it's targeting you.
  - Guild rank after the guild name, separately for your guild (shown in green) and other guilds.
  - Player names in class color.
  - Spell and item IDs (off by default; handy for the spell ID lists in Stinkie UI).
  - Rated PvP hides names and classes from addons; the target line and colors are left out there.
- Character Sheet:
  - Back to "PvP 344" (compact kept everything else).
  - Window opacity 90% by default (profiles on 55% move up).
  - The chosen background now fills the whole window, not just the character: the name bar, item columns and stat sheet show it too, under a darker shade (adjustable) so text stays readable. The character area keeps its own lighter shade.
  - The window reaches further left so the gems beside the left item column sit inside it.

## 0.35.0
- Character Sheet, compact (on by default, one checkbox to go back):
  - Item names drop the set / season prefix that every piece shares ("Venomous Gladiator's Amulet" -> "Amulet", "Thalassian Competitor's Plate Sabatons" -> "Plate Sabatons") and are capped at 16 characters (slider; 0 = no limit).
  - Enchants are a small icon at the end of the item level line, a green check when enchanted, a red cross when an enchantable slot has none, instead of a whole line. (Hover the item for the enchant's name.)
  - Shorter item level line: "292 P344 C1/6" = item level, PvP item level, Champion 1/6 (track letters: Ex, Ad, V, C, H, M, in the track's color).
  - The weapons' text sits under the weapons (which move up to make room), so it no longer runs into the bottom of the side columns.
  - No text on the shirt and tabard.
  - Smaller text: 11 / 10 (was 12 / 11); profiles still on the old sizes move down.
  - Every item is two lines at most (it was three).

## 0.34.1
- Flag Cap Indicator: each flag now sits under the score of the team carrying it (a Horde player with the Alliance flag shows under the Horde bar), and keeps that side when it's the only flag out. Before, bars filled from the left, so a lone flag, for example after the other carrier died, showed under the wrong team, and the Alliance side showed a flag even when the Alliance didn't have one. Option to swap if your score shows Horde on the left.
- Flag Cap Indicator: when the map shows a flag with art that doesn't name its team (after a drop and re-pickup), it's matched to the flag last seen nearest that spot instead of being treated as a new flag.

## 0.34.0
- Nameplates: your target is now found by its nameplate frame instead of asking the game "is this unit my target", which Blitz and rated PvP answer with a hidden (secret) value. That's why friendly targets in Blitz never got the full plate. Friendly and enemy targets now get the target treatment everywhere the game shows a nameplate for them.
- Flag Cap Indicator:
  - Plain flag icon in the team color only (no more map flag art with its base), in the box and under the score.
  - Shows whenever someone has a flag, and only then: a dropped flag or a flag at home isn't shown. A known carrier whose flag the map isn't showing still gets a bar ("HAS FLAG", no distance).
  - Fixed: it waited until both flags had been picked up before turning on, so a single carried flag never showed. On Warsong Gulch and Twin Peaks it's on from the start.
  - "Sit under the score" is now locked under the score bar at exactly its width (two flags side by side split it). Only the gap below it is adjustable; the X offset and the DROPPED color are gone.
- Important units in rated PvP: the game hides unit names and NPC IDs there (confirmed in Blizzard's API documentation), so the name / ID list can't match and nothing can recolor or resize those plates. New fallback that works with hidden names: a big glowing icon on units carrying a listed aura on themselves (default 8178, Grounding Totem Effect; add more spell IDs on the Plate Auras & Units page).
- /stinkie plates now also shows whether your target's name and NPC ID are hidden, whether it's a minion, whether it counts as important, and whether its plate was found as your target.

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
