extends SceneTree

# =============================================================================
# tests/GarmentTests.gd -- what you are wearing, priced in degrees.
#
#   godot --headless --path . --script res://tests/GarmentTests.gd
#
# `Garments` is pure static arithmetic over `Materials`' own tables, so most
# of this is a sweep. Six sections carry more weight than the rest:
#
#   `tables` -- THE RECONCILIATION. `CONDUCT` has an opinion about all ten
#   metals and `Materials.MATS` has an opinion about seven of them (its
#   `element`). Every direction is re-derived here through
#   `Materials.element_name()` rather than restated, so giving a metal an
#   element in Materials.gd and not pricing it here turns this red and says
#   which metal.
#
#   `crossing` -- THE CLAIM OF THE FILE. A harness is a flat windbreak and a
#   conduction debt that is a FRACTION OF A GRADIENT, so the two cross at
#   some temperature, and the whole design lives or dies on where. The
#   crossing is SEARCHED FOR rather than asserted near a number, and the
#   claim is a relationship: a gale moves it at least nine degrees colder,
#   and dragonsteel has no crossing at all.
#
#   `gradient` -- the moment metal stops mattering is found by binary search
#   over two metals that disagree, and demanded to be EXACTLY
#   `Exposure.WARMTH_NEUTRAL_C`. There is no second definition of "warm
#   enough" in the project and this is what stops one appearing.
#
#   `slumber` -- the REAL night walk. `Slumber.night` takes the environment
#   dictionary, so clothing rides into it with no new plumbing, and this is
#   the section that proves the feature is a game rule and not a readout:
#   seven sets, seven different wakings, a three-and-a-quarter hour spread,
#   and the man in steel sleeping LESS than the naked one.
#
#   `exposure` and `place` -- the real front doors of `Exposure`, `Slumber`,
#   `Materials` and `Seasons`. A STUB IS NOT THE COLLABORATOR. `place` also
#   covers the second thing this round landed: `Seasons.base_c_at()` had no
#   caller, and now `Exposure.ambient_c` honours it.
#
#   `sources` -- negative scans and CALL SITES, through a comment stripper.
#   A method nobody calls is not a feature: every claim about wiring is
#   asserted against the caller's source, not by invoking the method here.
#
# SECTION CLAIMS: every section stakes what it is about to assert before it
# runs one, so a section killed by a runtime error shows up as a claim that
# never settled instead of quietly taking its assertions with it.
#
# EVERY LITERAL MARGIN BELOW IS SET AGAINST A NUMBER tools/probe_garments.gd
# MEASURED, not against a number that merely sounds demanding.
# =============================================================================

const MIN_ASSERTIONS := 170

## The fixture night: winter, nine in the evening, a breath of wind, open
## ground, sixty metres up. `ambient_c` -4.60; with the wind's own chill
## taken back out, the air a harness has been sitting in is -4.00.
const WINTER_STILL_C := -4.0
const WINTER_AMBIENT_C := -4.6
const SUMMER_STILL_C := 18.0
const BREATH_OF_WIND := 0.2

## Measured `Garments.garment_c` for a head-to-toe set, dry, at the fixture
## night's still air and a breath of wind.
const MEASURED_WINTER := {"steel": -1.08, "cold_iron": -2.98, "meteoric": 0.69,
	"dragonsteel": 2.46, "mithril": -0.67, "adamant": -1.49}

## The same sets in a full gale. Note steel turns POSITIVE.
const MEASURED_GALE := {"steel": 0.68, "cold_iron": -1.22, "meteoric": 2.45,
	"dragonsteel": 4.22, "mithril": 1.09, "adamant": 0.27}

## And soaked through, breath of wind.
const MEASURED_SOAKED := {"steel": -2.71, "cold_iron": -5.76, "meteoric": 0.12,
	"dragonsteel": 2.95, "adamant": -3.36}

## Hours actually slept out of ten, from 21:00, on the fixture night, walked
## by the real `Slumber.night`.
const MEASURED_SLEPT := {"naked": 8.00, "steel": 7.25, "cold_iron": 6.25,
	"meteoric": 8.25, "dragonsteel": 9.50, "mithril": 7.25, "adamant": 7.00}
const MEASURED_SLEPT_GALE := {"naked": 6.75, "steel": 7.00, "cold_iron": 6.25,
	"dragonsteel": 9.00}
const MEASURED_SLEPT_SOAKED := {"naked": 7.00, "steel": 5.75, "cold_iron": 5.00,
	"dragonsteel": 8.00}

## Coverage as the pieces go on in the order the weights imply: chest,
## legs, arms, head, boots.
const DRESS_ORDER: Array[String] = ["chest", "pants", "arms", "helmet", "shoes"]
const MEASURED_COVER: Array[float] = [0.38, 0.60, 0.76, 0.90, 1.00]
const MEASURED_COVER_WINTER: Array[float] = [-0.41, -0.65, -0.82, -0.97, -1.08]

## The two places, as `SeasonsTests.PLACES` holds them, and what
## `Seasons.base_c_at` says about them on day 66 -- the day the north is in
## winter and the south has not finished autumn.
const CASCO_BAY := Vector3(600.2, 8.0, 559.9)
const AROOSTOOK := Vector3(3600.2, 210.0, -7000.1)
const MEASURED_AROOSTOOK_66_LOCAL := -9.97
const MEASURED_AROOSTOOK_66_SHARED := 2.02

## Measured drying at a fire, wet 0.8: bare skin -0.04000 per second, full
## plate -0.02400.
const MEASURED_DRY_BARE := -0.04
const MEASURED_DRY_PLATE := -0.024

var _pass := 0
var _fail := 0
var _claims: Dictionary = {}
var _counts: Dictionary = {}
var _section := ""


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


func near_f(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.4f, want %.4f +/- %.4f)" % [what, a, b, tol])


func complains(bad: Array, phrase: String) -> bool:
	for b in bad:
		if String(b).contains(phrase):
			return true
	return false


func _code_only(src: String) -> String:
	## Borrowed verbatim from `SeasonsTests`, which is where it was written
	## after four rounds running of a negative source scan going red on the
	## comment that explains it. Two passes: a line that is ALL comment goes
	## entirely, and a TRAILING comment is cut off any line with no quote in
	## it -- the second pass is what stops a call being switched off as
	## `pass  # thing()` and the scan still finding its text.
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var s := String(line)
		var t := s.strip_edges()
		if t.begins_with("#"):
			continue
		var h := s.find("#")
		if h >= 0 and not s.substr(0, h).contains("\""):
			s = s.substr(0, h)
		out.append(s)
	return "\n".join(out)


# ------------------------------------------------------------------ fixtures

func full(m: String) -> Dictionary:
	var d: Dictionary = {}
	for slot: String in Materials.ARMOR_SLOTS:
		d[slot] = m
	return d


func night_env(worn: Dictionary, season: int, wind: float, sheltered: bool) -> Dictionary:
	return Exposure.env({"season": season, "hour": 21.0, "wind": wind,
		"sheltered": sheltered, "worn": worn})


func slept(worn: Dictionary, season: int, wind: float, wet: float, sheltered: bool) -> Dictionary:
	return Slumber.night(night_env(worn, season, wind, sheltered),
		Exposure.WARMTH_MAX, wet, 10.0, 0.0, 0.0)


func gc(worn: Dictionary, air: float, wet: float, wind: float) -> float:
	return Garments.garment_c(worn, air, wet, wind)


# =============================================================================
#  tables -- and they have to agree with Materials
# =============================================================================

