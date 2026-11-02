#!/bin/bash
# Runs the headless tests against the decompiled game:
#   ./tests/run.sh            all of them
#   ./tests/run.sh midi map   only these (midi, map, play, ui)
# Needs Godot 3.5.3 headless, the decompiled game (git clone --depth 1 https://github.com/Blizzardfur-Maxxx/Webfishing-Decompiled)
# and python3:
#   GODOT=/path/to/Godot_v3.5.3-stable_linux_headless.64 GAME=/path/to/decomp ./tests/run.sh
# Against the built pck instead of the source (checks that nothing is missing from the pack):
#   MP_PCK=/abs/path/package/MIDIPlayer/MIDIPlayer.pck ./tests/run.sh
# (the game's Steam library is missing here, so a few "Steam" errors at the start are normal)
cd "$(dirname "$0")"
export GAME=${GAME:-/home/claude/wf-game/decomp}
GODOT=${GODOT:-/home/claude/godot/Godot_v3.5.3-stable_linux_headless.64}
./make_stubs.sh || exit 1
export TESTS_DIR=$(pwd)
export MIDI_DIR=$(mktemp -d)
python3 make_midis.py "$MIDI_DIR" || exit 1
WHICH=${@:-midi map play ui}
STATUS=0
# every script of the mod must be in the pack list, or the mod would be built without it
for f in ../source/mods/MIDIPlayer/*.gd; do
  n=$(basename "$f")
  grep -q "\"$n\"" ../pack.gd || { echo "FAIL pack.gd does not list $n"; STATUS=1; }
done
for t in $WHICH; do
  echo "=== $t"
  OUT=$(cd "$GAME" && timeout 600 "$GODOT" --path . -s "$TESTS_DIR/e_$t.gd" 2>&1)
  OUT=$(echo "$OUT" | grep -vE "LOBBY_TYPE_PUBLIC|Invalid get index 'active_zone'|Invalid get index 'view_distance'")
  echo "$OUT" | grep -E "^(ok|FAIL|---|SUMMARY|note)|SCRIPT ERROR|Parse Error|ERROR: .*(MIDIPlayer|mods/)"
  if echo "$OUT" | grep -qE "^FAIL|SCRIPT ERROR|Parse Error|ERROR: .*(MIDIPlayer|mods/)"; then STATUS=1; fi
  if ! echo "$OUT" | grep -q "^SUMMARY"; then echo "no SUMMARY line: the test did not finish"; STATUS=1; fi
done
rm -rf "$MIDI_DIR"
exit $STATUS
