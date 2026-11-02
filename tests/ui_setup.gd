extends Reference
# Shared set-up of the UI tests: the real guitar menu scene on a stub HUD, with the mod running.
# Used by e_ui.gd and v_ui.gd.

var tree = null
var hud = null
var player = null
var minigame = null
var mod = null
var T = ""


func wipe_library():
	var d = Directory.new()
	if d.open("user://MIDIPlayer") == OK:
		d.list_dir_begin(true, true)
		var f = d.get_next()
		while f != "":
			if not d.current_is_dir():
				d.remove("user://MIDIPlayer/" + f)
			f = d.get_next()
		d.list_dir_end()


func prepare(t):
	tree = t
	T = OS.get_environment("TESTS_DIR")
	var root = tree.root
	var NW = root.get_node("Network")
	NW.STEAM_ID = 4242
	NW.STEAM_LOBBY_ID = 0
	NW.PLAYING_OFFLINE = true
	NW.OWNED_ACTORS = []
	var PD = root.get_node("PlayerData")
	PD.guitar_shapes = PD.DEFAULT_GUITAR_SHAPES.duplicate(true)
	for c in root.get_children():   # the game's autoload overlays (the scene transition's circle wipe) would cover a shot
		if c is CanvasLayer:
			c.visible = false
	var bg = ColorRect.new()
	bg.color = Color(0.11, 0.2, 0.3)
	bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(bg)
	hud = load(T + "/stub_hud.gd").new()
	root.add_child(hud)
	player = load(T + "/stub_player.gd").new()
	player.hud = hud
	root.add_child(player)


func start_mod(auto = true):
	mod = load("res://mods/MIDIPlayer/main.gd").new()
	mod.auto = auto
	tree.root.add_child(mod)
	return mod


# opens the guitar menu the way the game does: the scene is added to the HUD
func open_guitar():
	minigame = load("res://Scenes/Minigames/Guitar/guitar_minigame.tscn").instance()
	hud.add_child(minigame)
	return minigame


func close_guitar():
	if minigame != null and is_instance_valid(minigame):
		minigame.queue_free()
	minigame = null
