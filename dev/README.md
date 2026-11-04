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
