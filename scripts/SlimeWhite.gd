extends Slime
class_name SlimeWhite
## White slime — the rime: shivers; drains warmth and stiffens you.
## Every number lives in Slime.KINDS["white"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("white")
