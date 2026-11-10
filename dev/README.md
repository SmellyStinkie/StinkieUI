# dev

Development tools for Stinkie UI. Not part of the addon: the packager leaves this folder out of
the release zip.

- `tests/run.py`: loads the addon into a fake WoW client (`tests/mock.lua`) and runs
  `tests/tests.lua`. From the repo root: `python dev/tests/run.py`. Needs `pip install lupa`.
- `tests/test_import.lua`, `tests/test_mem.lua`: Rated Tracker import and memory checks against a
  real `RatedTracker.lua` SavedVariables file; set `STINKIE_RT` to its path first.
- `tools/make_preset.py`: turns a Stinkie UI export string (saved to a text file) into
  `Preset.lua`. From the repo root: `python dev/tools/make_preset.py export.txt Preset.lua`.
  Needs `pip install lupa cbor2`.
- `tests/check_api.py`: checks every game function, method and event the addon uses against the
  real clients' lists in `tests/api/` (`retail.txt`, `forever.txt`), and flags calls into
  Blizzard's Lua code (a taint risk). `run.py` runs it after the other tests; with no list files
  it's skipped. `tests/api/reviewed.txt` holds the names someone looked at and accepted, each
  with a reason, so anything new fails until it's reviewed.
- `tools/make_api_list.py`: builds those lists from the game's own exported UI code. Start the
  game with `-console`, open the console at the login screen with the ` key, run
  `ExportInterfaceFiles code`, then:
  `python dev/tools/make_api_list.py "<game>/_retail_/BlizzardInterfaceCode" retail` (and the same
  for `_forever_` with `forever`). Only names are kept. Redo it after a game patch.
