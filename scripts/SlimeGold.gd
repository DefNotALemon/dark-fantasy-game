extends Slime
class_name SlimeGold
## Gold slime — the gilt: never fights, bounds away, drops a purse if you catch it.
## Every number lives in Slime.KINDS["gold"]; this class exists so the M menu
## and the bestiary can spawn it by class (`cls.new()`), like every mob.


func _init() -> void:
	super()
	set_kind("gold")