func _t_tables() -> void:
	claim("tables", 22)

	ok(Garments.table_problems().is_empty(),
		"the file's own reconciliation is clean: %s" % str(Garments.table_problems()))

	## COVER is exactly the armour slots, and nothing else.
	ok(Garments.COVER.size() == Materials.ARMOR_SLOTS.size(),
		"one cover weight per armour slot")
	for slot: String in Materials.ARMOR_SLOTS:
		ok(Garments.COVER.has(slot), "%s has a cover weight" % slot)
	var tot := 0.0
	for slot in Garments.COVER:
		tot += float(Garments.COVER[slot])
	near_f(tot, 1.0, 1e-9, "the five weights are a whole body")

	## CONDUCT is exactly the metals, and every value is derived from the
	## element Materials gives that metal -- re-derived HERE, not restated.
	ok(Garments.CONDUCT.size() == Materials.ORDER.size(),
		"one conduction per metal")
	var warm := 0
	var cold := 0
	var plain := 0
	for id: String in Materials.ORDER:
		var el := Materials.element_name(id)
		var c := float(Garments.CONDUCT[id])
		if Garments.WARM_ELEMENTS.has(el):
			ok(c < 1.0, "%s carries %s and runs cooler than plain metal" % [id, el])
			warm += 1
		elif Garments.COLD_ELEMENTS.has(el):
			ok(c > 1.0, "%s carries %s and runs colder than plain metal" % [id, el])
			cold += 1
		elif el == "":
			near_f(c, 1.0, 1e-9, "%s has no element and is plain metal" % id)
			plain += 1
		else:
			ok(true, "%s carries %s, which is neither warm nor cold" % [id, el])
	ok(warm >= 3, "and at least three metals in the game are warm to wear (%d)" % warm)
	ok(cold >= 1, "and at least one is cold (%d)" % cold)
	ok(plain >= 3, "and the mundane metals are plain (%d)" % plain)

	## THE GUARD THAT MAKES THE WINDBREAK HONEST, stated as a literal: a
	## full harness gives back 2.2 of the 3.0 a gale takes, so no amount of
	## plate can make a gale better than still air.
	ok(Garments.WIND_BREAK_C < absf(Exposure.WIND_C),
		"a harness never hands back more of the gale than the gale took")
	near_f(absf(Exposure.WIND_C) - Garments.WIND_BREAK_C, 0.8, 0.001,
		"and it leaves at least eight tenths of a degree of gale on the table")
	var naked_gale := Exposure.ambient_c(Exposure.env({"season": 3, "hour": 21.0, "wind": 1.0}))
	var plate_gale := naked_gale + gc(full("steel"), WINTER_STILL_C, 0.0, 1.0)
	var still := Exposure.ambient_c(Exposure.env({"season": 3, "hour": 21.0, "wind": 0.0}))
	ok(plate_gale < still,
		"so a gale in full plate is still worse than still air bare-headed")

	ok(Garments.DRY_MULT_FULL < 1.0, "and a harness never dries you faster than skin")

	## ⚠ AND THE GUARDS THEMSELVES HAVE TO BE REACHABLE. The first sweep
	## opened three of `table_problems()`' thresholds to nonsense and nothing
	## moved: the shipped tables are correct, so a guard that cannot fire at
	## the shipped values is a guard no mutation can reach. `problems_in()`
	## takes the tables rather than reading the constants, so the suite can
	## hand it one that IS wrong and demand the right complaint back.
	var gc_cover: Dictionary = Garments.COVER.duplicate()
	var gc_cond: Dictionary = Garments.CONDUCT.duplicate()
	var wb := Garments.WIND_BREAK_C
	var dm := Garments.DRY_MULT_FULL
	var ct := Garments.COVER_TOTAL
	ok(Garments.problems_in(gc_cover, gc_cond, ct, wb, dm).is_empty(),
		"the shipped tables, handed back in, produce no complaint")

	var heavy := gc_cover.duplicate()
	heavy["pants"] = 0.60
	ok(complains(Garments.problems_in(heavy, gc_cond, ct, wb, dm), "sum to"),
		"cover weights that do not add up are refused")
	var thin := gc_cover.duplicate()
	thin.erase("shoes")
	ok(complains(Garments.problems_in(thin, gc_cond, 0.90, wb, dm), "no cover weight"),
		"an armour slot nobody dressed is refused")
	var odd := gc_cover.duplicate()
	odd["cloak"] = 0.0
	ok(complains(Garments.problems_in(odd, gc_cond, ct, wb, dm), "no armour in"),
		"and a slot Materials has never heard of is refused")

	var missing := gc_cond.duplicate()
	missing.erase("adamant")
	ok(complains(Garments.problems_in(gc_cover, missing, ct, wb, dm), "no conduction"),
		"a metal with no conduction is refused")
	var extra := gc_cond.duplicate()
	extra["unobtanium"] = 1.0
	ok(complains(Garments.problems_in(gc_cover, extra, ct, wb, dm), "does not have"),
		"and a conduction for a metal that does not exist is refused")

	var ember_wrong := gc_cond.duplicate()
	ember_wrong["meteoric"] = 1.4
	ok(complains(Garments.problems_in(gc_cover, ember_wrong, ct, wb, dm), "run cooler"),
		"a metal carrying Ember priced as a cold one is refused")
	var soul_wrong := gc_cond.duplicate()
	soul_wrong["voidsteel"] = 1.4
	ok(complains(Garments.problems_in(gc_cover, soul_wrong, ct, wb, dm), "run cooler"),
		"and so is one carrying Soulfire")
	var frost_wrong := gc_cond.duplicate()
	frost_wrong["cold_iron"] = 0.5
	ok(complains(Garments.problems_in(gc_cover, frost_wrong, ct, wb, dm), "run colder"),
		"a metal carrying Frost priced as a warm one is refused")
	var plain_wrong := gc_cond.duplicate()
	plain_wrong["bronze"] = 1.3
	ok(complains(Garments.problems_in(gc_cover, plain_wrong, ct, wb, dm), "not plain metal"),
		"and a metal with no element that is not plain metal is refused")

	ok(complains(Garments.problems_in(gc_cover, gc_cond, ct, absf(Exposure.WIND_C), dm), "gale"),
		"a windbreak worth the whole gale is refused")
	ok(complains(Garments.problems_in(gc_cover, gc_cond, ct, wb, 1.4), "faster than bare skin"),
		"and a harness that dries you faster than skin is refused")


# =============================================================================
#  cover -- the five slots are not worth the same
# =============================================================================

