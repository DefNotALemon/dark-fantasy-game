extends SceneTree
## tools/probe_factions.gd -- MEASURE BEFORE CHOOSING A CONSTANT.
##   godot --headless --path . --script res://tools/probe_factions.gd
##
## Runs the REAL Chronicle for as many game years as asked, feeding every
## resolved outcome into the REAL Factions field, and prints the political map
## it produces. This is what fitted PUSH_GAIN, and it is what proves the map
## reaches a steady state instead of collapsing.

const SEED := 0x4D59524B


func _init() -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var seats := Factions.seats_from(c.places)
	var land := Factions.land_regions(Chronicle.REGION_ROSTER, seats)
	var centres := Factions.centres_of(Chronicle.REGION_ROSTER)
	var adj := Factions.adjacency(land, centres)
	var rch := Factions.reach(land, seats, adj)
	var anch := Factions.anchors(land, seats, rch)

	print("=== THE MAP, DERIVED ===")
	var dropped: Array = []
	for r in Chronicle.REGION_ROSTER:
		var rd := r as Dictionary
		if not land.has(String(rd.get("name", ""))):
			dropped.append(String(rd.get("name", "")))
	print("land regions: %d   off the map as open sea: %s" % [land.size(), str(dropped)])
	var edges := 0
	for a in land:
		edges += (adj[String(a)] as Array).size()
	print("adjacency edges: %d" % (edges / 2))
	print("table_problems: %s" % str(Factions.table_problems(land, seats, adj)))
	print("")

	print("=== AT REST (no event has ever happened) ===")
	var rest := Factions.blank(anch)
	for a in land:
		var an := String(a)
		var h: Dictionary = rest[an]
		print("  %-22s seats=%4.1f reach=%.2f  %-10s men %.2f gob %.2f wlf %.2f wild %.2f" % [
			an, float(seats.get(an, 0.0)), float(rch[an]), Factions.holder_of(rest, an),
			float(h[Factions.MEN]), float(h[Factions.GOBLINS]),
			float(h[Factions.WOLVES]), float(h[Factions.WILD])])
	print("  frontier pairs at rest: %d" % Factions.frontier(rest, adj).size())
	print("")

	_run(c, seats, land, adj, anch, 1)
	_run(c, seats, land, adj, anch, 4)
	_run(c, seats, land, adj, anch, 10)
	quit(0)


func _run(proto: Chronicle, seats: Dictionary, land: Array, adj: Dictionary,
		anch: Dictionary, years: int) -> void:
	var c := Chronicle.new()
	c.world_seed = SEED
	c.boot(true)
	var state := Factions.blank(anch)
	var pushes := Factions.blank_push(land)
	var was := {}
	for a in land:
		was[String(a)] = Factions.holder_of(state, String(a))
	var flips := 0
	var movers := {}
	var core: Array = ["CASCO BAY", "ANDROSCOGGIN R.", "AROOSTOOK", "KENNEBEC R."]
	var core_wobble: Array = []
	c.event_resolved.connect(func(ev: Dictionary) -> void:
		var kind := ChronicleEvents.by_id(String(ev.get("kind", "")))
		for o in (kind.get("outcomes", []) as Array):
			var od := o as Dictionary
			if String(od.get("id", "")) == String(ev.get("outcome", "")):
				var p3: Vector2 = ev.get("pos", Vector2.ZERO)
				var rn := Factions.region_at(Vector3(p3.x, 0.0, p3.y), Chronicle.REGION_ROSTER)
				Factions.note(pushes, rn, od.get("bias", {})))
	for d in range(96 * years):
		c.advance(24.0, 400)
		Factions.step(state, pushes, anch, adj, seats, 1.0)
		for a in land:
			var an := String(a)
			var now := Factions.holder_of(state, an)
			if now != String(was[an]):
				flips += 1
				movers[an] = true
				was[an] = now
				if core.has(an) and now != Factions.MEN and not core_wobble.has(an + ":" + now):
					core_wobble.append(an + ":" + now)
	var men := 0.0
	var gob := 0.0
	var tally := {}
	for a in land:
		var an := String(a)
		var h: Dictionary = state[an]
		men += float(h[Factions.MEN])
		gob += float(h[Factions.GOBLINS])
		var who := Factions.holder_of(state, an)
		tally[who] = int(tally.get(who, 0)) + 1
	print("=== AFTER %d GAME YEAR(S) ===" % years)
	print("  changes of hand: %d across %d regions   core seats that wobbled: %s" % [
		flips, movers.size(), str(core_wobble)])
	print("  mean men %.3f  mean goblins %.3f   holders %s   frontier pairs %d" % [
		men / float(land.size()), gob / float(land.size()), str(tally),
		Factions.frontier(state, adj).size()])
	if years == 1:
		for a in land:
			var an := String(a)
			var h2: Dictionary = state[an]
			print("    %-22s %-10s men %.2f gob %.2f wlf %.2f wild %.2f" % [
				an, Factions.holder_of(state, an), float(h2[Factions.MEN]),
				float(h2[Factions.GOBLINS]), float(h2[Factions.WOLVES]),
				float(h2[Factions.WILD])])
	print("")
