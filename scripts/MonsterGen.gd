class_name MonsterGen
extends RefCounted
## ===========================================================================
## MONSTER GEN — the random monster generator.
##
## Lemon (2026-09-14): "scrap the current humanoid mobs for ... a monster
## random generator spawner, to make unique mobs at each level" — where a
## level is BOTH the player's level tier AND the zone of the map they are
## standing in. So every zone of the Maine map (a WorldPlan zone if one is
## painted there, else the wilderness in 1 km cells) owns its own little
## bestiary, seeded by the zone; and every level tier the player climbs adds
## a newcomer to each zone's roster and turns the whole roster meaner. Two
## players standing in the same meadow at the same level meet the same
## species; walk a kilometre and the species change; level up and something
## new starts hunting there.
##
## A SPECIES is a genome (a Dictionary — see roll_species) that Monster.gd
## reads to build a body out of the same box rig + CreatureSkin PSX bake as
## every other creature in the game, and to pick its fighting style out of
## Enemy's own toolbox (melee loop, telegraphed strong attacks, duelist
## pacing, nerve and rout). The body grammar:
##
##   plan       biped | quadruped | hexapod | serpent
##   head       blunt | snout | skull | maw | crest | eyeless
##   horns      0..3, eyes 0..6, tail  "" | whip | club | stinger
##   plates     dorsal armour boxes, spines  a ridge of thorns
##   arms       (bipeds) none | claws | club | blade
##   tile       hide | scale | chitin | bone | fur | skin | stone
##
## and an ABILITY KIT rolled by tier: burn / poison / chill / shock / tar on
## the touch (through Afflictions.gd, same as the slimes), plus passives —
## regen, armored, thick_hide, quick, howl (wakes its pack), thorns (a sword
## that lands pays a little back), frenzy (harder when hurt). The SPECIAL is
## the telegraphed strong attack: lunge (guard-break leap), charge (throws
## you aside and barrels past), slam (hurls you back), flurry (three fast
## hits), or none.
##
## Everything here is static and pure: (seed, zone key, tier) in, genomes
## out, the same every time. Nothing in this file touches the scene tree.
## ===========================================================================

const PLANS := ["biped", "quadruped", "hexapod", "serpent"]
const HEADS := ["blunt", "snout", "skull", "maw", "crest", "eyeless"]
const TAILS := ["", "whip", "club", "stinger"]
const ARMS := ["none", "claws", "club", "blade"]
const TILES := ["hide", "scale", "chitin", "bone", "fur", "skin", "stone", "fur_long"]
const SPECIALS := ["", "lunge", "charge", "slam", "flurry"]
## The touch (on-hit afflictions) and the passives, in one kit.
const TOUCHES := ["burn", "poison", "chill", "shock", "tar"]
const PASSIVES := ["regen", "armored", "thick_hide", "quick", "howl", "thorns", "frenzy"]
const ABILITIES := TOUCHES + PASSIVES

## Level tiers: the player's level folded into five bands.
const TIER_LEVELS := [1, 4, 8, 13, 20]   ## tier i begins at this level
const MAX_TIER := 4
## How many species a zone knows at a tier: the natives + one newcomer per tier.
const NATIVES := 2
const WILD_CELL := 1000.0                ## m — the wilderness rolls per cell

## Name banks: a growl, a hiss, a click and a moan — the plan picks the bank,
## the epithet says what it does to you.
const SYL_GROWL := ["gr", "kr", "vr", "dr", "br", "thr", "ur", "ar", "or", "ak", "ok", "usk", "ash", "ug", "rag", "mor"]
const SYL_HISS := ["ss", "sh", "zs", "is", "es", "ith", "yss", "as", "sil", "vis", "esh", "ish"]
const SYL_CLICK := ["k", "tk", "ch", "ik", "ek", "tik", "kak", "chit", "kri", "tch", "ik"]
const SYL_MOAN := ["mo", "ho", "wo", "oo", "um", "ol", "hol", "mur", "nor", "ul", "oth", "hom"]
const EPITHETS := {
	"biped": ["Stalker", "Raider", "Skulker", "Warden", "Butcher", "Prowler", "Reaver", "Gaunt"],
	"quadruped": ["Hound", "Beast", "Stag", "Boar", "Crawler", "Lurker", "Brute", "Runner"],
	"hexapod": ["Skitter", "Weaver", "Creeper", "Mite", "Scuttler", "Nester", "Tick", "Spinner"],
	"serpent": ["Wyrm", "Coil", "Serpent", "Lash", "Worm", "Slither", "Adder", "Eel"],
}
const TOUCH_WORDS := {"burn": "Ember", "poison": "Venom", "chill": "Rime", "shock": "Jolt", "tar": "Tar"}


