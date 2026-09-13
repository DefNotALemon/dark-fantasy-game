extends Slime
class_name SlimeRed
## Red slime — the ember: fast skipping hops, the bounce sets you alight.
## Every number lives in Slime.KINDS["red"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("red")
