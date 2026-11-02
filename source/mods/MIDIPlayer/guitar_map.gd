extends Reference

# Turns the notes of a MIDI file into guitar strums: which string, which fret, when, how loud.
#
# The game's guitar has 6 strings tuned E A D G B E (MIDI 40 45 50 55 59 64) and the menu shows frets 0..15, so the
# playable range is MIDI 40 .. 79 (E2 .. G5). Each string is monophonic (a new note on a string cuts the one before),
# so chords have to use different strings and a held note should not be cut when another string is free.
#
#   var m = GuitarMap.new().build(notes, {"tracks": {0: true}, "semitones": 0, "auto_octave": true, "fold": true})
#   m["events"]   [[time_s, string, fret, volume], ...] sorted by time
#   m["total"] notes looked at, m["played"] strums made, m["out_of_range"], m["too_many"] (more than 6 at once /
#   no free string), m["too_fast"] (over MAX_PER_SECOND), m["octaves"] automatic octave shift, m["folded"]

const OPEN = [40, 45, 50, 55, 59, 64]
const MAX_FRET = 15
const LOW = 40
const HIGH = 79
const CHORD_WINDOW = 0.025       # notes starting within this many seconds of each other are one chord
const MAX_PER_SECOND = 48        # strums sent per second at most (every strum is a network message to everybody)
const DROP_COST = 10.0
const MAX_NODES = 4000

# working data of one chord
var _items = []
var _order = []
var _cands = []
var _costs = []
var _best = []
var _best_cost = 0.0
var _nodes = 0


func build(notes, opts):
	var res = {"events": [], "total": 0, "played": 0, "out_of_range": 0, "too_many": 0, "too_fast": 0,
		"octaves": 0, "folded": 0, "duration": 0.0}
	var enabled = opts.get("tracks", null)
	var semis = int(opts.get("semitones", 0))
	var fold = bool(opts.get("fold", true))
	var sel = []
	var hist = []
	hist.resize(128)
	for i in 128:
		hist[i] = 0
	for nt in notes:
		if nt[5] == 9:
			continue   # percussion channel: those numbers are drums, not pitches
		if enabled != null and not enabled.has(nt[4]):
			continue
		sel.append(nt)
		hist[nt[2]] += 1
	res["total"] = sel.size()
	if sel.empty():
		return res

	var octaves = 0
	if bool(opts.get("auto_octave", true)):
		var best = -1
		for k in [0, -1, 1, -2, 2, -3, 3, -4, 4]:   # in this order a tie goes to the smaller shift
			var cnt = 0
			for pch in 128:
				var q = pch + semis + 12 * k
				if q >= LOW and q <= HIGH:
					cnt += hist[pch]
			if cnt > best:
				best = cnt
				octaves = k
	res["octaves"] = octaves
	var shift = semis + 12 * octaves

	var items = []   # [start, end, pitch, velocity]
	for nt in sel:
		var q = nt[2] + shift
		if q < LOW or q > HIGH:
			if not fold:
				res["out_of_range"] += 1
				continue
			while q > HIGH:
				q -= 12
			while q < LOW:
				q += 12
			res["folded"] += 1
		items.append([nt[0], nt[1], q, nt[3]])

	var last_end = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0]
	var last_start = [-10.0, -10.0, -10.0, -10.0, -10.0, -10.0]
	var ref_fret = 5.0
	var events = []
	var i = 0
	var count = items.size()
	while i < count:
		var t0 = items[i][0]
		var j = i
		var group = {}   # pitch -> item (the louder one when a pitch is doubled)
		while j < count and items[j][0] - t0 <= CHORD_WINDOW:
			var it = items[j]
			if not group.has(it[2]) or group[it[2]][3] < it[3]:
				group[it[2]] = it
			j += 1
		i = j
		var g = group.values()
		if g.size() > 6:
			g.sort_custom(self, "_cmp_pitch_desc")
			var keep = [g[0], g[g.size() - 1]]   # the melody (highest) and the bass (lowest) first
			var mids = []
			for x in range(1, g.size() - 1):
				mids.append(g[x])
			mids.sort_custom(self, "_cmp_velocity_desc")
			for m in mids:
				if keep.size() < 6:
					keep.append(m)
			res["too_many"] += g.size() - 6
			g = keep
		var picks = _assign(g, last_end, last_start, ref_fret)
		var fret_sum = 0.0
		var fret_n = 0
		var chosen = []
		for x in g.size():
			var pk = picks[x]
			if pk == null:
				res["too_many"] += 1
				continue
			var s = pk[0]
			var f = pk[1]
			var it2 = g[x]
			last_end[s] = max(it2[1], it2[0] + 0.05)
			last_start[s] = it2[0]
			fret_sum += f
			fret_n += 1
			chosen.append([it2[0], s, f, clamp(0.4 + 0.6 * it2[3] / 127.0, 0.1, 1.0)])
		if fret_n > 0:
			ref_fret = 0.5 * ref_fret + 0.5 * (fret_sum / fret_n)
		chosen.sort_custom(self, "_cmp_time")
		for e in chosen:
			events.append(e)

	# the network limit
	var out = []
	var head = 0
	for e in events:
		while head < out.size() and e[0] - out[head][0] >= 1.0:
			head += 1
		if out.size() - head >= MAX_PER_SECOND:
			res["too_fast"] += 1
			continue
		out.append(e)
	res["events"] = out
	res["played"] = out.size()
	if not out.empty():
		res["duration"] = out[out.size() - 1][0]
	return res


