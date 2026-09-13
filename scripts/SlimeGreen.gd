extends Slime
class_name SlimeGreen
## Green slime — the common jelly — lazy hops, splits in two when it dies.
## Every number lives in Slime.KINDS["green"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("green")