## ------------------------------------------------------------- tiers ------

static func tier_for_level(level: int) -> int:
	var t := 0
	for i in range(TIER_LEVELS.size()):
		if level >= int(TIER_LEVELS[i]):
			t = i
	return clampi(t, 0, MAX_TIER)


static func tier_name(tier: int) -> String:
	return ["Low", "Common", "Hardened", "Dire", "Apex"][clampi(tier, 0, MAX_TIER)]


## ------------------------------------------------------------- zones ------

static func zone_key(pos: Vector3) -> String:
	## The key a spot on the map rolls its bestiary from. A painted WorldPlan
	## zone (a forest, a moor, a ruin) wins — the smallest one containing the
	## point, WorldPlan's own rule — else the wilderness by region and 1 km
	## cell, so the deep woods north of the river are not the deep woods
	## south of it. No map at all (a lab, a test): one wild cell.
	var z: Dictionary = WorldPlan.zone_at(pos.x, pos.z)
	if not z.is_empty():
		var nm := str(z.get("name", ""))
		var kind := str(z.get("kind", "zone"))
		if nm == "":
			nm = "%s@%d,%d" % [kind, int(floor(WorldPlan.center_of(z).x)), int(floor(WorldPlan.center_of(z).y))]
		return "zone:%s:%s" % [kind, nm]
	var region := "wild"
	if Overworld.inst != null and Overworld.inst._loaded:
		region = Overworld.inst.region_for(pos.x, pos.z)
	var cx := int(floor(pos.x / WILD_CELL))
	var cz := int(floor(pos.z / WILD_CELL))
	return "wild:%s:%d,%d" % [region, cx, cz]


static func cave_key(cave_pos: Vector3, depth_y: float) -> String:
	## A cave rolls its own: one bestiary per cave, one band per depth —
	## shallow / middle / deep — so the galleries get meaner as you go down.
	var band := "shallow" if depth_y > -12.0 else ("middle" if depth_y > -21.0 else "deep")
	return "cave:%d,%d:%s" % [int(floor(cave_pos.x / 50.0)), int(floor(cave_pos.z / 50.0)), band]


static func band_tier(key: String, tier: int) -> int:
	## Caves push the tier: middle galleries roll one up, the deep two.
	if key.ends_with(":middle"):
		return mini(tier + 1, MAX_TIER)
	if key.ends_with(":deep"):
		return mini(tier + 2, MAX_TIER)
	return tier


## ------------------------------------------------------------ rosters -----

static func _seed(world_seed: int, key: String, salt: int) -> int:
	## Stable across runs: GDScript's String hash is deterministic.
	var h := int(hash(key)) & 0x7fffffff
	return int((int(world_seed) * 1000003 + h * 31 + salt * 7919) & 0x7fffffffffffffff)


