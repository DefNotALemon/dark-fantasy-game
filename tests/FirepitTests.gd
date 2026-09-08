extends SceneTree

# =============================================================================
# tests/FirepitTests.gd -- the fire that actually burns (2026-09-08, SYSTEMS).
#
#   godot --headless --path . --script res://tests/FirepitTests.gd
#
# Everything here runs without a Player and without World.tscn. The two things
# that need the engine rather than arithmetic -- the roof ray and the group
# bookkeeping -- get real nodes in the real physics world and a handful of
# frames to settle, because a shelter test that never runs a physics frame is
# a test of nothing.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one. A section killed by a runtime error therefore shows up as a claim
# that never settled, instead of silently taking its assertions with it and
# leaving a smaller green total behind (the trap IncidentTests found on
# 2026-09-07).
# =============================================================================

const MIN_ASSERTIONS := 118

var _pass := 0
var _fail := 0
var _frame := 0
var _elapsed := 0.0
var _claims: Dictionary = {}      ## section -> expected count
var _counts: Dictionary = {}      ## section -> actual count
var _section := ""

var _roof_fire: Firepit = null
var _open_fire: Firepit = null


class FakeWeather extends Node:
	var intensity := 0.0
	var level := 0


class FakeWorld extends Node:
	var w: FakeWeather = null
	func weather() -> Object:
		return w


# --------------------------------------------------------------------- harness

func claim(section: String, n: int) -> void:
	_section = section
	_claims[section] = n
	_counts[section] = 0