func _t_cover() -> void:
	claim("cover", 20)

	near_f(Garments.cover({}), 0.0, 1e-9, "nothing on is nothing")
	near_f(Garments.cover(full("steel")), 1.0, 1e-9, "head to toe is a whole body")
	ok(Garments.pieces(full("steel")) == 5, "and it is five pieces")
	ok(Garments.pieces({}) == 0, "and bare is none")

	## THE DRESSING ORDER. The chest is the biggest single thing you can put
	## on and the boots the smallest, which is what makes a part-dressed man
	## a decision rather than a fraction.
	ok(float(Garments.COVER["chest"]) > float(Garments.COVER["pants"]),
		"the chest covers more than the legs")
	ok(float(Garments.COVER["pants"]) > float(Garments.COVER["arms"]),
		"the legs more than the arms")
	ok(float(Garments.COVER["arms"]) > float(Garments.COVER["helmet"]),
		"the arms more than the head")
	ok(float(Garments.COVER["helmet"]) > float(Garments.COVER["shoes"]),
		"and the head more than the feet")
	ok(float(Garments.COVER["chest"]) >= 3.0 * float(Garments.COVER["shoes"]),
		"and a breastplate is worth at least three pairs of boots")

	## The ladder, measured.
	var worn: Dictionary = {}
	for i in range(DRESS_ORDER.size()):
		worn[DRESS_ORDER[i]] = "steel"
		near_f(Garments.cover(worn), MEASURED_COVER[i], 0.005,
			"%d pieces on covers what it measured" % (i + 1))
		near_f(gc(worn, WINTER_STILL_C, 0.0, BREATH_OF_WIND), MEASURED_COVER_WINTER[i], 0.02,
			"%d pieces of steel cost what they measured on the fixture night" % (i + 1))

	## `equipment` carries a sword and an offhand too. Neither is a garment.
	var with_sword := full("steel")
	with_sword["sword"] = "dragonsteel"
	with_sword["offhand"] = "iron"
	near_f(Garments.cover(with_sword), 1.0, 1e-9, "a sword is not a garment")
	ok(Garments.pieces(with_sword) == 5, "and it is not a piece either")
	near_f(gc(with_sword, WINTER_STILL_C, 0.0, BREATH_OF_WIND),
		gc(full("steel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND), 1e-9,
		"and carrying a dragonsteel blade does not warm you")

	## An empty slot is not a piece.
	var half := {"chest": "steel", "helmet": ""}
	ok(Garments.pieces(half) == 1, "an empty slot is not something you are wearing")
	near_f(Garments.cover(half), float(Garments.COVER["chest"]), 1e-9,
		"and it covers nothing")

	## A wardrobe padded out with empty slots is the SAME wardrobe. This is
	## what makes `Player.worn_metals()`'s own guard a second line of defence
	## rather than the only one.
	var padded := {"chest": "steel", "pants": "steel", "arms": "", "helmet": "", "shoes": ""}
	var lean := {"chest": "steel", "pants": "steel"}
	near_f(Garments.cover(padded), Garments.cover(lean), 1e-9,
		"padding a wardrobe with empty slots covers no more of you")
	near_f(gc(padded, WINTER_STILL_C, 0.3, BREATH_OF_WIND),
		gc(lean, WINTER_STILL_C, 0.3, BREATH_OF_WIND), 1e-9,
		"and is worth exactly the same on a winter night")
	ok(Garments.pieces(padded) == Garments.pieces(lean),
		"and is the same number of pieces")


# =============================================================================
#  conduct -- a mean, not a sum
# =============================================================================

func _t_conduct() -> void:
	claim("conduct", 11)

	near_f(Garments.conduct({}), 0.0, 1e-9, "nothing conducts nothing")
	for id: String in ["steel", "cold_iron", "dragonsteel"]:
		near_f(Garments.conduct(full(id)), float(Garments.CONDUCT[id]), 1e-9,
			"a whole set of %s conducts like %s" % [id, id])

	## A MEAN. One dragonsteel boot does not make a man warm, and a single
	## piece of anything conducts like itself however little of you it is on.
	near_f(Garments.conduct({"shoes": "dragonsteel"}),
		float(Garments.CONDUCT["dragonsteel"]), 1e-9,
		"one dragonsteel boot conducts like dragonsteel")
	ok(gc({"shoes": "dragonsteel"}, WINTER_STILL_C, 0.0, BREATH_OF_WIND) < 0.5,
		"but it is worth less than half a degree, because it is one boot")
	ok(gc(full("dragonsteel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
		> 4.0 * gc({"shoes": "dragonsteel"}, WINTER_STILL_C, 0.0, BREATH_OF_WIND),
		"and the whole set is worth more than four boots")

	## Mixed. A dragonsteel breastplate over cold-iron everything else lands
	## between the two, and nearer the cold iron, because there is more of it.
	var mixed := full("cold_iron")
	mixed["chest"] = "dragonsteel"
	var cm := Garments.conduct(mixed)
	ok(cm < float(Garments.CONDUCT["cold_iron"]),
		"a dragonsteel breastplate cools a cold-iron harness")
	ok(cm > float(Garments.CONDUCT["dragonsteel"]),
		"but does not make it dragonsteel")
	near_f(cm, 0.38 * -0.30 + 0.62 * 1.70, 1e-6,
		"and the mean is weighted by how much of the body each piece is on")

	## An unknown metal is plain metal, not a crash.
	near_f(Garments.conduct({"chest": "unobtanium"}), Garments.CONDUCT_BARE, 1e-9,
		"a metal nobody has heard of conducts like plain metal")


# =============================================================================
#  gradient -- and where metal stops mattering
# =============================================================================

func _t_gradient() -> void:
	claim("gradient", 14)

	near_f(Garments.gradient_c(Exposure.WARMTH_NEUTRAL_C), 0.0, 1e-9,
		"at neutral there is no gradient")
	near_f(Garments.gradient_c(Exposure.WARMTH_NEUTRAL_C + 10.0), 0.0, 1e-9,
		"and above it there is still none")
	near_f(Garments.gradient_c(Exposure.WARMTH_NEUTRAL_C - 10.0), 10.0, 1e-9,
		"and below it, it is how far below")

	## THE MOMENT METAL STOPS MATTERING, FOUND RATHER THAN ASSERTED. Sweep
	## down from well above neutral until steel and cold iron first disagree
	## about anything, and demand that the temperature where they part is
	## EXACTLY Exposure's neutral. There is one definition of warm enough in
	## the project and this is what stops a second one appearing.
	var parted := -999.0
	var air := 25.0
	while air > -25.0:
		var d := absf(gc(full("steel"), air, 0.0, BREATH_OF_WIND)
			- gc(full("cold_iron"), air, 0.0, BREATH_OF_WIND))
		if d > 1e-9:
			parted = air
			break
		air -= 0.005
	ok(parted > -900.0, "steel and cold iron do eventually disagree")
	near_f(parted, Exposure.WARMTH_NEUTRAL_C, 0.02,
		"and the temperature they part at is Exposure's neutral, to the hundredth")

	## Above it every metal is the same metal, and the whole set is pure
	## windbreak.
	var summer_vals: Array[float] = []
	for id: String in Materials.ORDER:
		summer_vals.append(gc(full(id), SUMMER_STILL_C, 0.0, BREATH_OF_WIND))
	for i in range(1, summer_vals.size()):
		near_f(summer_vals[i], summer_vals[0], 1e-9,
			"in summer %s is worth exactly what steel is" % Materials.ORDER[i])
	near_f(summer_vals[0], Garments.wind_break(full("steel"), BREATH_OF_WIND), 1e-9,
		"and what a summer harness is worth is its windbreak and nothing else")
	near_f(summer_vals[0], 1.64, 0.01, "which measured 1.64 degrees")


# =============================================================================
#  windbreak -- the half that is always a gift
# =============================================================================

func _t_windbreak() -> void:
	claim("windbreak", 10)

	near_f(Garments.wind_break({}, 1.0), 0.0, 1e-9, "nothing breaks no wind")
	near_f(Garments.wind_break(full("steel"), 0.0), Garments.STILL_C, 1e-9,
		"a full harness in still air is worth its still-air term")
	near_f(Garments.wind_break(full("steel"), 1.0),
		Garments.STILL_C + Garments.WIND_BREAK_C, 1e-9,
		"and in a full gale, both terms")
	ok(Garments.wind_break(full("steel"), 1.0) > 2.0 * Garments.wind_break(full("steel"), 0.0),
		"so a gale more than doubles what being covered is worth")

	## It scales with coverage, because a gale finds a gap.
	var prev := -1.0
	var worn: Dictionary = {}
	for slot: String in DRESS_ORDER:
		worn[slot] = "steel"
		var wb := Garments.wind_break(worn, 1.0)
		ok(wb > prev, "another piece on breaks more of the gale (%s)" % slot)
		prev = wb

	## The metal has nothing to do with it.
	near_f(Garments.wind_break(full("cold_iron"), 0.7),
		Garments.wind_break(full("dragonsteel"), 0.7), 1e-9,
		"and cold iron breaks a wind exactly as well as dragonsteel does")


# =============================================================================
#  crossing -- THE CLAIM OF THE FILE
# =============================================================================

func first_crossing(worn: Dictionary, wind: float) -> float:
	## The still-air temperature at which this set stops being worth wearing,
	## walked down from high summer at a hundredth of a degree. -999 when the
	## set never turns against you at all.
	var air := 30.0
	while air > -60.0:
		if gc(worn, air, 0.0, wind) < 0.0:
			return air
		air -= 0.01
	return -999.0


func _t_crossing() -> void:
	claim("crossing", 12)

	var steel_still := first_crossing(full("steel"), BREATH_OF_WIND)
	var steel_gale := first_crossing(full("steel"), 1.0)
	var iron_still := first_crossing(full("cold_iron"), BREATH_OF_WIND)

	ok(steel_still > -900.0, "a steel harness does turn against you somewhere")
	ok(steel_gale > -900.0, "and so it does in a gale")

	## Measured: +2.35 in a breath of wind. That is an autumn evening, not a
	## winter night and not a summer one -- the crossing has to sit inside
	## the year or the rule is either never on or always on.
	near_f(steel_still, 2.35, 0.05, "and it crosses on an autumn evening")
	ok(steel_still < Exposure.WARMTH_NEUTRAL_C,
		"which is colder than neutral")
	ok(steel_still > WINTER_STILL_C,
		"and warmer than the fixture winter night")

	## THE HEADLINE. A gale moves the crossing at least nine degrees colder:
	## the same harness that costs you three quarters of an hour on a still
	## winter night BUYS you a quarter of one when it is blowing. Measured
	## span 2.35 to -8.00, which is 10.35.
	ok(steel_gale < steel_still - 9.0,
		"and a gale moves the crossing at least nine degrees colder (%.2f to %.2f)"
			% [steel_still, steel_gale])
	near_f(steel_gale, -8.0, 0.05, "landing at eight below")

	## Cold iron crosses WARMEST -- it is a liability first.
	ok(iron_still > steel_still,
		"cold iron turns against you before steel does")
	near_f(iron_still, 6.33, 0.05, "at six and a third degrees")

	## And the warm metals never cross at all, which is what a negative
	## conductor means: it is worth MORE the worse the night gets.
	ok(first_crossing(full("dragonsteel"), BREATH_OF_WIND) < -900.0,
		"dragonsteel never turns against you, at any temperature")
	## Measured: 3.782 at thirty below against 1.640 at neutral, a ratio of
	## 2.31. Stated as a RATIO because that is the form that goes to 1.00 the
	## moment dragonsteel's conduction is zeroed -- at neutral the set is
	## pure windbreak whatever it is made of, so the whole of the difference
	## between these two numbers is the negative conductor doing its work.
	ok(gc(full("dragonsteel"), -30.0, 0.0, BREATH_OF_WIND)
		>= 2.0 * gc(full("dragonsteel"), Exposure.WARMTH_NEUTRAL_C, 0.0, BREATH_OF_WIND),
		"dragonsteel is worth at least twice as much at thirty below as at neutral")
	var ds_rises := true
	var a2 := Exposure.WARMTH_NEUTRAL_C
	var prev_ds := gc(full("dragonsteel"), a2, 0.0, BREATH_OF_WIND)
	while a2 > -40.0:
		a2 -= 0.25
		var now_ds := gc(full("dragonsteel"), a2, 0.0, BREATH_OF_WIND)
		if now_ds < prev_ds - 1e-12:
			ds_rises = false
			break
		prev_ds = now_ds
	ok(ds_rises, "and it is worth more at every step down from neutral to forty below")
	ok(gc(full("cold_iron"), -30.0, 0.0, BREATH_OF_WIND)
		< gc(full("cold_iron"), 0.0, 0.0, BREATH_OF_WIND) - 6.0,
		"while cold iron is at least six degrees worse")


# =============================================================================
#  metals -- the ladder, measured
# =============================================================================

func _t_metals() -> void:
	claim("metals", 20)

	for id in MEASURED_WINTER:
		var mid := String(id)
		near_f(gc(full(mid), WINTER_STILL_C, 0.0, BREATH_OF_WIND),
			float(MEASURED_WINTER[mid]), 0.02,
			"%s on the fixture night is what it measured" % mid)
	for id in MEASURED_GALE:
		var mid2 := String(id)
		near_f(gc(full(mid2), WINTER_STILL_C, 0.0, 1.0), float(MEASURED_GALE[mid2]), 0.02,
			"%s in the gale is what it measured" % mid2)

	## THE ORDER, stated as an order rather than as six numbers: cold iron
	## is the worst thing in the game to wear on a winter night, dragonsteel
	## the best, and plain steel is worse than being naked.
	var order: Array[String] = ["cold_iron", "adamant", "steel", "mithril",
		"meteoric", "dragonsteel"]
	var last := -99.0
	for id: String in order:
		var g := gc(full(id), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
		ok(g > last, "%s is warmer to sleep in than the one before it" % id)
		last = g
	ok(gc(full("steel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND) < -0.5,
		"and plain steel costs more than half a degree, so it is worse than nothing")
	ok(gc(full("cold_iron"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
		< 2.0 * gc(full("steel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND),
		"and cold iron costs more than twice what steel does")
	ok(gc(full("dragonsteel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND) > 2.0,
		"while dragonsteel is worth more than two degrees")

	## The two currencies pull against each other, and that is the design.
	## Cold iron turns MORE than steel and costs more to sleep in.
	ok(Garments.protect(full("cold_iron")) > Garments.protect(full("steel")),
		"cold iron is the better armour")
	ok(gc(full("cold_iron"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
		< gc(full("steel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND),
		"and the worse garment: the two tables disagree on purpose")
	near_f(Garments.protect(full("steel")), 5.0 * Materials.armor_piece_protect("steel"), 1e-9,
		"and protection is read through Materials' own door")


# =============================================================================
#  wet -- what metal does not do
# =============================================================================

func _t_wet() -> void:
	claim("wet", 12)

	for id in MEASURED_SOAKED:
		var mid := String(id)
		near_f(gc(full(mid), WINTER_STILL_C, 1.0, BREATH_OF_WIND),
			float(MEASURED_SOAKED[mid]), 0.02,
			"%s soaked through is what it measured" % mid)

	## Wet metal costs strictly more, by the multiplier and no more.
	var dry_loss := Garments.conduct_c(full("steel"), WINTER_STILL_C, 0.0)
	var wet_loss := Garments.conduct_c(full("steel"), WINTER_STILL_C, 1.0)
	near_f(wet_loss, dry_loss * Garments.WET_CONDUCT_MULT, 1e-9,
		"soaking a harness costs exactly the wet multiplier")
	ok(wet_loss > dry_loss + 0.5,
		"and that is worth at least half a degree on the fixture night")
	near_f(Garments.conduct_c(full("steel"), WINTER_STILL_C, 0.5),
		(dry_loss + wet_loss) * 0.5, 1e-9, "half wet is half way")

	## METAL REFUNDS NONE OF WET_CHILL_C. The whole of the difference that
	## clothing makes to a soaked man is the garment term, so the nine
	## degrees of being wet are untouched by what he is wearing.
	var e_worn := night_env(full("dragonsteel"), 3, BREATH_OF_WIND, false)
	var e_bare := night_env({}, 3, BREATH_OF_WIND, false)
	var d_soaked := Exposure.felt_c(e_worn, 1.0) - Exposure.felt_c(e_bare, 1.0)
	var d_dry := Exposure.felt_c(e_worn, 0.0) - Exposure.felt_c(e_bare, 0.0)
	near_f(d_soaked, Exposure.garment_c(e_worn, 1.0), 1e-9,
		"clothing changes a soaked man's felt temperature by the garment term alone")
	ok(d_soaked > d_dry,
		"and dragonsteel is worth MORE when you are wet, because wet is colder")
	ok(Exposure.felt_c(e_worn, 1.0) < Exposure.felt_c(e_worn, 0.0) - 8.0,
		"but the best armour in the game still leaves eight degrees of soaking on you")

	## A gale on wet skin stays the worst thing in the game, harness or not.
	var gale_worn := night_env(full("dragonsteel"), 3, 1.0, false)
	ok(Exposure.felt_c(gale_worn, 1.0) < Exposure.felt_c(e_worn, 1.0),
		"soaked in a gale is worse than soaked out of it, in the best set there is")


# =============================================================================
#  drying -- metal does not breathe
# =============================================================================

func _t_drying() -> void:
	claim("drying", 8)

	near_f(Garments.dry_mult({}), 1.0, 1e-9, "bare skin dries at its own rate")
	near_f(Garments.dry_mult(full("steel")), Garments.DRY_MULT_FULL, 1e-9,
		"and a full harness at the harness rate")
	ok(Garments.dry_mult({"chest": "steel"}) < 1.0,
		"a breastplate alone already slows it")
	ok(Garments.dry_mult({"chest": "steel"}) > Garments.DRY_MULT_FULL,
		"but not as much as the whole kit")

	## Through Exposure's REAL door, at a fire, which is where a wet man goes.
	var at_fire := Exposure.env({"season": 3, "hour": 21.0, "fire_c": 14.0})
	var at_fire_plate := Exposure.env({"season": 3, "hour": 21.0, "fire_c": 14.0,
		"worn": full("steel")})
	near_f(Exposure.wet_rate(at_fire, 0.8), MEASURED_DRY_BARE, 1e-5,
		"bare at a fire dries at what it measured")
	near_f(Exposure.wet_rate(at_fire_plate, 0.8), MEASURED_DRY_PLATE, 1e-5,
		"in plate at the same fire, slower, by what it measured")
	ok(absf(Exposure.wet_rate(at_fire_plate, 0.8)) < absf(Exposure.wet_rate(at_fire, 0.8)) - 0.01,
		"so the fire is working against his own harness by a hundredth a second")

	## And it does not touch getting wet, only getting dry.
	var rain := Exposure.env({"season": 0, "level": 3, "intensity": 0.9, "worn": full("steel")})
	var rain_bare := Exposure.env({"season": 0, "level": 3, "intensity": 0.9})
	near_f(Exposure.wet_rate(rain, 0.2), Exposure.wet_rate(rain_bare, 0.2), 1e-9,
		"plate does not keep the rain off")


# =============================================================================
#  dress -- the trade, and the season deciding it
# =============================================================================

func mixed_pack() -> Array:
	var pack: Array = []
	for slot: String in Materials.ARMOR_SLOTS:
		for m: String in ["steel", "cold_iron"]:
			pack.append({"slot": slot, "material": m,
				"name": Materials.armor_piece_name(m, slot), "count": 1})
	return pack


func _t_dress() -> void:
	claim("dress", 15)

	var pack := mixed_pack()

	## STEEL BELOW, COLD IRON ABOVE -- one function, two answers, and the
	## season decides which. Cold iron is the better armour (tier 1 against
	## tier 0) and the worse garment, so it only ever comes out when the
	## garment question has no answer.
	var cold_set := Garments.dress(pack, WINTER_STILL_C, 0.0, BREATH_OF_WIND)
	var warm_set := Garments.dress(pack, SUMMER_STILL_C, 0.0, BREATH_OF_WIND)
	ok(Garments.pieces(cold_set) == 5, "a full pack dresses you head to toe in winter")
	ok(Garments.pieces(warm_set) == 5, "and in summer")
	for slot: String in Materials.ARMOR_SLOTS:
		ok(String(cold_set.get(slot, "")) == "steel",
			"in winter the %s is steel, because cold iron would cost him the night" % slot)
	ok(String(warm_set.get("chest", "")) == "cold_iron",
		"in summer it is cold iron, because nothing conducts and the tiebreak is armour")
	ok(Garments.protect(warm_set) > Garments.protect(cold_set),
		"so the summer set turns more than the winter one")

	## THE SWITCH-OVER IS FOUND, NOT ASSERTED, and it is Exposure's neutral.
	var switch := -999.0
	var air := 25.0
	while air > -25.0:
		if String(Garments.dress(pack, air, 0.0, BREATH_OF_WIND).get("chest", "")) != "cold_iron":
			switch = air
			break
		air -= 0.005
	ok(switch > -900.0, "there is a temperature at which he changes his mind")
	near_f(switch, Exposure.WARMTH_NEUTRAL_C - 0.005, 0.02,
		"and it is the moment the gradient opens, to the hundredth")

	## Properties rather than numbers: the set it hands back is at least as
	## warm as any single-metal set the same pack could make.
	for m: String in ["steel", "cold_iron"]:
		ok(gc(cold_set, WINTER_STILL_C, 0.0, BREATH_OF_WIND)
			>= gc(full(m), WINTER_STILL_C, 0.0, BREATH_OF_WIND) - 1e-9,
			"the winter set is at least as warm as a whole kit of %s" % m)

	## Rubbish in the pack is ignored rather than crashed on.
	ok(Garments.dress([], WINTER_STILL_C, 0.0, 0.2).is_empty(),
		"an empty pack dresses nobody")
	var junk: Array = [{"name": "Waterskin", "weight": 2.0},
		{"slot": "sword", "material": "dragonsteel"}, "a string", 7]
	ok(Garments.dress(junk, WINTER_STILL_C, 0.0, 0.2).is_empty(),
		"and neither a waterskin nor a sword is something you can put on")


# =============================================================================
#  exposure -- the REAL front door
# =============================================================================

func _t_exposure() -> void:
	claim("exposure", 19)

	## Nothing changed for anybody who does not dress. THE REGRESSION TEST
	## for the whole wiring: an env with no `worn` key behaves exactly as it
	## did before this file existed.
	var bare := night_env({}, 3, BREATH_OF_WIND, false)
	near_f(Exposure.garment_c(bare, 0.0), 0.0, 1e-9, "an unclothed man pays nothing")
	near_f(Exposure.felt_c(bare, 0.0), Exposure.ambient_c(bare), 1e-9,
		"and his felt temperature is still the air")
	near_f(Exposure.ambient_c(bare), WINTER_AMBIENT_C, 0.02,
		"which is what the fixture night measured")

	## felt = ambient + garment, exactly, and the garment term is the only
	## thing clothing touches.
	for id: String in ["steel", "cold_iron", "dragonsteel"]:
		var e := night_env(full(id), 3, BREATH_OF_WIND, false)
		near_f(Exposure.felt_c(e, 0.0) - Exposure.felt_c(bare, 0.0),
			Exposure.garment_c(e, 0.0), 1e-9,
			"%s changes the felt temperature by its garment term and nothing else" % id)
		near_f(Exposure.ambient_c(e), Exposure.ambient_c(bare), 1e-9,
			"and does not change the air" )

	## `still_air_c` is the air with the wind's own chill taken back out.
	for w: float in [0.0, 0.3, 1.0]:
		var ew := Exposure.env({"season": 3, "hour": 21.0, "wind": w})
		near_f(Exposure.still_air_c(ew), WINTER_STILL_C, 0.02,
			"the air a harness sits in does not change with the wind (%.1f)" % w)
	var shel := Exposure.env({"season": 3, "hour": 21.0, "wind": 1.0, "sheltered": true})
	near_f(Exposure.still_air_c(shel), Exposure.ambient_c(shel), 1e-9,
		"and under a roof there is no wind term to take out")

	## ⚠ AND A ROOF MUST NOT BE PAID FOR TWICE. `Exposure` already zeroes the
	## wind under shelter, so a harness that still claimed its windbreak in
	## there would be refunding a draught the roof has already stopped. The
	## mutation sweep found this hole: nothing asserted the roofed-and-windy
	## case at all.
	var roof_gale := Exposure.env({"season": 3, "hour": 21.0, "wind": 1.0,
		"sheltered": true, "worn": full("steel")})
	var roof_still := Exposure.env({"season": 3, "hour": 21.0, "wind": 0.0,
		"sheltered": true, "worn": full("steel")})
	near_f(Exposure.garment_c(roof_gale, 0.0), Exposure.garment_c(roof_still, 0.0), 1e-9,
		"under a roof a harness is worth the same whatever it is doing outside")
	near_f(Exposure.garment_c(roof_still, 0.0),
		Garments.garment_c(full("steel"), Exposure.still_air_c(roof_still), 0.0, 0.0), 1e-9,
		"because the wind it is handed is zero, not the weather's")
	var open_gale := Exposure.env({"season": 3, "hour": 21.0, "wind": 1.0,
		"worn": full("steel")})
	ok(Exposure.garment_c(open_gale, 0.0) > Exposure.garment_c(roof_gale, 0.0),
		"and the harness is worth MORE out in the gale than under the roof, which is the point of it")

	## The vocabulary. A misspelt key would otherwise read as a default and
	## quietly undress you.
	ok(Exposure.DEFAULTS.has("worn"), "`worn` is part of the shared vocabulary")
	ok(Exposure.DEFAULTS.has("base_c"), "and so is `base_c`")
	ok(Exposure.unknown_env_keys({"worn": {}, "base_c": 0.0}).is_empty(),
		"and a caller passing both is not told off")
	ok(Exposure.unknown_env_keys({"wornn": {}}).size() == 1,
		"while a misspelt one still is")

	## env() DEEP-copies, so two environments do not share one wardrobe.
	var a := Exposure.env({})
	var wa: Dictionary = a["worn"]
	wa["chest"] = "steel"
	var b := Exposure.env({})
	var wb: Dictionary = b["worn"]
	ok(wb.is_empty(), "dressing one environment does not dress every other one")

	## And the caller's dictionary is not mutated by being read.
	var mine := full("steel")
	var e2 := night_env(mine, 3, BREATH_OF_WIND, false)
	var _ignored := Exposure.felt_c(e2, 0.4)
	ok(Garments.pieces(mine) == 5, "and asking what a set is worth does not take it off")


# =============================================================================
#  place -- Seasons.base_c_at finally has a caller
# =============================================================================

func _t_place() -> void:
	claim("place", 14)

	## NAN means "use the shared table", which is what every existing caller
	## gets and why nothing regressed.
	var shared := Exposure.env({"season": 3, "hour": 4.0})
	near_f(Exposure.ambient_c(shared),
		Exposure.SEASON_BASE_C[3] + Exposure.hour_curve_c(4.0)
			+ Exposure.lapse_c(Exposure.LAPSE_BASE_Y), 1e-9,
		"with no local answer the season table decides")

	## And a number replaces the table's season term outright, leaving every
	## other term standing.
	var local := Exposure.env({"season": 3, "hour": 4.0, "base_c": -1.0})
	near_f(Exposure.ambient_c(local) - Exposure.ambient_c(shared),
		-1.0 - Exposure.SEASON_BASE_C[3], 1e-9,
		"and a local answer moves the air by exactly its difference from the table")
	var windy := Exposure.env({"season": 3, "hour": 4.0, "base_c": -1.0, "wind": 1.0})
	near_f(Exposure.ambient_c(windy) - Exposure.ambient_c(local), Exposure.WIND_C, 1e-9,
		"the wind still bites on top of it")
	var high := Exposure.env({"season": 3, "hour": 4.0, "base_c": -1.0, "y": 900.0})
	ok(Exposure.ambient_c(high) < Exposure.ambient_c(local) - 4.0,
		"and the lapse rate still owns what altitude does to the DAY")

	## THE REAL FRONT DOOR of Seasons, at the two places the year disagrees
	## about most. Measured on day 66: Aroostook is in winter and the shared
	## calendar has not finished autumn, twelve degrees apart.
	var bc_a := Seasons.base_c_at(66.0, AROOSTOOK)
	var bc_c := Seasons.base_c_at(66.0, CASCO_BAY)
	ok(bc_a < bc_c, "on day 66 Aroostook's year is colder than Casco Bay's")
	var e_local := Exposure.env({"season": Exposure.season_for_day(66.0), "hour": 4.0,
		"y": AROOSTOOK.y, "base_c": bc_a})
	var e_shared := Exposure.env({"season": Exposure.season_for_day(66.0), "hour": 4.0,
		"y": AROOSTOOK.y})
	near_f(Exposure.ambient_c(e_local), MEASURED_AROOSTOOK_66_LOCAL, 0.05,
		"an Aroostook night on day 66 is what it measured")
	near_f(Exposure.ambient_c(e_shared), MEASURED_AROOSTOOK_66_SHARED, 0.05,
		"and the shared calendar says what it said before, which is why this matters")
	ok(Exposure.ambient_c(e_local) < Exposure.ambient_c(e_shared) - 11.0,
		"eleven degrees of difference the old table could not see")

	## And it is a place, not a shift: both places are walked through a year
	## and the north is never the warmer of the two at four in the morning.
	##
	## ⚠ AND THE MODEL WAS RIGHT WHERE THE FIRST ASSERTION WAS WRONG. This
	## began as "Aroostook is never the warmer of the two, on any day", which
	## is what a colder place ought to mean -- and it went red on FOUR of 192
	## samples. The warp is a PHASE shift as well as an amplitude one, so at
	## the very tail of winter the north is already past its coldest point
	## while the south is still descending, and it leads by a sixth of a
	## degree for two days. That is the warp working, not a defect, so what
	## is asserted is the real shape: colder on all but a handful of days,
	## nearly three degrees colder on the year, and never AHEAD by more than
	## a quarter of a degree when it does lead.
	var north_colder := 0
	var samples := 0
	var worst_inversion := 0.0
	var mean_north := 0.0
	var mean_south := 0.0
	var day := 0.0
	while day < 96.0:
		var na := Seasons.base_c_at(day, AROOSTOOK)
		var ca := Seasons.base_c_at(day, CASCO_BAY)
		samples += 1
		mean_north += na
		mean_south += ca
		if na <= ca + 1e-9:
			north_colder += 1
		else:
			worst_inversion = maxf(worst_inversion, na - ca)
		day += 0.5
	ok(samples == 192, "a whole year walked at half a day (%d)" % samples)
	ok(north_colder >= 185,
		"and Aroostook is the colder of the two on all but a handful of days (%d of %d)"
			% [north_colder, samples])
	ok(worst_inversion <= 0.25,
		"and where it does lead, it leads by under a quarter of a degree (%.3f)"
			% worst_inversion)
	ok(mean_south / float(samples) - mean_north / float(samples) >= 2.5,
		"and over the year it is two and a half degrees colder (%.2f)"
			% (mean_south / float(samples) - mean_north / float(samples)))

	## Through a whole night, with clothing, at both places: the same man in
	## the same set sleeps longer in the south.
	var worn := full("steel")
	var north := Exposure.env({"season": Exposure.season_for_day(66.0), "hour": 21.0,
		"y": AROOSTOOK.y, "base_c": Seasons.base_c_at(66.0, AROOSTOOK), "worn": worn})
	var south := Exposure.env({"season": Exposure.season_for_day(66.0), "hour": 21.0,
		"y": CASCO_BAY.y, "base_c": Seasons.base_c_at(66.0, CASCO_BAY), "worn": worn})
	var rn: Dictionary = Slumber.night(north, Exposure.WARMTH_MAX, 0.0, 10.0, 0.0, 0.0)
	var rs: Dictionary = Slumber.night(south, Exposure.WARMTH_MAX, 0.0, 10.0, 0.0, 0.0)
	ok(float(rn["hours_slept"]) < float(rs["hours_slept"]),
		"and the same night in the same harness is shorter in the north")
	ok(String(rn["woke"]) == Slumber.WOKE_COLD, "the northern man is woken by the cold")
	ok(String(rs["woke"]) == Slumber.WOKE_DAWN, "and the southern one sleeps until dawn")


# =============================================================================
#  slumber -- the real night walk, and the reason this is a game rule
# =============================================================================

func _t_slumber() -> void:
	claim("slumber", 26)

	## SEVEN SETS, SEVEN WAKINGS, on the fixture night. Every one of these
	## numbers came out of the real `Slumber.night`, walking the real
	## `Exposure` model a quarter of a game hour at a time.
	for id in MEASURED_SLEPT:
		var mid := String(id)
		var worn: Dictionary = {} if mid == "naked" else full(mid)
		var r := slept(worn, 3, BREATH_OF_WIND, 0.0, false)
		near_f(float(r["hours_slept"]), float(MEASURED_SLEPT[mid]), 0.26,
			"%s sleeps what it measured" % mid)

	## THE SPREAD. Three and a quarter hours of one night decided by nothing
	## but what is on his back.
	var worst := float(slept(full("cold_iron"), 3, BREATH_OF_WIND, 0.0, false)["hours_slept"])
	var best := float(slept(full("dragonsteel"), 3, BREATH_OF_WIND, 0.0, false)["hours_slept"])
	ok(best - worst >= 3.0,
		"three hours of sleep between the best set and the worst (%.2f to %.2f)" % [worst, best])

	## AND THE LINE THAT MAKES IT A RULE RATHER THAN A BONUS: the man in
	## plain steel sleeps LESS than the naked one.
	var bare_h := float(slept({}, 3, BREATH_OF_WIND, 0.0, false)["hours_slept"])
	var steel_h := float(slept(full("steel"), 3, BREATH_OF_WIND, 0.0, false)["hours_slept"])
	ok(steel_h <= bare_h - 0.5,
		"a man who sleeps in his steel loses at least half an hour by it")
	ok(worst <= bare_h - 1.5, "and in cold iron, at least an hour and a half")
	ok(best >= bare_h + 1.0, "while dragonsteel buys him an hour")

	## THE GALE TURNS IT ROUND. Same harness, same season, more wind, and
	## now the steel is worth wearing.
	for id in MEASURED_SLEPT_GALE:
		var gid := String(id)
		var gworn: Dictionary = {} if gid == "naked" else full(gid)
		near_f(float(slept(gworn, 3, 1.0, 0.0, false)["hours_slept"]),
			float(MEASURED_SLEPT_GALE[gid]), 0.26, "%s in a gale sleeps what it measured" % gid)
	var gale_bare := float(slept({}, 3, 1.0, 0.0, false)["hours_slept"])
	var gale_steel := float(slept(full("steel"), 3, 1.0, 0.0, false)["hours_slept"])
	ok(gale_steel >= gale_bare, "in a gale the steel harness is worth wearing")
	ok((steel_h - bare_h) < (gale_steel - gale_bare),
		"and the wind is what changed its mind, not the cold")

	## SOAKED. The wet multiplier, through a whole night.
	for id in MEASURED_SLEPT_SOAKED:
		var sid := String(id)
		var sworn: Dictionary = {} if sid == "naked" else full(sid)
		near_f(float(slept(sworn, 3, BREATH_OF_WIND, 1.0, false)["hours_slept"]),
			float(MEASURED_SLEPT_SOAKED[sid]), 0.26,
			"%s soaked sleeps what it measured" % sid)
	ok(float(slept(full("cold_iron"), 3, BREATH_OF_WIND, 1.0, false)["hours_slept"])
		<= float(slept({}, 3, BREATH_OF_WIND, 1.0, false)["hours_slept"]) - 1.5,
		"soaked in cold iron costs an hour and a half over being soaked in nothing")

	## THE END-GAME REWARD, and it is the ONLY set that gets it: a roof and
	## no fire at all, and dragonsteel sleeps the winter night through. The
	## suite SEARCHES for which sets manage it rather than asserting one.
	var through: Array[String] = []
	for id: String in Materials.ORDER:
		var r2 := slept(full(id), 3, BREATH_OF_WIND, 0.0, true)
		if String(r2["woke"]) == Slumber.WOKE_DAWN:
			through.append(id)
	## ⚠ The first draft of this asserted ONE metal and found TWO. Voidsteel
	## carries Soulfire and runs warm as well, which is not an accident of
	## the numbers: what the search actually finds is that the metals which
	## sleep a roofed winter night through are EXACTLY the end-game tier,
	## and that is a better claim than the one that was written down.
	ok(through.size() == 2, "exactly two metals sleep a roofed winter night through (%s)"
		% str(through))
	for id2: String in through:
		ok(int(Materials.get_mat(id2)["tier"]) == 3,
			"%s is an end-game metal" % id2)
	for id3: String in Materials.ORDER:
		if int(Materials.get_mat(id3)["tier"]) == 3:
			ok(through.has(id3), "and every end-game metal manages it (%s)" % id3)
	ok(String(slept({}, 3, BREATH_OF_WIND, 0.0, true)["woke"]) == Slumber.WOKE_COLD,
		"a roof alone does not, which is what Slumber measured before this landed")

	## A WINTER RULE, NOT A TAX ON ORDINARY PLAY. In autumn every set in the
	## game sleeps the night through, cold iron included.
	var autumn_cold := 0
	for id: String in Materials.ORDER:
		var r3 := slept(full(id), 2, BREATH_OF_WIND, 0.0, false)
		if String(r3["woke"]) != Slumber.WOKE_DAWN:
			autumn_cold += 1
	ok(autumn_cold == 0, "no set of armour in the game costs you an autumn night")
	ok(String(slept(full("cold_iron"), 1, BREATH_OF_WIND, 0.0, false)["woke"])
		== Slumber.WOKE_DAWN, "nor a summer one")

	## And the night is still never fatal, whatever he wore to bed.
	for id: String in ["cold_iron", "adamant"]:
		var r4 := slept(full(id), 3, 1.0, 1.0, false)
		ok(float(r4["warmth"]) > 0.0, "%s at its worst still wakes him alive" % id)


# =============================================================================
#  readout -- both of these defects were found by LOOKING at the game
# =============================================================================

func _t_readout() -> void:
	claim("readout", 10)

	## A green suite says nothing about the shape of the thing on screen.
	## Both assertions below exist because the running game put the wrong
	## words in front of a player and no pure function could see it.
	var warm := Garments.readout(full("dragonsteel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
	var cold := Garments.readout(full("steel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
	ok(not warm.contains("--"),
		"a warm metal's readout does not print a double minus: %s" % warm)
	ok(warm.contains("metal +"), "it shows the metal GIVING heat back")
	ok(cold.contains("metal -"), "and a plain harness TAKING it")
	ok(warm.contains(Garments.describe(full("dragonsteel"))), "and it names the set")
	ok(warm.contains("%+.1f" % Garments.garment_c(full("dragonsteel"),
		WINTER_STILL_C, 0.0, BREATH_OF_WIND)), "and carries the net it agrees with")

	## THE VERDICT MUST NOT OVERSELL A SUMMER EVENING. Above neutral there is
	## no gradient, so warmth comes back whatever is on your back, and a full
	## harness scoring its whole windbreak used to be announced as being
	## worth more than a fire.
	var summer_words: Array[String] = []
	for id: String in Materials.ORDER:
		var v := Garments.verdict(full(id), SUMMER_STILL_C, 0.0, BREATH_OF_WIND)
		if not summer_words.has(v):
			summer_words.append(v)
	ok(summer_words.size() == 1,
		"every metal gets the same verdict in summer (%s)" % str(summer_words))
	ok(summer_words[0] != Garments.verdict(full("dragonsteel"), WINTER_STILL_C, 0.0,
		BREATH_OF_WIND), "and it is not the one a winter harness earns")
	ok(Garments.verdict({}, WINTER_STILL_C, 0.0, BREATH_OF_WIND) == "unclothed",
		"a naked man is told so")
	ok(Garments.verdict(full("cold_iron"), WINTER_STILL_C, 0.0, BREATH_OF_WIND)
		!= Garments.verdict(full("dragonsteel"), WINTER_STILL_C, 0.0, BREATH_OF_WIND),
		"and the best and worst sets in the game are not described the same way")
	ok(Garments.verdict(full("steel"), Exposure.WARMTH_NEUTRAL_C - 0.01, 0.0, BREATH_OF_WIND)
		!= summer_words[0],
		"and a hundredth of a degree below neutral is already a different answer")


# =============================================================================
#  sources -- the call sites, through a comment stripper
# =============================================================================

func _t_sources() -> void:
	claim("sources", 22)

	var g_raw := FileAccess.get_file_as_string("res://scripts/Garments.gd")
	var e_raw := FileAccess.get_file_as_string("res://scripts/Exposure.gd")
	var p_raw := FileAccess.get_file_as_string("res://scripts/Player.gd")
	ok(g_raw.length() > 4000, "Garments.gd read back (%d bytes)" % g_raw.length())
	ok(e_raw.length() > 4000, "Exposure.gd read back (%d bytes)" % e_raw.length())
	ok(p_raw.length() > 4000, "Player.gd read back (%d bytes)" % p_raw.length())

	var g := _code_only(g_raw)
	var e := _code_only(e_raw)
	var p := _code_only(p_raw)

	## The stripper works, proved on planted text built by CONCATENATION so
	## the fixture cannot trip the very scan it is proving.
	var planted := "var x = 1  " + "# " + "randi" + "() in a comment\n" \
		+ "\t" + "# " + "randi" + "() on its own line\n" \
		+ "pass  " + "# " + "_feed" + "()\n"
	ok(planted.contains("randi"), "the planted text has the word in it")
	ok(not _code_only(planted).contains("randi"),
		"and the stripper takes it out of both a trailing and a whole-line comment")
	ok(not _code_only(planted).contains("_feed"),
		"including a call switched off behind a `pass`")

	## Garments is pure. No RNG, no tree, no clock, no frames.
	for bad: String in ["RandomNumberGenerator", "randf", "randi", "get_tree",
			"await", "_process", "Time.", "DayNight", "Wind."]:
		ok(not g.contains(bad), "Garments never reaches for %s" % bad)
	ok(not g.contains("func _input") and not g.contains("func _unhandled_input"),
		"and it declares no input handler, so it claims no key")
	ok(g.contains("static func garment_c"), "and the door is a static function")

	## THE CALL SITES. A method nobody calls is not a feature.
	ok(e.contains("f += garment_c(e, wet_v)"),
		"Exposure.felt_c adds the garment term")
	ok(e.contains("Garments.garment_c(worn, still_air_c(e)"),
		"and it goes through Garments with the STILL air, not the windy one")
	ok(e.contains("dry *= Garments.dry_mult("),
		"Exposure.wet_rate slows drying by the harness")
	ok(e.contains("if not is_nan(local):") and e.contains("c = local"),
		"Exposure.ambient_c honours a local base temperature when it is given one")
	ok(p.contains("\"worn\": worn_metals(),"),
		"Player publishes what is actually on the body")
	ok(p.contains("\"base_c\": Seasons.base_c_at("),
		"and where the body is standing")
	ok(p.contains("func worn_metals() -> Dictionary:"),
		"and worn_metals exists to be called")
	## ⚠ IN CONTEXT, NOT BY NAME. The first version of this asserted the bare
	## string `_garment_note()`, which the function's own DEFINITION line
	## satisfies -- so deleting the call walked straight through it. The same
	## shape that has cost this project four rounds in comments cost it one
	## more in a signature.
	ok(p.contains("\t_garment_note()\n\t_refresh_inventory_ui()"),
		"and putting a set on says what it is worth tonight")
	ok(p.contains("func _garment_note() -> void:"),
		"and there is something there to call")
	ok(p.contains("\t\tif m != \"\":\n\t\t\tw[slot] = m"),
		"and an empty slot is never published as something you are wearing")

	## Exposure reads `worn` in exactly one place, so there is one door.
	var doors := e.count("e.get(\"worn\"")
	ok(doors == 2, "Exposure reads the wardrobe in two places and no more (%d)" % doors)


# =============================================================================
#  determinism
# =============================================================================

func _signature() -> String:
	var sig := ""
	for id: String in Materials.ORDER:
		for air: float in [-20.0, -4.0, 2.0, 12.0, 25.0]:
			for wet: float in [0.0, 0.5, 1.0]:
				for wind: float in [0.0, 0.4, 1.0]:
					sig += "%.9f|" % gc(full(id), air, wet, wind)
	return sig


func _t_determinism() -> void:
	claim("determinism", 6)

	var a := _signature()
	var b := _signature()
	ok(a == b, "the same question twice gives the same answer, to nine places")
	ok(a.length() > 3000, "and the signature is long enough to carry the whole table")

	## The signature carries the variables the file is actually about -- a
	## signature that cannot see the variable cannot see the bug.
	ok("%.9f" % gc(full("cold_iron"), -4.0, 0.0, 0.2)
		!= "%.9f" % gc(full("dragonsteel"), -4.0, 0.0, 0.2),
		"two different metals do not hash the same")
	ok("%.9f" % gc(full("steel"), -4.0, 0.0, 0.2) != "%.9f" % gc(full("steel"), -4.0, 1.0, 0.2),
		"nor dry and soaked")
	ok("%.9f" % gc(full("steel"), -4.0, 0.0, 0.2) != "%.9f" % gc(full("steel"), -4.0, 0.0, 1.0),
		"nor still and blowing")
	ok("%.9f" % gc(full("steel"), -20.0, 0.0, 0.2) != "%.9f" % gc(full("steel"), -4.0, 0.0, 0.2),
		"nor two different nights")


# =============================================================================

func _init() -> void:
	_t_tables()
	_t_cover()
	_t_conduct()
	_t_gradient()
	_t_windbreak()
	_t_crossing()
	_t_metals()
	_t_wet()
	_t_drying()
	_t_dress()
	_t_exposure()
	_t_place()
	_t_slumber()
	_t_readout()
	_t_sources()
	_t_determinism()

	var short: Array = []
	for s in _claims:
		if int(_counts.get(s, 0)) < int(_claims[s]):
			short.append("%s %d/%d" % [s, int(_counts.get(s, 0)), int(_claims[s])])
	if not short.is_empty():
		_fail += 1
		print("  FAIL  [claims] sections that never finished: %s" % ", ".join(PackedStringArray(short)))
	if _pass + _fail < MIN_ASSERTIONS:
		_fail += 1
		print("  FAIL  [floor] only %d assertions ran, floor is %d" % [_pass + _fail, MIN_ASSERTIONS])

	if _fail == 0:
		print("ALL GREEN -- %d assertions" % _pass)
	else:
		print("%d passed, %d FAILED" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
