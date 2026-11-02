#!/bin/bash
# Links the mod into the decompiled game project, where the game would load it from (res://mods/MIDIPlayer).
# With MP_PCK=<absolute path of MIDIPlayer.pck> the built pck is mounted by the tests instead (checks the pack).
# Nothing from the game is stored in this repo.
#   GAME=/path/to/decompiled/webfishing ./tests/make_stubs.sh
set -e
cd "$(dirname "$0")"
GAME=${GAME:-/home/claude/wf-game/decomp}
[ -f "$GAME/project.godot" ] || { echo "decompiled game not found at $GAME (set GAME=...)"; exit 1; }
if [ -n "$MP_PCK" ]; then
  rm -f "$GAME/mods/MIDIPlayer"
  echo "the mod comes from $MP_PCK"
else
  mkdir -p "$GAME/mods"
  # MOD_SRC (an absolute folder) lets mutate.py test a damaged copy of the source
  ln -sfn "${MOD_SRC:-$(cd .. && pwd)/source/mods/MIDIPlayer}" "$GAME/mods/MIDIPlayer"
  echo "mod linked into $GAME/mods"
fi
