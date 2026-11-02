extends Spatial
# TEST STUB: just enough of the player for the mod to find the HUD (group controlled_player, hud).
var hud = null


func _ready():
	add_to_group("controlled_player")
