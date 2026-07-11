class_name Materials
## Weapon material data + matchup math — see docs/MATERIALS.md.
## Every weapon is made of ONE material. The material sets its matchup
## multipliers vs creature families, its element (or none), its weight, and
## its look. Pure static data/helpers — never instanced.
##
## Families in use (tag enemies via Enemy.families):
##   beast, humanoid, undead, cursed, armored, construct, demon, fae,
##   dragonkin, ooze, insect, fiery, cold, regenerating, flying
## "*" in a strong list = broadly good vs everything (mithril soft, endgame full).

const STRONG_MULT := 1.35
const WEAK_MULT := 0.8
const BROAD_MULT := 1.15     ## the softer "good vs everything" (mithril)
## TODO(design): element bonus should scale +5%..+25% with the sword's evolution
## level (step 5). No evolution bar yet, so a fixed mid value stands in.
const ELEMENT_BONUS := 0.15

const SWORD_BASE_WEIGHT := 7.0

## ---- Armor sets: 5 pieces per material -----------------------------------
## Piece weight = base × the material's weight mult (mithril kit is light,
## adamant kit is a walking siege wall). Protection is % damage shaved per
## worn piece, by tier — a full set: common 10% → end-game 25% (capped 40%).
const ARMOR_SLOTS: Array[String] = ["helmet", "chest", "arms", "pants", "shoes"]
const ARMOR_BASE_WEIGHT := {"helmet": 3.5, "chest": 9.0, "arms": 4.5, "pants": 5.5, "shoes": 3.0}
const ARMOR_PIECE_NAMES := {"helmet": "Helmet", "chest": "Chestplate", "arms": "Bracers", "pants": "Greaves", "shoes": "Boots"}
const PIECE_PROTECT := [0.02, 0.03, 0.04, 0.05]   ## per piece, by tier

## tier: 0 common · 1 uncommon · 2 rare · 3 end-game
## color: blade albedo. element: {} = none, else {name, color, strong_vs}.
const MATS := {
	"bronze": {
		"name": "Bronze", "tier": 0, "weight": 0.95,
		"color": Color(0.71, 0.44, 0.22),
		"strong": ["ooze", "insect"], "weak": ["armored"],
		"element": {},
	},
	"iron": {
		"name": "Iron", "tier": 0, "weight": 1.0,
		"color": Color(0.45, 0.47, 0.50),
		"strong": ["beast", "humanoid"], "weak": ["construct", "undead"],
		"element": {},
	},
	"steel": {
		"name": "Steel", "tier": 0, "weight": 1.0,
		"color": Color(0.72, 0.78, 0.85),
		"strong": ["beast", "humanoid", "armored"], "weak": ["cursed", "undead"],
		"element": {},
	},
	"silver": {
		"name": "Silver", "tier": 1, "weight": 0.9,
		"color": Color(0.88, 0.90, 0.96),
		"strong": ["undead", "cursed"], "weak": ["armored"],
		"element": {"name": "Moonlight", "color": Color(0.75, 0.85, 1.0),
			"strong_vs": ["undead", "cursed"]},
	},
	"cold_iron": {
		"name": "Cold Iron", "tier": 1, "weight": 1.05,
		"color": Color(0.50, 0.58, 0.70),
		"strong": ["demon", "fae", "cursed"], "weak": ["construct"],
		"element": {"name": "Frost", "color": Color(0.55, 0.80, 1.0),
			"strong_vs": ["fiery", "regenerating"]},
	},
	"meteoric": {
		"name": "Meteoric", "tier": 2, "weight": 1.1,
		"color": Color(0.30, 0.26, 0.24),
		"strong": ["demon", "dragonkin"], "weak": [],
		"element": {"name": "Ember", "color": Color(1.0, 0.45, 0.10),
			"strong_vs": ["regenerating", "cold"]},
	},
	"mithril": {
		"name": "Mithril", "tier": 2, "weight": 0.7,
		"color": Color(0.80, 0.88, 0.92),
		"strong": ["*"], "weak": [],
		"element": {"name": "Spark", "color": Color(0.70, 0.85, 1.0),
			"strong_vs": ["armored", "flying"]},
	},
	"adamant": {
		"name": "Adamant", "tier": 2, "weight": 1.4,
		"color": Color(0.25, 0.28, 0.33),
		"strong": ["construct", "armored"], "weak": [],
		"element": {"name": "Quake", "color": Color(0.85, 0.72, 0.40),
			"strong_vs": ["construct"]},
	},
	"dragonsteel": {
		"name": "Dragonsteel", "tier": 3, "weight": 1.0,
		"color": Color(0.48, 0.18, 0.14),
		"strong": ["*"], "weak": [],
		"element": {"name": "Dragonfire", "color": Color(1.0, 0.35, 0.08),
			"strong_vs": ["beast", "humanoid", "cursed", "demon", "fae", "dragonkin", "regenerating", "cold"]},
	},
	"voidsteel": {
		"name": "Voidsteel", "tier": 3, "weight": 1.05,
		"color": Color(0.20, 0.16, 0.28),
		"strong": ["undead", "demon"], "weak": [],
		"element": {"name": "Soulfire", "color": Color(0.62, 0.30, 0.95),
			"strong_vs": ["undead", "demon"]},
	},
}

