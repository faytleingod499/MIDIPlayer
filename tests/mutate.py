#!/usr/bin/env python3
"""Mutation check: puts one deliberate bug at a time into a COPY of the mod and runs the tests that should notice.
Every mutation must make at least one check FAIL, otherwise the tests would not have caught that bug.

    python3 tests/mutate.py            all mutations
    python3 tests/mutate.py 3 5        only these numbers
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source", "mods", "MIDIPlayer")

# (file, old text, new text, tests to run, what the bug is)
M = [
    ("midi_file.gd", "return _ts[lo] + float(tick - _tt[lo]) * _tu[lo] / 1000000.0 / _tpq",
     "return _ts[lo] + float(tick - _tt[lo]) * 500000 / 1000000.0 / _tpq", "midi", "tempo changes ignored"),
    ("midi_file.gd", "if kind == 0x90 and vel > 0:", "if kind == 0x90:", "midi", "note on with velocity 0 taken as a note"),
    ("midi_file.gd", "			if dend > end:\n				break\n", "", "midi", "meta event length not checked against the chunk"),
    ("guitar_map.gd", "		c += 1.0 + min(remaining, 2.0)   # would cut a note that is still held", "		pass", "map", "held notes are cut as if free"),
    ("guitar_map.gd", "const MAX_PER_SECOND = 48", "const MAX_PER_SECOND = 480", "map", "no network limit"),
    ("guitar_map.gd", "		if nt[5] == 9:\n			continue", "		if false:\n			continue", "map", "drum channel played as notes"),
    ("guitar_map.gd", "			if cnt > best:", "			if cnt >= best:", "map", "octave tie goes to the larger shift"),
    ("song_player.gd", "	clock += min(delta, MAX_DELTA) * speed", "	clock += delta * speed", "play", "a long frame makes the song jump"),
    ("song_player.gd", "		if events[mid][0] < clock:", "		if events[mid][0] <= clock:", "play", "seek off by one"),
    ("song_player.gd", "	if s < 0 or s > 5 or f < 0 or f > 15:\n		return", "	if false:\n		return", "play", "bad strums are sent"),
    ("main.gd", "	if not _is_midi_name(f) or f.find(\"/\") >= 0 or f.find(\"\\\\\") >= 0:\n		return", "	if false:\n		return", "ui", "delete follows a path"),
    ("main.gd", "		minigame.set_process(not on)", "		pass", "ui", "string keys still strum under a file dialog"),
    ("main.gd", "	if not markers_dirty:\n		return", "	return", "ui", "markers are not given back"),
    ("main.gd", "	if player.playing:\n		player.pause()\n	player.stop()\n	set_keys_blocked(false)", "	set_keys_blocked(false)", "ui", "song keeps playing when the menu closes"),
    ("main.gd", "	if RESERVED.has(out.split(\".\")[0].to_upper()):\n		out = \"_\" + out", "	pass", "ui", "Windows device names allowed"),
    ("main.gd", "		if not r[\"ok\"]:\n			bad.append(\"%s (%s)\" % [fname, r[\"error\"]])\n			continue", "		pass", "ui", "files are not checked on import"),
    ("main.gd", "	if mode == 1:\n		player.seek(0.0)\n		player.play()", "	if mode == 1:\n		pass", "ui", "repeat song does nothing"),
    ("window.gd", "	if _remove_armed == f and _clock <= _remove_until:", "	if true:", "ui", "Remove needs no second click"),
    ("window.gd", "	if not _updating:\n		mod.set_speed(v)", "	pass", "ui", "speed slider does nothing"),
    ("main.gd", "			saved_actions[a] = InputMap.get_action_list(a)\n			InputMap.action_erase_events(a)", "			pass", "ui", "game keys stay bound under a file dialog"),
    ("main.gd", "func _restore_actions():\n	for a in saved_actions:", "func _restore_actions():\n	for a in []:", "ui", "game keys are not given back"),
    ("main.gd", "	set_keys_blocked(false)\n	minigame = null", "	minigame = null", "ui", "keys stay off when the menu closes under a dialog"),
]


def run(which, src):
    env = dict(os.environ, MOD_SRC=src)
    out = subprocess.run([os.path.join(HERE, "run.sh")] + which.split(), capture_output=True, text=True, env=env, timeout=900).stdout
    fails = [l for l in out.splitlines() if l.startswith("FAIL") or "SCRIPT ERROR" in l or "Parse Error" in l]
    return fails


def main():
    pick = [int(a) for a in sys.argv[1:]]
    bad = 0
    for i, (fname, old, new, tests, what) in enumerate(M, 1):
        if pick and i not in pick:
            continue
        tmp = tempfile.mkdtemp()
        dst = os.path.join(tmp, "MIDIPlayer")
        shutil.copytree(SRC, dst)
        p = os.path.join(dst, fname)
        text = open(p).read()
        if text.count(old) != 1:
            print("%2d  CAN'T APPLY (%d matches): %s" % (i, text.count(old), what))
            bad += 1
            continue
        open(p, "w").write(text.replace(old, new))
        fails = run(tests, dst)
        status = "caught" if fails else "NOT CAUGHT"
        if not fails:
            bad += 1
        print("%2d  %-10s %s  (%s)  %s" % (i, status, what, tests, ("; ".join(fails[:2]))[:150]))
        shutil.rmtree(tmp)
    # put the link back to the real source
    subprocess.run([os.path.join(HERE, "make_stubs.sh")], capture_output=True)
    print("not caught or not applied: %d" % bad)
    sys.exit(1 if bad else 0)


main()