func _cmp_pitch_desc(a, b):
	return a[2] > b[2]


func _cmp_velocity_desc(a, b):
	return a[3] > b[3]


func _cmp_time(a, b):
	return a[0] < b[0]


static func candidates(pitch):
	var out = []
	for s in 6:
		var f = pitch - OPEN[s]
		if f >= 0 and f <= MAX_FRET:
			out.append([s, f])
	return out


# Picks a (string, fret) for every note of one chord, all on different strings, with the least cost; returns an array
# with [string, fret] or null (note dropped) per note of g.
func _assign(g, last_end, last_start, ref_fret):
	_items = g
	_cands = []
	_costs = []
	for x in g.size():
		var cl = candidates(g[x][2])
		var costs = []
		for c in cl:
			costs.append(_cost(c[0], c[1], g[x], last_end, last_start, ref_fret))
		_cands.append(cl)
		_costs.append(costs)
	_order = []
	for x in g.size():
		_order.append(x)
	# the notes with the fewest choices first (insertion sort, at most 6 notes)
	for a in range(1, _order.size()):
		var v = _order[a]
		var b = a - 1
		while b >= 0 and _cands[_order[b]].size() > _cands[v].size():
			_order[b + 1] = _order[b]
			b -= 1
		_order[b + 1] = v
	_best = []
	_best.resize(g.size())
	_best_cost = 1.0e30
	_nodes = 0
	var cur = []
	cur.resize(g.size())
	_search(0, cur, 0.0, 0)
	return _best


func _cost(s, f, it, last_end, last_start, ref_fret):
	var c = 0.04 * abs(f - ref_fret) + 0.01 * f
	var remaining = last_end[s] - it[0]
	if remaining > 0.02:
		c += 1.0 + min(remaining, 2.0)   # would cut a note that is still held
	elif it[0] - last_start[s] < 0.06:
		c += 1.0                         # would cut an attack that has just started
	return c


func _search(depth, cur, cost, used):
	if cost >= _best_cost:
		return
	if depth == _order.size():
		_best_cost = cost
		_best = cur.duplicate()
		return
	_nodes += 1
	if _nodes > MAX_NODES and _best_cost < 1.0e29:
		return
	var x = _order[depth]
	var cl = _cands[x]
	var costs = _costs[x]
	# the cheapest first, so the first complete answer is already a good one
	var idx = []
	for k in cl.size():
		idx.append(k)
	for a in range(1, idx.size()):
		var v = idx[a]
		var b = a - 1
		while b >= 0 and costs[idx[b]] > costs[v]:
			idx[b + 1] = idx[b]
			b -= 1
		idx[b + 1] = v
	for k in idx:
		var s = cl[k][0]
		if used & (1 << s):
			continue
		cur[x] = cl[k]
		_search(depth + 1, cur, cost + costs[k], used | (1 << s))
	cur[x] = null   # leave the note out
	_search(depth + 1, cur, cost + DROP_COST, used)
	cur[x] = null
