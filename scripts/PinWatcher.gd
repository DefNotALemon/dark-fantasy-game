extends Node
## (probe)

## Ticks the pinned-under-a-trunk timer for the Player without adding anything
## to Player's own _process / _physics_process. docs/TREES_v2_SPEC.md §8b.
##
## Created by Player.pin_under(), freed by Player.release_pin().

var target: Node


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	if target.has_method("pin_tick"):
		target.call("pin_tick", delta)
