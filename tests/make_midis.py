#!/usr/bin/env python3
"""Writes test MIDI files plus the notes each one must give (ground truth) into a folder:

    python3 make_midis.py <out dir>

Every song is described as notes with known times and then encoded to bytes by the small writer below, so the expected
notes come from the description and not from any reader. <name>.mid has <name>.json next to it:
    {"ok": true, "notes": [[start_s, end_s, pitch, velocity, track, channel], ...], "tracks": n}
or {"ok": false}. Notes are sorted by (start, pitch, track).
"""
import json
import os
import random
import struct
import sys
from fractions import Fraction


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def chunk(tag, body):
    return tag + struct.pack(">I", len(body)) + body


def track_bytes(events, running=False):
    """events: [(tick, bytes)] in order. With running=True a channel message with the same status as the one
    before it leaves its status byte out (as many real files do)."""
    out = b""
    t = 0
    last_status = None
    for tick, data in sorted(events, key=lambda e: e[0]):
        out += vlq(tick - t)
        t = tick
        st = data[0]
        if running and st < 0xF0 and st == last_status:
            out += data[1:]
        else:
            out += data
        last_status = st if st < 0xF0 else None
    return out


def end_of_track(tick):
    return (tick, b"\xff\x2f\x00")


def tempo(tick, us):
    return (tick, b"\xff\x51\x03" + us.to_bytes(3, "big"))


def name(tick, text):
    t = text.encode()
    return (tick, b"\xff\x03" + vlq(len(t)) + t)


def note(ch, pitch, vel, start, end):
    return [(start, bytes([0x90 | ch, pitch, vel])), (end, bytes([0x80 | ch, pitch, 0]))]


def note0(ch, pitch, vel, start, end):
    """the note off written as a note on with velocity 0 (same status byte, so running status applies)"""
    return [(start, bytes([0x90 | ch, pitch, vel])), (end, bytes([0x90 | ch, pitch, 0]))]


def smf(fmt, division, tracks, running=False):
    body = struct.pack(">HHH", fmt, len(tracks), division)
    out = chunk(b"MThd", body)
    for ev in tracks:
        out += chunk(b"MTrk", track_bytes(ev, running))
    return out


class TempoMap:
    def __init__(self, division, changes):
        # changes: [(tick, us per quarter)] sorted; later entries at the same tick win
        self.division = division
        pts = [(0, 500000)]
        for tk, us in changes:
            if tk <= pts[-1][0]:
                pts[-1] = (pts[-1][0], us)
            else:
                pts.append((tk, us))
        self.pts = pts

    def sec(self, tick):
        s = Fraction(0)
        for i, (tk, us) in enumerate(self.pts):
            nxt = self.pts[i + 1][0] if i + 1 < len(self.pts) else None
            if nxt is None or tick <= nxt:
                s += Fraction(tick - tk) * us / 1000000 / self.division
                return float(s)
            s += Fraction(nxt - tk) * us / 1000000 / self.division
        return float(s)


def truth(tm, notes):
    """notes: [(start_tick, end_tick, pitch, vel, track, ch)] -> expected list"""
    rows = [[tm.sec(a), tm.sec(b), p, v, t, c] for a, b, p, v, t, c in notes]
    rows.sort(key=lambda r: (round(r[0], 5), r[2], r[4]))
    return rows


def save(out, fname, data, expect):
    with open(os.path.join(out, fname), "wb") as f:
        f.write(data)
    base = os.path.splitext(fname)[0]
    with open(os.path.join(out, base + ".json"), "w") as f:
        json.dump(expect, f)