func ok(cond: bool, what: String) -> void:
	_counts[_section] = int(_counts.get(_section, 0)) + 1
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  [%s] %s" % [_section, what])


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func _fires_under(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if c is Firepit:
			k += 1
	return k


func _mk() -> Firepit:
	var f := Firepit.new()
	f.boot()
	return f


func _initialize() -> void:
	print("\n=== FirepitTests ===")


func _process(d: float) -> bool:
	_frame += 1
	_elapsed += d
	if _frame == 1:
		_t_fuel_table()
		_t_light_and_feed()
		_t_burn_down()
		_t_embers()
		_t_heat_curve()
		_t_heat_max_not_sum()
		_t_weather()
		_t_save()
		_t_determinism()
		_t_builtpiece()
		_setup_shelter()
		return false
	if _frame < 30 or _elapsed < 0.6:
		return false
	_t_shelter()
	_t_groups()
	_report()
	return true


func _report() -> void:
	for s in _claims:
		var want := int(_claims[s])
		var got := int(_counts.get(s, 0))
		if want != got:
			_fail += 1
			print("  FAIL  [claims] section '%s' claimed %d assertions, ran %d" % [s, want, got])
	print("\n--- %d passed, %d failed (floor %d) ---" % [_pass, _fail, MIN_ASSERTIONS])
	if _pass + _fail < MIN_ASSERTIONS:
		print("FAIL: only %d assertions ran" % (_pass + _fail))
		quit(1)
		return
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------------ the fuel

func _t_fuel_table() -> void:
	claim("fuel", 12)
	ok(Firepit.FUEL_MAX > Firepit.FUEL_PER_LOG, "the cap is more than one log")
	ok(Firepit.FUEL_PER_LOG > Firepit.FUEL_PER_PLANK, "a log beats a plank")
	ok(Firepit.FUEL_PER_PLANK > Firepit.FUEL_PER_STICK, "a plank beats a stick")
	ok(Firepit.FUEL_KINDLING < Firepit.FUEL_PER_LOG, "a torch alone is not a log")
	ok(Firepit.is_fuel("Log"), "Log burns")
	ok(Firepit.is_fuel("Plank"), "Plank burns")
	ok(Firepit.is_fuel("Stick"), "Stick burns")
	ok(not Firepit.is_fuel("Iron Sword"), "a sword does not burn")
	ok(not Firepit.is_fuel(""), "nothing is not fuel")
	near(Firepit.fuel_value("Log"), Firepit.FUEL_PER_LOG, 0.001, "Log is worth a log")
	near(Firepit.fuel_value("Rock"), 0.0, 0.001, "a rock is worth nothing")
	ok(Firepit.FUEL_MAX >= 1200.0, "the cap is at least a game day of burning")


# ------------------------------------------------------------- light and feed

func _t_light_and_feed() -> void:
	claim("light", 18)
	var f := _mk()
	ok(f.state == Firepit.State.OUT, "a new pit is out")
	ok(not f.burning(), "and not burning")
	ok(f.state_name() == "out", "and says so")
	near(f.heat_at(Vector3.ZERO), 0.0, 0.001, "a dead fire is not warm")
	ok(f.can_light(), "a dead pit takes a light")
	ok(f.light(), "it lights")
	ok(f.state == Firepit.State.LIT, "and is lit")
	ok(f.burning(), "and is burning")
	ok(f.state_name() == "lit", "and says so")
	near(f.fuel, Firepit.FUEL_KINDLING, 0.001, "kindling is what a torch buys")
	ok(not f.can_light(), "a burning fire cannot be lit again")
	ok(not f.light(), "and refuses")
	ok(f.feed(Firepit.FUEL_PER_LOG), "it takes a log")
	near(f.fuel, Firepit.FUEL_KINDLING + Firepit.FUEL_PER_LOG, 0.001, "the log went in")
	ok(f.feed(Firepit.FUEL_MAX * 2.0), "it takes an armful")
	near(f.fuel, Firepit.FUEL_MAX, 0.001, "but never past the cap")
	ok(not f.feed(-5.0), "negative wood is not wood")
	f.douse()
	ok(not f.feed(Firepit.FUEL_PER_LOG), "a dead pit will not take fuel without a light")
	f.free()


# ---------------------------------------------------------------- burning down

func _t_burn_down() -> void:
	claim("burn", 12)
	var f := _mk()
	f.light(120.0)
	near(f.fuel, 120.0, 0.001, "starts on two minutes")
	near(f.burn_rate(), 1.0, 0.001, "and burns at one second per second with no sky")
	f.tick(30.0)
	near(f.fuel, 90.0, 0.001, "thirty seconds is thirty seconds of wood")
	ok(f.state == Firepit.State.LIT, "still lit")
	f.tick(60.0)
	near(f.fuel, 30.0, 0.001, "and again")
	near(f.minutes_left(), 0.5, 0.01, "half a minute left, in minutes")
	f.tick(29.0)
	ok(f.state == Firepit.State.LIT, "still lit on the last second")
	ok(f.fuel > 0.0, "with wood to spare")
	f.tick(2.0)
	ok(f.state == Firepit.State.EMBERS, "out of wood is embers, not out")
	near(f.fuel, 0.0, 0.001, "and no wood left")
	near(f.ember_t, Firepit.EMBER_SECONDS, 0.001, "with a full ember clock")
	ok(f.heat_at(Vector3.ZERO) > 0.0, "embers are still warm")
	f.free()


func _t_embers() -> void:
	claim("embers", 11)
	var f := _mk()
	f.light(1.0)
	f.tick(2.0)
	ok(f.state == Firepit.State.EMBERS, "burnt straight through to embers")
	ok(f.state_name() == "embers", "and says so")
	ok(f.burning(), "embers count as burning")
	near(f.heat_at(Vector3.ZERO), Firepit.FIRE_HEAT_C * Firepit.EMBER_HEAT_MULT, 0.01,
		"a quarter of the heat")
	f.tick(Firepit.EMBER_SECONDS - 5.0)
	ok(f.state == Firepit.State.EMBERS, "still glowing five seconds out")
	f.tick(6.0)
	ok(f.state == Firepit.State.OUT, "then out")
	near(f.heat_at(Vector3.ZERO), 0.0, 0.001, "and cold")
	## banking: embers take a log without a torch
	var g := _mk()
	g.light(1.0)
	g.tick(2.0)
	ok(g.state == Firepit.State.EMBERS, "banked")
	ok(g.feed(Firepit.FUEL_PER_LOG), "embers take a log")
	ok(g.state == Firepit.State.LIT, "and come back up")
	near(g.fuel, Firepit.FUEL_PER_LOG, 0.001, "with the log's worth in it")
	f.free()
	g.free()


# ---------------------------------------------------------------------- heat

func _t_heat_curve() -> void:
	claim("heat", 14)
	var f := _mk()
	f.light(600.0)
	near(f.heat_at(Vector3.ZERO), Firepit.FIRE_HEAT_C, 0.001, "full heat at the stones")
	near(f.heat_at(Vector3(Firepit.FIRE_CORE, 0, 0)), Firepit.FIRE_HEAT_C, 0.001,
		"full heat out to the core radius")
	near(f.heat_at(Vector3(Firepit.FIRE_RANGE, 0, 0)), 0.0, 0.001, "nothing at the edge")
	near(f.heat_at(Vector3(12.0, 0, 0)), 0.0, 0.001, "nothing well past it")
	near(f.heat_at(Vector3(60.0, 0, 0)), 0.0, 0.001, "nothing across the valley")
	var mid := f.heat_at(Vector3((Firepit.FIRE_CORE + Firepit.FIRE_RANGE) * 0.5, 0, 0))
	ok(mid > 0.0 and mid < Firepit.FIRE_HEAT_C, "something in between")
	near(mid, Firepit.FIRE_HEAT_C * 0.5, 0.6, "and roughly half at the halfway mark")
	var last := 999.0
	var falling := true
	for i in range(1, 14):
		var h := f.heat_at(Vector3(float(i) * 0.5, 0, 0))
		if h > last + 0.0001:
			falling = false
		last = h
	ok(falling, "heat never rises with distance")
	ok(f.heat_at(Vector3(0, 2.0, 0)) > 0.0, "warmth reaches up as well as out")
	near(f.heat_at(Vector3(3.0, 0, 0)), f.heat_at(Vector3(0, 0, -3.0)), 0.001,
		"and is the same in every direction")
	f.douse()
	near(f.heat_at(Vector3.ZERO), 0.0, 0.001, "a doused fire warms nothing")
	near(f.fuel, 0.0, 0.001, "and keeps no wood")
	ok(not f.burning(), "and is not burning")
	ok(f.can_light(), "and can be lit again")
	f.free()


func _t_heat_max_not_sum() -> void:
	claim("max", 9)
	var a := _mk()
	var b := _mk()
	a.light(600.0)
	b.light(600.0)
	a.position = Vector3(3.0, 0, 0)
	b.position = Vector3(-3.0, 0, 0)
	var one := a.heat_at(Vector3.ZERO)
	ok(one > 0.0, "one fire three metres off is warm")
	var both := Firepit.heat_from([a, b], Vector3.ZERO)
	near(both, one, 0.001, "two campfires are not a furnace")
	ok(both < one * 1.9, "and specifically not the sum")
	b.position = Vector3.ZERO
	near(Firepit.heat_from([a, b], Vector3.ZERO), Firepit.FIRE_HEAT_C, 0.001,
		"the nearest fire wins")
	near(Firepit.heat_from([], Vector3.ZERO), 0.0, 0.001, "no fires, no heat")
	near(Firepit.heat_from([null], Vector3.ZERO), 0.0, 0.001, "a null is not a fire")
	var bare := Node3D.new()
	near(Firepit.heat_from([bare], Vector3.ZERO), 0.0, 0.001, "nor is a bare node")
	bare.free()
	a.douse()
	near(Firepit.heat_from([a, b], Vector3.ZERO), Firepit.FIRE_HEAT_C, 0.001,
		"a dead fire beside a live one changes nothing")
	b.douse()
	near(Firepit.heat_from([a, b], Vector3.ZERO), 0.0, 0.001, "two dead fires warm nothing")
	a.free()
	b.free()


# ------------------------------------------------------------------- weather

func _t_weather() -> void:
	claim("weather", 16)
	var world := FakeWorld.new()
	world.add_to_group("world")
	var wx := FakeWeather.new()
	root.add_child(world)
	world.add_child(wx)
	world.w = wx
	var f := _mk()
	root.add_child(f)

	wx.intensity = 0.0
	wx.level = 0
	near(f.burn_rate(), 1.0, 0.001, "a clear sky costs nothing")
	ok(f.can_light(), "and takes a light")
	ok(not f.storm_bound(), "and is not storm-bound")

	wx.intensity = Firepit.RAIN_THRESHOLD - 0.05
	near(f.burn_rate(), 1.0, 0.001, "drizzle is survivable")

	wx.intensity = 0.9
	wx.level = 3
	near(f.burn_rate(), Firepit.RAIN_BURN_MULT, 0.001, "rain in the open eats the wood twice as fast")
	ok(f.can_light(), "rain alone still takes a light")

	wx.level = 4
	near(f.burn_rate(), Firepit.RAIN_BURN_MULT, 0.001, "a storm burns twice as fast too")
	ok(f.storm_bound(), "a storm in the open is storm-bound")
	ok(not f.can_light(), "and will not take a light")
	ok(not f.light(), "and refuses one")
	ok(f.state == Firepit.State.OUT, "and stays out")

	wx.intensity = 0.4
	ok(not f.storm_bound(), "a storm that is not yet raining hard is still lightable")
	ok(f.light(), "and lights")
	ok(f.state == Firepit.State.LIT, "and is lit")

	## Rain doubling is measured, not asserted in the abstract.
	wx.intensity = 0.9
	f.fuel = 100.0
	f.tick(10.0)
	near(f.fuel, 80.0, 0.001, "ten seconds of storm costs twenty seconds of wood")
	wx.intensity = 0.0
	f.tick(10.0)
	near(f.fuel, 70.0, 0.001, "ten seconds of clear costs ten")

	f.queue_free()
	world.queue_free()


# ---------------------------------------------------------------------- save

func _t_save() -> void:
	claim("save", 17)
	var f := _mk()
	f.light(Firepit.FUEL_PER_LOG)
	f.tick(20.0)
	var d := f.to_dict()
	ok(d.has("state") and d.has("fuel") and d.has("ember"), "the dict has all three")
	var g := _mk()
	g.apply_dict(d)
	ok(g.state == f.state, "state survives")
	near(g.fuel, f.fuel, 0.001, "fuel survives")
	near(g.ember_t, f.ember_t, 0.001, "the ember clock survives")
	near(g.heat_at(Vector3.ZERO), f.heat_at(Vector3.ZERO), 0.001, "so does the heat")

	## A dict from a crash: lit with nothing left.
	var h := _mk()
	h.apply_dict({"state": Firepit.State.LIT, "fuel": 0.0, "ember": 0.0})
	ok(h.state == Firepit.State.EMBERS, "lit-with-no-wood loads as embers")
	ok(h.ember_t > 0.0, "with time on the clock")

	## Embers with a spent clock are simply out.
	h.apply_dict({"state": Firepit.State.EMBERS, "fuel": 0.0, "ember": 0.0})
	ok(h.state == Firepit.State.OUT, "spent embers load as out")

	## Junk.
	h.apply_dict({})
	ok(h.state == Firepit.State.OUT, "an empty dict is a cold pit")
	near(h.fuel, 0.0, 0.001, "with no wood")
	h.apply_dict({"state": 99, "fuel": 1e9, "ember": 1e9})
	ok(h.state == Firepit.State.OUT, "an impossible state falls back to out")
	near(h.fuel, Firepit.FUEL_MAX, 0.001, "and absurd fuel clamps to the cap")
	h.apply_dict({"state": -4, "fuel": -20.0, "ember": -3.0})
	ok(h.state == Firepit.State.OUT, "a negative state falls back to out")
	near(h.fuel, 0.0, 0.001, "and negative fuel clamps to nothing")
	near(h.ember_t, 0.0, 0.001, "as does a negative ember clock")

	## Round trip twice is the same fire.
	var i := _mk()
	i.apply_dict(g.to_dict())
	near(i.fuel, g.fuel, 0.001, "a second round trip drifts nowhere")
	ok(i.state == g.state, "and keeps its state")
	f.free()
	g.free()
	h.free()
	i.free()


func _t_determinism() -> void:
	claim("determinism", 4)
	var a := _mk()
	var b := _mk()
	a.light(Firepit.FUEL_PER_LOG)
	b.light(Firepit.FUEL_PER_LOG)
	for i in range(200):
		a.tick(2.0)
		b.tick(2.0)
	near(a.fuel, b.fuel, 0.0, "two fires fed the same wood burn to the same second")
	ok(a.state == b.state, "and end in the same state")
	near(a.ember_t, b.ember_t, 0.0, "with the same ember clock")
	near(a.heat_at(Vector3.ZERO), b.heat_at(Vector3.ZERO), 0.0, "and the same heat")
	a.free()
	b.free()


# ---------------------------------------------------------------- BuiltPiece

func _t_builtpiece() -> void:
	claim("piece", 17)
	var holder := Node3D.new()
	root.add_child(holder)
	var p := BuiltPiece.make("firepit")
	holder.add_child(p)
	ok(p.fire != null, "a firepit piece grows a fire")
	ok(p.fire.state == Firepit.State.OUT, "and it starts cold")
	ok(p.fire.is_in_group("fires"), "and is findable as a fire")
	ok(p.get_child_count() > 1, "and still has its stones")

	var w := BuiltPiece.make("wall")
	holder.add_child(w)
	ok(w.fire == null, "a wall does not grow a fire")
	ok(not w.save_dict().has("fire"), "and writes no fire down")

	p.fire.light(Firepit.FUEL_PER_LOG)
	var d := p.save_dict()
	ok(d.has("fire"), "a firepit writes its fire down")
	ok(int((d["fire"] as Dictionary)["state"]) == Firepit.State.LIT, "as lit")

	var q := BuiltPiece.from_dict(d)
	holder.add_child(q)
	ok(q.fire != null, "and grows one back")
	ok(q.fire.state == Firepit.State.LIT, "still lit")
	near(q.fire.fuel, p.fire.fuel, 0.001, "with the same wood in it")
	ok(q.piece == "firepit", "and is still a firepit")

	## Twice through _ready must not double the fire -- and "not double" is
	## counted as FIREPIT children, not as child count, because a second fire
	## hiding among nine stones is exactly the kind of leak a total misses.
	ok(_fires_under(q) == 1, "a restored piece has exactly one fire")
	var before := q.get_child_count()
	q._attach_fire()
	ok(q.get_child_count() == before, "attaching the fire twice adds nothing")
	ok(_fires_under(q) == 1, "and still exactly one fire")
	## And with the handle lost -- a re-parent, a reload -- it must find the
	## fire already hanging there rather than hang a second one beside it.
	q.fire = null
	q._attach_fire()
	ok(_fires_under(q) == 1, "a lost handle finds the existing fire, not a new one")
	ok(q.fire != null, "and the handle comes back")
	holder.queue_free()


# -------------------------------------------------------- shelter and groups

func _setup_shelter() -> void:
	## A real roof, in the real physics world, over one of two fires.
	_roof_fire = _mk()
	_roof_fire.position = Vector3(0, 0, 0)
	root.add_child(_roof_fire)
	var roof := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4, 0.3, 4)
	cs.shape = bs
	roof.add_child(cs)
	roof.position = Vector3(0, 3.0, 0)
	root.add_child(roof)

	_open_fire = _mk()
	_open_fire.position = Vector3(40, 0, 0)
	root.add_child(_open_fire)


