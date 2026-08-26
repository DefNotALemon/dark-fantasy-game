class_name LabPlayer
extends CharacterBody3D
## Stand-in player for the headless suites. Records what wildlife does to it
## (damage, quills, stink, bites) so the tests can assert on it, and exposes
## the small surface the creature code probes with `has_method`.

var damage_taken := 0.0
var quills := 0
var stink_t := 0.0
var bites := 0.0
var level := 1
var grass_hidden := false
var sprinting := false
var crouching := false
var prone := false
var log_lines: Array = []


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)


func take_damage(amount: float, _from = null, _strong = false, _throw = null, _attacker: Node = null) -> void:
	damage_taken += amount


func stick_quills(n: int) -> void:
	quills += n


func apply_stink(seconds: float) -> void:
	stink_t = maxf(stink_t, seconds)


func apply_bug_bites(amount: float) -> void:
	bites += amount


func on_mob_slain(_e: Node) -> void:
	pass


func _add_log_msg(text: String, _col: Color) -> void:
	log_lines.append(text)


func notify(text: String, _col := Color.WHITE) -> void:
	log_lines.append(text)
