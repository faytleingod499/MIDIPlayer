extends Spatial
# TEST STUB: just enough of the player for the mod to find the HUD (group controlled_player, hud).
var hud = null
var held_item = {"id": "empty_hand", "ref": 0, "size": 1.0, "quality": 0, "tags": []}   # what the character holds


func _ready():
	add_to_group("controlled_player")
