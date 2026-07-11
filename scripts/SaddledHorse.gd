extends Horse
class_name SaddledHorse
## The tame, RIDEABLE horse — saddle and stirrups mark it at a glance. Calm
## around people, and it will carry you (E to mount) for as long as you never
## hurt it. Same bestiary page as the wild kind: a horse is a horse.


func _init() -> void:
	super()
	rideable = true
	skittish_radius = 0.0  ## steady around footsteps — until trust breaks
