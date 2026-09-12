extends SceneTree
## tools/probe_warcamps4.gd -- pass five, fitting ONE number.
##
## Pass four: a cleared camp noting a goblin bias of -0.2 against its region
## every eight days takes ALLAGASH from a 0.614 goblin hold to 0.002 inside a
## game year -- and the ground does not become men's, it goes to the WOLVES.
## Two findings in one run. The magnitude is an order of magnitude too big, and
## the reason is Lemon's own model: `PUSH_GAIN` is divided by 1 + seats/4, and
## ALLAGASH HAS NO SEATS AT ALL. A push in the roadless north is worth ~2.5x a
## push at Down East and ~4x one at Casco Bay. The north is where the camps are,
## so the north is the population this constant has to be fitted against.

const SEED := 0x4D59524B


func _init() -> void:
	var c0 := Chronicle.new()
	c0.world_seed = SEED
	c0.boot(true)
	var seats := Factions.seats_from(c0.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var adj := Factions.adjacency(land, Factions.centres_of(Chronicle.REGION_ROSTER))
	var anch := Factions.anchors(land, seats, Factions.reach(land, seats, adj))

	print("=== HOW DAMPED IS EACH REGION? g = PUSH_GAIN / (1 + seats/SEAT_HALF) ===")
	for r: String in ["ALLAGASH", "BAXTER STATE PARK", "100-MILE WILDERNESS", "DOWN EAST",
			"AROOSTOOK", "CASCO BAY"]:
		var s := float(seats.get(r, 0.0))
		print("  %-22s seats %4.1f  g %.4f  (%.2fx the Allagash)" % [
			r, s, Factions.PUSH_GAIN / (1.0 + s / Factions.SEAT_HALF),
			(Factions.PUSH_GAIN / (1.0 + s / Factions.SEAT_HALF)) / Factions.PUSH_GAIN])
	print("")

	print("=== FITTING THE CLEARING PUSH AT ALLAGASH (the sensitive end) ===")
	var base := _arm("ALLAGASH", 0.0, 0.0, seats, land, adj, anch)
	print("  control: gob %.3f  goblin-days %d of 96" % [base.x, int(base.y)])
	for push: float in [0.01, 0.02, 0.05]:
		for every: float in [8.0, 24.0]:
			var t := _arm("ALLAGASH", push, every, seats, land, adj, anch)
			print("  push %.2f every %2.0f d (%2d camps a year): gob %.3f (%+.3f)  goblin-days %2d (%+d)  holder %s" % [
				push, every, int(96.0 / every), t.x, t.x - base.x, int(t.y),
				int(t.y) - int(base.y), _who(t.z)])
	print("")
	print("=== AND WHAT IS ONE CAMP WORTH? a single clearing, then silence ===")
	for push: float in [0.02, 0.05]:
		var c := Chronicle.new()
		c.world_seed = SEED
		c.boot(true)
		var st := Factions.blank(anch)
		var pu := Factions.blank_push(land)
		_wire(c, pu)
		for d in range(48):
			c.advance(24.0, 400)
			Factions.step(st, pu, anch, adj, seats, 1.0)
		var before := float(Factions.hold_of(st, "ALLAGASH").get(Factions.GOBLINS, 0.0))
		Factions.note(pu, "ALLAGASH", {"goblins": -push})
		var marks: Array = []
		for d in range(28):
			c.advance(24.0, 400)
			Factions.step(st, pu, anch, adj, seats, 1.0)
			if d == 0 or d == 6 or d == 13 or d == 27:
				marks.append("d+%d %.4f (%+.4f)" % [d + 1,
					float(Factions.hold_of(st, "ALLAGASH").get(Factions.GOBLINS, 0.0)),
					float(Factions.hold_of(st, "ALLAGASH").get(Factions.GOBLINS, 0.0)) - before])
		print("  push %.2f from gob %.4f: %s" % [push, before, str(marks)])
	quit(0)


func _wire(c: Chronicle, pushes: Dictionary) -> void:
	c.event_resolved.connect(func(ev: Dictionary) -> void:
		var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
		for o in (kind.get("outcomes", []) as Array):
			var od := o as Dictionary
			if String(od.get("id", "")) == String(ev.get("outcome", "")):
				var p3: Vector2 = ev.get("pos", Vector2.ZERO)
				Factions.note(pushes, Factions.region_at(Vector3(p3.x, 0.0, p3.y),
					Chronicle.REGION_ROSTER), od.get("bias", {})))


func _arm(target: String, push: float, every: float, seats: Dictionary, land: Array,
		adj: Dictionary, anch: Dictionary) -> Vector3:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	_wire(c, pushes)
	var gdays := 0
	for d in range(96):
		if push > 0.0 and every > 0.0 and fmod(float(d), every) == 0.0:
			Factions.note(pushes, target, {"goblins": -push})
		c.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)
		if Factions.holder_of(state, target) == Factions.GOBLINS:
			gdays += 1
	var who := Factions.holder_of(state, target)
	var idx := 4.0
	for i in range(Factions.CLAIMANTS.size()):
		if String(Factions.CLAIMANTS[i]) == who:
			idx = float(i)
	return Vector3(float(Factions.hold_of(state, target).get(Factions.GOBLINS, 0.0)),
		float(gdays), idx)


func _who(idx: float) -> String:
	var i := int(idx)
	if i >= 0 and i < Factions.CLAIMANTS.size():
		return String(Factions.CLAIMANTS[i])
	return Factions.CONTESTED
