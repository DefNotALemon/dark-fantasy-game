extends Slime
class_name SlimeYellow
## Yellow slime — the jolt: skitters side to side at you, then leaps; the touch shocks.
## Every number lives in Slime.KINDS["yellow"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("yellow")
