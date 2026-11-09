# Stinkie UI: notes for Claude

Stinkie UI is a flat PvP UI addon for World of Warcraft by Stinkie (twitch.tv/smellystinkie). It
covers unit, party, arena and battleground frames, nameplates, castbars, chat, cooldown bars, BG
timers and match history. One build ships to two game versions:

- **Midnight** (retail 12.1.5, Interface 120105)
- **WoW Forever** (Interface 16001). `ns.IS_FOREVER` is set from the project constants, with a
  fallback to the build's interface number (10000-19999).

Published on CurseForge (project 1780262) and Wago (rNkgx3Na) by the GitHub Actions workflow in
`.github/workflows/release.yml` (BigWigs packager) when a `v*` tag is pushed.

## Rules that never bend

- Only original code. Reading other addons for API facts is fine; copying their code is not.
- The author is "Stinkie (twitch.tv/smellystinkie)". Never put the owner's real name anywhere in
  the addon, the repo or commit messages.
- Don't tag or push a release until Stinkie has tried the change in game and says it's good.
  Commit locally as often as is useful; pushing `main` without a tag is fine when he asks.
- Releases are batched. Don't tag, bump the version, edit the changelog or suggest a release after
  each change. Wait until Stinkie calls for one, after several changes are in and all very stable.
- Explain changes in plain words, conclusion first. Be precise and direct, and make the change
  rather than describing it. Label anything not actually checked as unverified.

## Midnight API rules (secret values and taint)

- In Midnight many values are "secret" in combat and in PvP instances (unit names, auras, health,
  some scoreboard and widget values). Test with `issecret(v)` (or the `readable()` helper in
  modules) before comparing, doing arithmetic, using it as a table key or branching on it. A secret
  value can still be passed straight to widget setters (`SetText`, `SetValue`, and the
  `SetAlphaFromBoolean` family for secret booleans).
- Check each API's documentation flags: `UnitName` is SecretWhenUnitNameIdentityRestricted,
  `UnitCreatureID` is SecretWhenUnitIdentityRestricted, and `UnitIsUnit` is
  SecretWhenUnitComparisonRestricted.
- Taint:
  - Never edit Blizzard tables. For example, `PAPERDOLL_STATCATEGORIES` broke Blitz and Solo
    Shuffle once.
  - Never call Blizzard update or layout functions such as
    `ObjectiveTrackerManager:UpdateAll` or `CharacterFrame:Expand`/`Collapse`.
  - Never `Hide()` Blizzard Edit Mode frames.
  - Instead: change alpha, build our own frames, and post-hook with `hooksecurefunc`.
- Protected work in combat goes through `ns:RunOOC(fn)`.

## Layout

- `StinkieUI.toc`: load order. A new file must be added here, and the game needs a full restart
  (not /reload) to see a new file or a toc change.
- `Core.lua`:
  - namespace and event dispatcher (`ns:On`)
  - `ns.defaults` (every setting)
  - migrations: bump `ns.DB_VERSION` and add a step when an existing default changes for people
    who already have the addon
  - profiles, export/import (`STINKIEUI1:` strings), slash commands
  - `ns.profile`, the CPU profiler behind `/stinkie cpu`
- `Preset.lua`: the default layout new profiles start from. It holds only values that differ from
  `ns.defaults`. Regenerate it from an export string with `dev/tools/make_preset.py`.
- `Options.lua`: the options window. Pages are built in `Build...Page` functions, and the
  navigation list is at the bottom. `ShowPopup` is the shared dropdown list.
- One file per module, each registered with `ns:RegisterModule(name, mod)` and having `Init` and
  `Refresh`.
- `Modules.lua`: the module registry (`M.LIST`: id, files, pages, requires, conflicts, available).
  A new module needs an entry there, or it's treated as core and always loads. A module that's off
  never runs Init. A game setting a module forces needs `ns.Modules.Remember(id, cvar)` before the
  write, so it can be put back once the module is off. `dev/tests/modules.lua` boots each case
  (fresh install, upgrade, each module off, Forever) in its own mock client.
- `MatchRecorder.lua`: reads the scoreboard at the end of a match and saves one compact line
  (codec `C.TOP` / `C.PLAYER`). **Only ever add new fields at the end of `C.TOP` or `C.PLAYER`,
  and never remove one.** Saved lines are positional, and the player list is always the last part
  of a line.
- `StinkieUI_History/`: a separate load-on-demand addon for the Match History window (`/mh`). It
  ships as its own folder (`move-folders` in `.pkgmeta`).
- `dev/`: test harness and tools. They aren't shipped (they're in `.pkgmeta` ignore).

## Testing

- `pip install lupa cbor2`, then from the repo root: `python dev/tests/run.py`. It should end
  "N passed, 0 failed".
- `mock.lua` is a fake WoW client:
  - Add stubs there when new code calls an API the mock doesn't know.
  - Calls to unknown globals are listed at the end. One that matches a `local function` in the
    addon is reported as a failure, because it means a function was used before its definition.
- Add checks to `dev/tests/tests.lua` for new logic.
- `test_import.lua` and `test_mem.lua` need a real Rated Tracker file. Set `STINKIE_RT` to the
  path of `RatedTracker.lua` in the account's SavedVariables folder.
- Passing tests don't prove it works in game. Say what still needs checking in game.

## In-game debug commands

`/stinkie dmg`, `/stinkie cpu`, `/stinkie score`, `/stinkie plates`, `/stinkie auras`,
`/stinkie flags`, `/stinkie timers`, `/stinkie fontcheck`, `/stinkie quest`, `/stinkie tooltip`, `/stinkie map`,
`/stinkie report` (support block; errors caught in our pcalls go through `ns.Error`, which records them for it). They print what the game reports, so a
pasted result tells you what this client actually has. `/st` is short for `/stinkie`.

## Releasing

1. Bump `## Version:` in both `StinkieUI.toc` and `StinkieUI_History/StinkieUI_History.toc`.
2. Add a section at the top of `CHANGELOG.md` in plain words, written for players. Mention the
   README if commands changed.
3. Run the tests.
4. After Stinkie confirms in game:
   - `git commit -am "Stinkie UI X.Y.Z"` (add new files first)
   - `git tag vX.Y.Z`
   - `git push origin main`
   - `git push origin vX.Y.Z`
5. The Actions tab shows the packager run; CurseForge and Wago update a few minutes later.

## Cloud sessions (phone or web)

- There's no game here, so a fix is only ever mock-tested. Say so, and list what to check in game.
- Run the tests before pushing (the Testing section's commands work here). Each branch push also
  runs them in the Tests workflow on GitHub.
- Work on a branch, and leave it for Stinkie to review. Nothing but his say-so stops a push to
  `main` from here, so don't push there unless he asks in that session.
- Cloud sessions can't push tags. Tagging a release has to happen from a machine with git.
- The Rated Tracker tests can't run here because `STINKIE_RT` needs a file from the game folder.

## Local setup (Windows)

The game's AddOns folders for retail and Forever have directory junctions pointing at this repo:
`AddOns\StinkieUI` points to the repo, and `AddOns\StinkieUI_History` points to
`repo\StinkieUI_History`.

- Edits show up in game after `/reload`, or a full restart for new files and toc changes.
- Remove a junction only with `cmd /c rmdir`, never by deleting its contents.
- CurseForge is set to ignore updates for Stinkie UI on this machine, so it never overwrites the
  junctions.
