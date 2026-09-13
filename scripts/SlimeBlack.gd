extends Slime
class_name SlimeBlack
## Black slime — the tar: heavy guard-breaking hurl, leaves you gummed and slow.
## Every number lives in Slime.KINDS["black"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("black")