## Menu / display order (common -> end-game).
const ORDER: Array[String] = [
	"bronze", "iron", "steel", "silver", "cold_iron",
	"meteoric", "mithril", "adamant", "dragonsteel", "voidsteel",
]

const TIER_NAMES := ["Common", "Uncommon", "Rare", "End-game"]

## ---- Rare mob drops: THE V1 SLICE ONLY (docs/MATERIALS.md) ----------------
## Indexed by the mob's xp_tier (0..3): chance a kill drops a sword at all,
## then a weighted pick of which material. Everything else is Armory-only
## until its target creatures exist.
const DROP_CHANCE := [0.03, 0.045, 0.06, 0.08]
const DROP_TABLE := [
	[["iron", 80], ["steel", 20]],
	[["iron", 55], ["steel", 40], ["silver", 5]],
	[["steel", 50], ["silver", 40], ["meteoric", 10]],
	[["steel", 20], ["silver", 55], ["meteoric", 25]],
]


static func get_mat(id: String) -> Dictionary:
	return MATS.get(id, MATS["iron"])


static func display_name(id: String) -> String:
	return String(get_mat(id)["name"])


static func sword_name(id: String) -> String:
	return "%s Sword" % display_name(id)


static func sword_weight(id: String) -> float:
	return SWORD_BASE_WEIGHT * float(get_mat(id)["weight"])


static func armor_piece_name(id: String, slot: String) -> String:
	return "%s %s" % [display_name(id), String(ARMOR_PIECE_NAMES[slot])]


static func armor_piece_weight(id: String, slot: String) -> float:
	return float(ARMOR_BASE_WEIGHT[slot]) * float(get_mat(id)["weight"])


static func armor_piece_protect(id: String) -> float:
	return float(PIECE_PROTECT[int(get_mat(id)["tier"])])


static func element_name(id: String) -> String:
	var e: Dictionary = get_mat(id)["element"]
	return String(e["name"]) if not e.is_empty() else ""


## Damage multiplier of material `id` against a creature with these family
## tags. Strong/weak stack MULTIPLICATIVELY — an armored+cursed foe hit with
## steel nets 1.35 × 0.8 ≈ 1.08 (the armor helps, the curse resists).
static func matchup_mult(id: String, families: Array) -> float:
	var mat := get_mat(id)
	var m := 1.0
	if "*" in mat["strong"]:
		m *= STRONG_MULT if int(mat["tier"]) >= 3 else BROAD_MULT
	for f in families:
		if f in mat["strong"]:
			m *= STRONG_MULT
		if f in mat["weak"]:
			m *= WEAK_MULT
	return m


## Elemental bonus multiplier (1.0 = nothing). Situational, never flat: it only
## pays vs the element's right targets — wrong targets get ~nothing.
static func element_mult(id: String, families: Array) -> float:
	var e: Dictionary = get_mat(id)["element"]
	if e.is_empty():
		return 1.0
	for f in families:
		if f in e["strong_vs"]:
			return 1.0 + ELEMENT_BONUS
	return 1.0


## Roll a rare sword drop for a dying mob. Returns a material id, or "" (most
## of the time) for no drop.
static func roll_sword_drop(xp_tier: int) -> String:
	var t := clampi(xp_tier, 0, 3)
	if randf() >= float(DROP_CHANCE[t]):
		return ""
	var table: Array = DROP_TABLE[t]
	var total := 0
	for entry: Array in table:
		total += int(entry[1])
	var pick := randi_range(1, total)
	for entry: Array in table:
		pick -= int(entry[1])
		if pick <= 0:
			return String(entry[0])
	return String(table[0][0])
