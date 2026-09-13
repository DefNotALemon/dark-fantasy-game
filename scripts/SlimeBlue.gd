extends Slime
class_name SlimeBlue
## Blue slime — high wet arcs; soaks you (and puts your fire out).
## Every number lives in Slime.KINDS["blue"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("blue")