def main(out):
    os.makedirs(out, exist_ok=True)
    div = 480

    # 1. format 0, a scale
    ev = [tempo(0, 500000), name(0, "Scale")]
    nl = []
    for i, p in enumerate([60, 62, 64, 65, 67, 69, 71, 72]):
        a = i * 480
        ev += note(0, p, 90 + i, a, a + 400)
        nl.append((a, a + 400, p, 90 + i, 0, 0))
    ev.append(end_of_track(3840))
    scale_bytes = smf(0, div, [ev])
    tm = TempoMap(div, [(0, 500000)])
    save(out, "scale.mid", scale_bytes, {"ok": True, "notes": truth(tm, nl), "tracks": 1})

    # 2. format 1, tempo changes, a note that spans a change, two tempo events on the same tick
    changes = [(0, 500000), (1920, 250000), (3840, 1000000), (3840, 800000), (5000, 400000)]
    cond = [name(0, "Conductor")] + [tempo(t, us) for t, us in changes] + [end_of_track(9000)]
    ev = []
    nl = []
    for i in range(20):
        a = i * 480
        ev += note(0, 48 + i, 80, a, a + 300)
        nl.append((a, a + 300, 48 + i, 80, 1, 0))
    ev += note(0, 36, 100, 1000, 6000)   # one long note across three tempo changes
    nl.append((1000, 6000, 36, 100, 1, 0))
    ev.append(end_of_track(9600))
    tm = TempoMap(div, changes)
    save(out, "tempo.mid", smf(1, div, [cond, ev]), {"ok": True, "notes": truth(tm, nl), "tracks": 2})

    # 3. running status (note on and off with the status left out) and an event that cancels it
    ev = [tempo(0, 600000)]
    nl = []
    t = 0
    for i in range(12):
        ev += note0(2, 50 + i, 70, t, t + 200)   # note on / note on with velocity 0: one status byte for all
        nl.append((t, t + 200, 50 + i, 70, 0, 2))
        t += 240
    ev.append((1000, b"\xff\x01\x04test"))      # a meta event clears running status
    ev.append(end_of_track(t + 100))
    tm = TempoMap(div, [(0, 600000)])
    save(out, "running.mid", smf(0, div, [ev], running=True), {"ok": True, "notes": truth(tm, nl), "tracks": 1})

    # 4. several tracks: names, programs, two channels in one track, drums on channel 9, overlapping notes of the
    #    same pitch (the first off ends the first on), a note that never ends, sysex and an unknown meta
    cond = [name(0, "Song"), tempo(0, 500000), (0, b"\xff\x58\x04\x04\x02\x18\x08"), end_of_track(4000)]
    a = [name(0, "Lead"), (0, bytes([0xC0, 25]))]
    nl = []
    for i, p in enumerate([72, 74, 76, 77]):
        a += note(0, p, 100, i * 480, i * 480 + 450)
        nl.append((i * 480, i * 480 + 450, p, 100, 1, 0))
    a.append((10, b"\xf0\x05\x7e\x7f\x09\x01\xf7"))
    a.append((20, b"\xff\x7f\x03abc"))
    a.append(end_of_track(2400))
    b = [name(0, "Bass & chords"), (0, bytes([0xC1, 33])), (0, bytes([0xC2, 0]))]
    b += note(1, 40, 90, 0, 1920)
    nl.append((0, 1920, 40, 90, 2, 1))
    b += note(2, 60, 80, 0, 960)
    nl.append((0, 960, 60, 80, 2, 2))
    # overlapping same pitch: on0 on1 off off -> pairs (on0, off0) and (on1, off1)
    b += [(100, bytes([0x91, 45, 60])), (200, bytes([0x91, 45, 61])), (300, bytes([0x81, 45, 0])), (500, bytes([0x81, 45, 0]))]
    nl.append((100, 300, 45, 60, 2, 1))
    nl.append((200, 500, 45, 61, 2, 1))
    # a note that never ends: closed by the end of the track
    b.append((700, bytes([0x92, 55, 99])))
    nl.append((700, 3000, 55, 99, 2, 2))
    b.append(end_of_track(3000))
    d = [name(0, "Drums")]
    for i in range(8):
        d += note(9, 36 if i % 2 == 0 else 38, 110, i * 240, i * 240 + 100)
        nl.append((i * 240, i * 240 + 100, 36 if i % 2 == 0 else 38, 110, 3, 9))
    d.append(end_of_track(2000))
    tm = TempoMap(div, [(0, 500000)])
    save(out, "multi.mid", smf(1, div, [cond, a, b, d]),
         {"ok": True, "notes": truth(tm, nl), "tracks": 4,
          "names": ["Song", "Lead", "Bass & chords", "Drums"], "programs": [-1, 25, 33, -1],
          "drums": [False, False, False, True]})

    # 5. SMPTE time: 25 frames per second, 40 ticks per frame = 1000 ticks per second
    nl = []
    ev = []
    for i in range(6):
        ev += note(0, 60 + i, 80, i * 500, i * 500 + 300)
        nl.append((i * 500, i * 500 + 300, 60 + i, 80, 0, 0))
    ev.append(end_of_track(4000))
    rows = [[a / 1000.0, b / 1000.0, p, v, t, c] for a, b, p, v, t, c in nl]
    smpte = struct.pack(">HHH", 0, 1, (0xE7 << 8) | 40)
    smpte = chunk(b"MThd", smpte) + chunk(b"MTrk", track_bytes(ev))
    save(out, "smpte.mid", smpte, {"ok": True, "notes": rows, "tracks": 1})

    # 6. the same scale inside a RIFF RMID wrapper
    data = chunk(b"data", scale_bytes + (b"\x00" if len(scale_bytes) & 1 else b""))
    riff = b"RIFF" + struct.pack("<I", 4 + len(data)) + b"RMID" + data
    tm = TempoMap(div, [(0, 500000)])
    nl = []
    for i, p in enumerate([60, 62, 64, 65, 67, 69, 71, 72]):
        nl.append((i * 480, i * 480 + 400, p, 90 + i, 0, 0))
    save(out, "wrapped.rmi", riff, {"ok": True, "notes": truth(tm, nl), "tracks": 1})

    # 7. damaged files
    save(out, "bad_empty.mid", b"", {"ok": False})
    save(out, "bad_garbage.mid", bytes(random.Random(5).randrange(256) for _ in range(500)), {"ok": False})
    save(out, "bad_text.mid", b"MThd is not what this file is, it is only text.", {"ok": False})
    save(out, "bad_nonotes.mid", smf(1, div, [[tempo(0, 500000), end_of_track(100)]]), {"ok": False})
    save(out, "bad_header.mid", b"MThd" + struct.pack(">IHHH", 3, 0, 1, 480) + b"\x00" * 10, {"ok": False})
    save(out, "bad_division.mid", chunk(b"MThd", struct.pack(">HHH", 0, 1, 0)) + chunk(b"MTrk", b"\x00\xff\x2f\x00"), {"ok": False})
    # the vlq of the first delta has 5 continuation bytes
    bad = chunk(b"MThd", struct.pack(">HHH", 0, 1, 480)) + chunk(b"MTrk", b"\xff\xff\xff\xff\xff\x7f\x90\x3c\x40")
    save(out, "bad_vlq.mid", bad, {"ok": False})
    # cut in the middle of the 5th note: the first 4 notes are still there
    ev = [tempo(0, 500000)]
    nl = []
    for i in range(8):
        ev += note(0, 60 + i, 80, i * 480, i * 480 + 400)
    ev.append(end_of_track(4000))
    full = smf(0, div, [ev])
    body = track_bytes(ev)
    # find the byte offset just after the 4th note-off by re-encoding the first events
    keep = [tempo(0, 500000)]
    for i in range(4):
        keep += note(0, 60 + i, 80, i * 480, i * 480 + 400)
        nl.append((i * 480, i * 480 + 400, 60 + i, 80, 0, 0))
    cut = len(track_bytes(keep)) + 8 + 14 + 2   # two bytes of the next event: its delta and half a message
    tm = TempoMap(div, [(0, 500000)])
    save(out, "cut.mid", full[:cut], {"ok": True, "notes": truth(tm, nl), "tracks": 1})
    # a track chunk that claims to be 4 GB long but the file ends: still the notes that are there
    evs = [tempo(0, 500000)] + note(0, 64, 80, 0, 200)
    raw = chunk(b"MThd", struct.pack(">HHH", 0, 1, 480)) + b"MTrk" + b"\xff\xff\xff\xff" + track_bytes(evs)
    save(out, "bad_chunklen.mid", raw, {"ok": True, "notes": truth(tm, [(0, 200, 64, 80, 0, 0)]), "tracks": 1})
    # bigger than the 3 MB limit
    save(out, "bad_big.mid", scale_bytes + b"\x00" * 3000100, {"ok": False})

    # 8. many notes (speed and the note limit)
    rng = random.Random(7)
    tracks = [[tempo(0, 500000)]]
    nl = []
    for ti in range(4):
        ev = []
        for i in range(30000):
            a = rng.randrange(0, 960 * 400)
            p = rng.randrange(30, 100)
            ev += note(ti, p, rng.randrange(1, 127), a, a + rng.randrange(1, 900))
        ev.append(end_of_track(960 * 400 + 1000))
        tracks.append(ev)
    save(out, "many.mid", smf(1, div, tracks, running=True), {"ok": True, "count": 120000, "tracks": 5})
    tracks = [[tempo(0, 500000)]]
    for ti in range(4):
        ev = []
        for i in range(40000):
            a = i * 10
            ev += note(ti, 60 + ti, 80, a, a + 5)
        tracks.append(ev)
    data = smf(1, div, tracks, running=True)
    save(out, "toomany.mid", data, {"ok": False, "size": len(data)})
    print("wrote", len(os.listdir(out)) // 2, "songs to", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "midis")