static func roster(world_seed: int, key: String, tier: int) -> Array:
	## The species that live at `key` when the player is at `tier`: the
	## NATIVES (rolled from the zone alone at tier 0, so they are the zone's
	## own and were there at level 1) plus one NEWCOMER per tier climbed
	## (rolled from zone + tier, so each level tier brings something the
	## zone never had). Every genome is then HARDENED to the tier, natives
	## included — the hound you met at level 2 is the same hound at level
	## 15, only bigger, tougher, and with a trick or two it did not have.
	tier = clampi(tier, 0, MAX_TIER)
	var out: Array = []
	for i in range(NATIVES):
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(world_seed, key, 100 + i)
		var g := roll_species(rng, 0, {"native": true, "born_tier": 0})
		harden(g, tier, _seed(world_seed, key, 300 + i))
		out.append(g)
	for t in range(1, tier + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(world_seed, key, 500 + t)
		var g := roll_species(rng, t, {"born_tier": t})
		harden(g, tier, _seed(world_seed, key, 700 + t))
		out.append(g)
	return out


static func harden(g: Dictionary, tier: int, hseed: int) -> void:
	## Carry a species born at `born_tier` up to `tier`: the tier multiplier
	## on hp and damage, a little more size and mass, the loot tiers, a
	## steadier nerve — and one more ability every two tiers climbed, rolled
	## from `hseed` so the zone's hound learns the SAME trick every time.
	tier = clampi(tier, 0, MAX_TIER)
	var born := clampi(int(g.get("born_tier", 0)), 0, MAX_TIER)
	g["tier"] = maxi(tier, born)
	if tier <= born:
		return
	var steps := tier - born
	var mult := (1.0 + 0.55 * float(tier)) / (1.0 + 0.55 * float(born))
	var grow := 1.0 + 0.06 * float(steps)
	g["hp"] = roundf(float(g["hp"]) * mult)
	g["dmg"] = roundf(float(g["dmg"]) * mult)
	g["size"] = snappedf(float(g["size"]) * grow, 0.01)
	g["mass"] = roundf(float(g["mass"]) * grow * grow)
	g["xp_tier"] = clampi(tier + (1 if float(g["size"]) > 1.4 else 0), 0, 4)
	g["orb_tier"] = clampi(tier, 0, 3)
	if tier >= 3:
		g["nerve"] = minf(float(g.get("nerve", 0.2)), 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = hseed
	var ab: Array = g.get("abilities", [])
	var touched := false
	for a in ab:
		if TOUCHES.has(a):
			touched = true
	@warning_ignore("integer_division")
	for _i in range(steps / 2):
		var pool: Array = []
		for a in ABILITIES:
			if ab.has(a):
				continue
			if TOUCHES.has(a) and touched:
				continue
			if a == "howl" and str(g.get("plan", "")) == "serpent":
				continue
			pool.append(a)
		if pool.is_empty():
			break
		var a: String = pool[rng.randi_range(0, pool.size() - 1)]
		if TOUCHES.has(a):
			touched = true
		ab.append(a)
	g["abilities"] = ab


static func pick(world_seed: int, key: String, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	## One species from the roster, newcomers weighted a little heavier —
	## the new thing in the woods is the thing you keep running into.
	var r := roster(world_seed, key, tier)
	if r.is_empty():
		return {}
	var weights: Array = []
	var total := 0.0
	for g in r:
		var w := 1.0 + float(int((g as Dictionary).get("born_tier", 0))) * 0.35
		weights.append(w)
		total += w
	var x := rng.randf() * total
	for i in range(r.size()):
		x -= float(weights[i])
		if x <= 0.0:
			return r[i]
	return r[r.size() - 1]


static func for_spot(world_seed: int, pos: Vector3, level: int, rng: RandomNumberGenerator) -> Dictionary:
	return pick(world_seed, zone_key(pos), tier_for_level(level), rng)


static func raider(world_seed: int, cell: int, tier: int) -> Dictionary:
	## The warbands' fighters (Warbands.gd used to stage real Goblins). One
	## biped species per band cell, armed, that scales with the tier.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(world_seed, "band:%d" % cell, 900)
	var g := roll_species(rng, 0, {"plan": "biped", "armed": true, "born_tier": 0})
	harden(g, tier, _seed(world_seed, "band:%d" % cell, 901))
	g["raider"] = true
	return g


## ------------------------------------------------------------ genomes -----

static func roll_species(rng: RandomNumberGenerator, tier: int, hints: Dictionary = {}) -> Dictionary:
	## One species. `hints` may pin a plan ("plan"), force a weapon
	## ("armed"), or record the tier it was born at ("born_tier").
	tier = clampi(tier, 0, MAX_TIER)
	var plan := str(hints.get("plan", PLANS[rng.randi_range(0, PLANS.size() - 1)]))
	if not PLANS.has(plan):
		plan = "quadruped"
	var g := {}
	g["plan"] = plan
	g["born_tier"] = int(hints.get("born_tier", 0))
	g["native"] = bool(hints.get("native", false))
	g["tier"] = tier
	## --- build
	var size_lo := 0.7 + 0.12 * float(tier)
	var size_hi := 1.15 + 0.22 * float(tier)
	g["size"] = snappedf(rng.randf_range(size_lo, size_hi), 0.01)
	g["bulk"] = snappedf(rng.randf_range(0.8, 1.35), 0.01)
	g["leg_len"] = snappedf(rng.randf_range(0.8, 1.25), 0.01)
	g["neck"] = snappedf(rng.randf_range(0.0, 0.6), 0.01)
	g["head_size"] = snappedf(rng.randf_range(0.85, 1.3), 0.01)
	g["head"] = HEADS[rng.randi_range(0, HEADS.size() - 1)]
	g["horns"] = _weighted(rng, [0, 1, 2, 3], [0.5, 0.15, 0.28, 0.07])
	g["eyes"] = _weighted(rng, [0, 1, 2, 3, 4, 6], [0.06, 0.10, 0.52, 0.10, 0.14, 0.08])
	if g["head"] == "eyeless":
		g["eyes"] = 0
	g["tail"] = TAILS[_weighted(rng, [0, 1, 2, 3], [0.35, 0.3, 0.2, 0.15])]
	if plan == "serpent":
		g["tail"] = ""   ## a serpent is all tail
	g["plates"] = rng.randf() < 0.30 + 0.08 * float(tier)
	g["spines"] = rng.randf() < 0.25
	g["segments"] = rng.randi_range(5, 8) if plan == "serpent" else 0
	if plan == "biped":
		var arms: String = ARMS[_weighted(rng, [0, 1, 2, 3], [0.15, 0.35, 0.3, 0.2])]
		if bool(hints.get("armed", false)) and arms == "none":
			arms = "club"
		g["arms"] = arms
	else:
		g["arms"] = "none"
	## --- look
	g["tile"] = _tile_for(rng, plan, g)
	var hue := rng.randf()
	var sat := rng.randf_range(0.18, 0.55)
	var val := rng.randf_range(0.28, 0.62)
	g["col"] = Color.from_hsv(hue, sat, val)
	g["accent"] = Color.from_hsv(fmod(hue + rng.randf_range(0.35, 0.65), 1.0), clampf(sat + 0.2, 0.0, 1.0), clampf(val + 0.2, 0.0, 1.0))
	g["eye_col"] = [Color(0.95, 0.85, 0.2), Color(0.9, 0.2, 0.15), Color(0.3, 0.9, 0.4), Color(0.6, 0.85, 1.0), Color(0.95, 0.95, 0.9)][rng.randi_range(0, 4)]
	## --- fighting style
	g["special"] = _special_for(rng, plan, g)
	g["abilities"] = _abilities_for(rng, tier, plan)
	g["duelist"] = plan == "biped" and rng.randf() < 0.55
	g["climber"] = plan != "serpent" and rng.randf() < 0.6
	## --- stats, scaled by size and tier
	_stats(g, rng, tier)
	## --- identity
	g["families"] = _families(g)
	g["name"] = species_name(rng, g)
	g["id"] = "sp_%08x" % (int(hash(g["name"] + plan)) & 0xffffffff)
	g["monster"] = true
	return g


static func _weighted(rng: RandomNumberGenerator, vals: Array, w: Array) -> Variant:
	var total := 0.0
	for x in w:
		total += float(x)
	var r := rng.randf() * total
	for i in range(vals.size()):
		r -= float(w[i])
		if r <= 0.0:
			return vals[i]
	return vals[vals.size() - 1]


static func _tile_for(rng: RandomNumberGenerator, plan: String, g: Dictionary) -> String:
	match plan:
		"hexapod":
			return "chitin" if rng.randf() < 0.75 else "stone"
		"serpent":
			return "scale" if rng.randf() < 0.8 else "hide"
		"biped":
			if g["head"] == "skull":
				return "bone"
			return ["skin", "hide", "fur", "bone"][_weighted(rng, [0, 1, 2, 3], [0.45, 0.25, 0.2, 0.1])]
		_:
			if g["head"] == "skull":
				return "bone"
			return ["hide", "fur", "fur_long", "scale", "stone"][_weighted(rng, [0, 1, 2, 3, 4], [0.35, 0.3, 0.12, 0.15, 0.08])]


static func _special_for(rng: RandomNumberGenerator, plan: String, g: Dictionary) -> String:
	match plan:
		"biped":
			if g["arms"] == "blade" or g["arms"] == "club":
				return ["flurry", "lunge", ""][_weighted(rng, [0, 1, 2], [0.45, 0.35, 0.2])]
			return ["lunge", "flurry", ""][_weighted(rng, [0, 1, 2], [0.5, 0.25, 0.25])]
		"quadruped":
			return ["charge", "lunge", "slam", ""][_weighted(rng, [0, 1, 2, 3], [0.45, 0.25, 0.15, 0.15])]
		"hexapod":
			return ["lunge", "flurry", ""][_weighted(rng, [0, 1, 2], [0.5, 0.3, 0.2])]
		_:
			return ["lunge", "slam", ""][_weighted(rng, [0, 1, 2], [0.55, 0.2, 0.25])]


static func _abilities_for(rng: RandomNumberGenerator, tier: int, plan: String) -> Array:
	## How many: tier 0 usually none, apex two or three. Never two touches.
	var n: int = [_weighted(rng, [0, 1], [0.6, 0.4]), 1, _weighted(rng, [1, 2], [0.5, 0.5]), 2, _weighted(rng, [2, 3], [0.55, 0.45])][tier]
	var out: Array = []
	var pool: Array = ABILITIES.duplicate()
	if plan == "serpent":
		pool.erase("howl")
	var touched := false
	var guard := 0
	while out.size() < n and not pool.is_empty() and guard < 40:
		guard += 1
		var a: String = pool[rng.randi_range(0, pool.size() - 1)]
		if TOUCHES.has(a):
			if touched:
				pool.erase(a)
				continue
			touched = true
		pool.erase(a)
		out.append(a)
	return out


static func _stats(g: Dictionary, rng: RandomNumberGenerator, tier: int) -> void:
	var s := float(g["size"])
	var b := float(g["bulk"])
	var tk := 1.0 + 0.55 * float(tier)          ## the tier's own multiplier
	var base_hp: float = {"biped": 42.0, "quadruped": 60.0, "hexapod": 34.0, "serpent": 50.0}[g["plan"]]
	var base_dmg: float = {"biped": 8.0, "quadruped": 10.0, "hexapod": 6.0, "serpent": 9.0}[g["plan"]]
	var base_spd: float = {"biped": 4.6, "quadruped": 5.4, "hexapod": 5.0, "serpent": 3.6}[g["plan"]]
	g["hp"] = roundf(base_hp * s * b * tk * rng.randf_range(0.85, 1.15))
	g["dmg"] = roundf(base_dmg * sqrt(s) * tk * rng.randf_range(0.85, 1.15))
	g["speed"] = snappedf(base_spd * clampf(1.15 - (s - 1.0) * 0.35, 0.6, 1.3) * float(g["leg_len"]) * rng.randf_range(0.9, 1.1), 0.1)
	if (g["abilities"] as Array).has("quick"):
		g["speed"] = snappedf(float(g["speed"]) * 1.25, 0.1)
	g["mass"] = roundf({"biped": 55.0, "quadruped": 90.0, "hexapod": 30.0, "serpent": 45.0}[g["plan"]] * s * s * b)
	g["nerve"] = snappedf(rng.randf_range(0.0, 0.35) if tier < 3 else rng.randf_range(0.0, 0.15), 0.01)
	g["xp_tier"] = clampi(tier + (1 if s > 1.4 else 0), 0, 4)
	g["orb_tier"] = clampi(tier, 0, 3)
	g["pack"] = {"biped": [2, 4], "quadruped": [1, 3], "hexapod": [3, 6], "serpent": [1, 2]}[g["plan"]]
	if s > 1.6:
		g["pack"] = [1, 1]


static func _families(g: Dictionary) -> Array:
	## The weapon-material families the sword reads (Player's FAMILY names).
	var f: Array = []
	if g["tile"] == "bone" or g["head"] == "skull":
		f.append("undead")
	if g["plan"] == "biped":
		f.append("humanoid")
	if f.is_empty() or g["plan"] != "biped":
		f.append("beast")
	return f


## -------------------------------------------------------------- names -----

static func species_name(rng: RandomNumberGenerator, g: Dictionary) -> String:
	var bank: Array = {"biped": SYL_GROWL, "quadruped": SYL_GROWL, "hexapod": SYL_CLICK, "serpent": SYL_HISS}[g["plan"]]
	if g["tile"] == "bone":
		bank = SYL_MOAN
	var n := rng.randi_range(2, 3)
	var word := ""
	for i in range(n):
		word += String(bank[rng.randi_range(0, bank.size() - 1)])
	word = word.substr(0, 1).to_upper() + word.substr(1)
	var ep: Array = EPITHETS[g["plan"]]
	var epithet := String(ep[rng.randi_range(0, ep.size() - 1)])
	for a in (g["abilities"] as Array):
		if TOUCH_WORDS.has(a) and rng.randf() < 0.7:
			epithet = String(TOUCH_WORDS[a]) + " " + epithet
			break
	return "%s %s" % [word, epithet]


static func describe(g: Dictionary) -> String:
	## One line for the lab / the log: what it is and what it does.
	if g.is_empty():
		return "nothing"
	var bits: Array = []
	bits.append("%s %s" % [tier_name(int(g.get("tier", 0))).to_lower(), str(g.get("plan", "?"))])
	bits.append("%.1fx" % float(g.get("size", 1.0)))
	bits.append(str(g.get("head", "")) + " head")
	if int(g.get("horns", 0)) > 0:
		bits.append("%d horns" % int(g["horns"]))
	if str(g.get("tail", "")) != "":
		bits.append(str(g["tail"]) + " tail")
	if bool(g.get("plates", false)):
		bits.append("plated")
	if str(g.get("arms", "none")) != "none":
		bits.append(str(g["arms"]))
	if str(g.get("special", "")) != "":
		bits.append("special: " + str(g["special"]))
	var ab: Array = g.get("abilities", [])
	if not ab.is_empty():
		bits.append("abilities: " + ", ".join(PackedStringArray(ab)))
	bits.append("hp %d, dmg %d" % [int(g.get("hp", 0)), int(g.get("dmg", 0))])
	return ", ".join(PackedStringArray(bits))


## ------------------------------------------------------------- save/load --

static func to_json(g: Dictionary) -> Dictionary:
	var d := g.duplicate(true)
	for k in ["col", "accent", "eye_col"]:
		if d.has(k) and d[k] is Color:
			d[k] = (d[k] as Color).to_html(false)
	return d


static func from_json(d: Dictionary) -> Dictionary:
	var g := d.duplicate(true)
	for k in ["col", "accent", "eye_col"]:
		if g.has(k) and g[k] is String:
			g[k] = Color.html(String(g[k]))
	if not g.has("abilities"):
		g["abilities"] = []
	if not g.has("pack"):
		g["pack"] = [1, 2]
	return g


static func validate(g: Dictionary) -> bool:
	## The contract Monster.gd builds against.
	if g.is_empty():
		return false
	for k in ["plan", "head", "size", "bulk", "leg_len", "tile", "col", "hp", "dmg", "speed", "mass", "name", "abilities", "special"]:
		if not g.has(k):
			return false
	if not PLANS.has(str(g["plan"])) or not HEADS.has(str(g["head"])):
		return false
	if not SPECIALS.has(str(g["special"])):
		return false
	for a in (g["abilities"] as Array):
		if not ABILITIES.has(str(a)):
			return false
	if float(g["size"]) < 0.3 or float(g["size"]) > 4.0:
		return false
	if float(g["hp"]) <= 0.0 or float(g["speed"]) <= 0.0:
		return false
	return true
