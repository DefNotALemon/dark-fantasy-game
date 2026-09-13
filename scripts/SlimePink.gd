extends Slime
class_name SlimePink
## Pink slime — the leech: bounces off you and drinks the hit back.
## Every number lives in Slime.KINDS["pink"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("pink")