func _t_shelter() -> void:
	claim("shelter", 8)
	ok(_roof_fire != null and _open_fire != null, "both fires were built")
	_roof_fire._shelter_t = 0.0
	_open_fire._shelter_t = 0.0
	ok(_roof_fire.sheltered(), "a fire under a roof is sheltered")
	ok(not _open_fire.sheltered(), "a fire in the open is not")

	## The whole point of the roof: it saves the wood and it lets you strike.
	var world := FakeWorld.new()
	world.add_to_group("world")
	root.add_child(world)
	var wx := FakeWeather.new()
	world.add_child(wx)
	world.w = wx
	wx.intensity = 0.9
	wx.level = 4
	near(_roof_fire.burn_rate(), 1.0, 0.001, "rain that misses the fire costs nothing")
	near(_open_fire.burn_rate(), Firepit.RAIN_BURN_MULT, 0.001, "rain that lands doubles it")
	ok(not _roof_fire.storm_bound(), "you can strike a light under a roof in a storm")
	ok(_open_fire.storm_bound(), "and not out in it")
	ok(_roof_fire.light(), "so the sheltered one lights")
	world.queue_free()


func _t_groups() -> void:
	claim("groups", 6)
	var f := _mk()
	root.add_child(f)
	ok(f.is_in_group("fires"), "every pit is a fire, lit or not")
	ok(not f.is_in_group("campfires"), "a cold pit gives no smoke")
	f.light(60.0)
	ok(f.is_in_group("campfires"),
		"a lit one does -- CritterSwarm._harass has been reading this group all along")
	f.tick(61.0)
	ok(f.is_in_group("campfires"), "embers still smoke")
	f.tick(Firepit.EMBER_SECONDS + 1.0)
	ok(not f.is_in_group("campfires"), "a dead fire stops")
	ok(f.is_in_group("fires"), "but is still a pit")
	f.queue_free()
