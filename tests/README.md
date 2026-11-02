# Tests

`./tests/run.sh` runs the headless tests inside the decompiled game project (real `PlayerData`, real guitar menu scene, real
player scene); nothing from the game is stored in this repo. Needs Godot 3.5.3 headless, python3 and
`git clone --depth 1 https://github.com/Blizzardfur-Maxxx/Webfishing-Decompiled` (set `GAME=` and `GODOT=` if they are not in
the default places, see `run.sh`). `./tests/run.sh midi` runs only one part.

- `make_midis.py` writes the test songs and what each must give. The expected notes come from the description of each song
  (known times and tempo changes), not from any reader.
- `e_midi.gd` the MIDI reader: tempo changes, running status, SMPTE, RIFF, several tracks, damaged files, 120000 notes, and
  1250 randomly damaged files (every answer must be sane).
- `e_map.gd` string and fret choice: every pitch, octave fitting, chords, held notes, the 48 per second limit.
- `e_play.gd` the clock (timing, pause, seek, speed, stalls, bad strums) and a strum going through the real player scene to the
  real guitar sound script.
- `e_ui.gd` the window in the real guitar menu: import, list, play, options, repeat, remove, drag and drop, bad files, names
  that are not safe, closing and opening the menu.
- `v_ui.gd` renders the window at 1920x1080 (windowed Godot under `xvfb-run`, see the header of the file).
- `mutate.py` puts one deliberate bug at a time into a copy of the mod; every one must make a test fail.

`MP_PCK=<abs path of MIDIPlayer.pck> ./tests/run.sh` tests the built pck instead of the source (checks that nothing is missing
from the pack).
