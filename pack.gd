# Rebuilds package/MIDIPlayer/MIDIPlayer.pck from source/ with the Godot 3.5 engine's own packer.
# Run from this folder with:  godot --no-window -s pack.gd
# (PCK_OUT and PCK_SRC_DIR can be set to absolute paths; PCK_SRC_DIR must be source/mods/MIDIPlayer.)
# FILES is a fixed list: a new script must be added here or it is silently left out of the mod.
extends SceneTree

const FILES = ["main.gd", "midi_file.gd", "guitar_map.gd", "song_player.gd", "window.gd"]

func _init():
	var out = OS.get_environment("PCK_OUT")
	if out == "":
		out = "package/MIDIPlayer/MIDIPlayer.pck"
	var src = OS.get_environment("PCK_SRC_DIR")
	if src == "":
		src = "source/mods/MIDIPlayer"
	var packer = PCKPacker.new()
	packer.pck_start(out, 32)
	for name in FILES:
		packer.add_file("res://mods/MIDIPlayer/" + name, src.plus_file(name))
	print("pack result: ", packer.flush(true))
	quit()
