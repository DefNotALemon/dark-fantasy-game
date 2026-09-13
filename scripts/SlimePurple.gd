extends Slime
class_name SlimePurple
## Purple slime — the venom: creeps flat, longest tell, longest leap, poison that ticks.
## Every number lives in Slime.KINDS["purple"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("purple")
