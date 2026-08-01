extends RefCounted
class_name PlayerStats
## The character sheet: five stats, banked level-up points, the level-99 XP
## curve, and the hidden progression trees ("grow a stat by using it").
## Pure data + math — Player.gd owns one of these, reads multipliers out of it,
## and draws all the UI itself.
##
## Stats start at BASE_STAT and cap at STAT_CAP. Formulas use "points above
## base" with diminishing returns, so every point helps but stacking one stat
## can never break the game (costs never hit zero, mitigation never hits 100%).

const STAT_ORDER: Array[String] = ["con", "dex", "str", "wis", "cha"]
const STAT_NAMES := {
	"con": "Constitution", "dex": "Dexterity", "str": "Strength",
	"wis": "Wisdom", "cha": "Charisma",
}
const STAT_FLAVOR := {
	"con": "Thick blood and deep lungs. The body refuses to quit.",
	"dex": "Economy of motion. Every action costs less and flows faster.",
	"str": "Hit like a falling tree. Shrug off what hits back. Carry the spoils.",
	"wis": "Understanding of the withered world. Will unlock sword arts and higher blades.",
	"cha": "Presence. Will grow through words once there is anyone left to charm.",
}

const BASE_STAT := 5
const STAT_CAP := 99
const POINTS_PER_LEVEL := 3
const MAX_LEVEL := 99

## Base values the formulas grow from (kept here so tooltips can show real numbers).
const BASE_HP := 100.0
const BASE_STAM := 100.0
const BASE_REGEN := 20.0
const BASE_HEAL := 3.0   ## out-of-combat HP regen per second
const BASE_CARRY := 90.0  ## was 60 — the old cap arrived so early it read as a sprint BUG
const BASE_DAMAGE := 22.0

var vals := {"con": BASE_STAT, "dex": BASE_STAT, "str": BASE_STAT, "wis": BASE_STAT, "cha": BASE_STAT}
var points := 0   ## banked, unspent level-up points


## ========================= Progression trees ==============================
## Each tree feeds its linked stat: finish a tier, gain that stat immediately
## (escalating rewards so late tiers stay worth chasing). If the stat is
## already capped the reward spills into the banked point pool instead.
## Trees never end: past the authored tiers, thresholds keep scaling with each
## completion (geometric growth taken from the tree's own last two tiers).
## "locked" trees render as ??? until their system exists (CHA needs NPCs).

const TIER_POINTS: Array[int] = [1, 1, 2, 2, 3, 3]

const TREES: Array[Dictionary] = [
	{
		"id": "deaths_door", "name": "Death's Door", "stat": "con",
		"desc": "Come back from the brink — drop below 15% health in a fight, then recover.",
		"noun": "recoveries", "tiers": [1, 3, 6, 12, 20, 30], "locked": false,
	},
	{
		"id": "marathoner", "name": "Marathoner", "stat": "con",
		"desc": "Cover ground. Every meter on foot toughens the body.",
		"noun": "traveled", "tiers": [500, 2000, 5000, 15000, 40000, 100000], "locked": false,
	},
	{
		"id": "untouchable", "name": "Untouchable", "stat": "dex",
		"desc": "Dash through a telegraphed special attack that would have landed.",
		"noun": "dodges", "tiers": [3, 8, 20, 40, 75, 125], "locked": false,
	},
	{
		"id": "combo_master", "name": "Combo Master", "stat": "dex",
		"desc": "Land the third strike of the flowing combo.",
		"noun": "finishers", "tiers": [5, 15, 40, 100, 250, 500], "locked": false,
	},
	{
		"id": "committed_step", "name": "The Committed Step", "stat": "dex",
		"desc": "There is no taking it back once your feet have gone. Close the gap and swing in the same breath.",
		"noun": "commitments", "tiers": [5, 15, 40, 90, 200, 450], "locked": false,
	},
	{
		"id": "nothing_to_lose", "name": "Nothing Left to Lose", "stat": "con",
		"desc": "Caution is a thing you can afford at full health. Drive a committed strike home while yours is nearly gone.",
		"noun": "reckless strikes", "tiers": [3, 10, 25, 55, 110, 220], "locked": false,
	},
	{
		"id": "perfect_guard", "name": "Perfect Guard", "stat": "str",
		"desc": "Raise your block in the last instant before a hit lands — a parry.",
		"noun": "parries", "tiers": [3, 8, 20, 40, 75, 125], "locked": false,
	},
	{
		"id": "slayer", "name": "Slayer", "stat": "str",
		"desc": "Send the withered back to dust.",
		"noun": "kills", "tiers": [10, 50, 150, 400, 1000, 2500], "locked": false,
	},
	{
		"id": "essence_drinker", "name": "Essence Drinker", "stat": "wis",
		"desc": "Absorb the essence that bursts from the withered.",
		"noun": "orbs absorbed", "tiers": [25, 75, 200, 500, 1200, 2500], "locked": false,
	},
	{
		"id": "silver_tongue", "name": "Silver Tongue", "stat": "cha",
		"desc": "The wilds hold no one to talk to... yet.",
		"noun": "", "tiers": [], "locked": true,
	},
]

var progress := {}       ## tree id -> raw counter (dodges, meters, kills...)
var tiers_earned := {}   ## tree id -> how many tiers completed


func _init() -> void:
	for t: Dictionary in TREES:
		progress[t.id] = 0
		tiers_earned[t.id] = 0


## ============================ Stats & points ==============================


func get_stat(id: String) -> int:
	return int(vals.get(id, BASE_STAT))


func _p(id: String) -> float:
	## Points above base — what every formula scales from.
	return float(get_stat(id) - BASE_STAT)


func can_spend(id: String) -> bool:
	return points > 0 and get_stat(id) < STAT_CAP


func spend(id: String, n := 1) -> int:
	## Spend up to n banked points into a stat. Returns how many actually went in.
	var put: int = clampi(n, 0, mini(points, STAT_CAP - get_stat(id)))
	vals[id] = get_stat(id) + put
	points -= put
	return put


func on_level_up() -> int:
	points += POINTS_PER_LEVEL
	return POINTS_PER_LEVEL


func xp_needed(level: int) -> int:
	## Deliberately slow: every level is earned. Roughly 20+ kills for level 2
	## and it stretches hard from there (~5M XP total to 99 — the true long
	## game; higher-tier XP sources arrive with later steps).
	return 120 + int(25.0 * pow(float(level), 1.9))


## ===================== Derived values (the formulas) ======================
## Diminishing shapes: x/(x+p) multipliers can approach but never reach zero.


func max_health() -> float:
	return BASE_HP + _p("con") * 6.0            ## 99 CON -> 664 HP


func max_stamina() -> float:
	return BASE_STAM + _p("con") * 4.0          ## 99 CON -> 476 stamina


func heal_rate() -> float:
	## Out-of-combat health regen — CON closes wounds faster (and since CON also
	## grows the pool, the % recovery per second climbs on both ends).
	return BASE_HEAL * (1.0 + _p("con") * 0.02)     ## 99 CON -> 8.6 HP/s


func bar_scale() -> float:
	## How much wider the HP/stamina bars draw. Visual only, capped so the HUD
	## never eats the screen even at 99 CON.
	return 1.0 + minf(_p("con") * 0.006, 0.5)


func stamina_cost_mult() -> float:
	return 60.0 / (60.0 + _p("dex"))            ## 99 DEX -> 39% cost (-61%)


func stamina_regen() -> float:
	return BASE_REGEN * (1.0 + _p("dex") * 0.012)   ## 99 DEX -> 42.6/s


func speed_mult() -> float:
	return 1.0 + minf(_p("dex") * 0.0022, 0.18)     ## "a little faster", capped +18%


func swing_mult() -> float:
	## Multiplies swing duration (lower = faster attacks/recovery).
	return 1.0 - minf(_p("dex") * 0.0018, 0.15)


func damage() -> float:
	return BASE_DAMAGE * (1.0 + _p("str") * 0.015)  ## 99 STR -> ~53 per hit


func damage_taken_mult() -> float:
	return 55.0 / (55.0 + _p("str"))            ## 99 STR -> takes 37% (-63%)


func carry_limit() -> float:
	return BASE_CARRY + _p("str") * 1.5         ## 99 STR -> 201 wt


func xp_mult() -> float:
	## +3%/pt: with the slow curve, WIS is THE learning stat (sword arts later).
	return 1.0 + _p("wis") * 0.03               ## 99 WIS -> +282% XP


func gold_mult() -> float:
	return 1.0 + _p("cha") * 0.01               ## placeholder until NPCs


## ====================== Tooltip lines (Stats page) ========================


func effect_lines(id: String, extra := 0) -> Array:
	## Rows for the hover panel: [label, value at stat+extra, value at +1 more].
	## The UI renders them as "Max health   190 -> 196".
	var real: int = get_stat(id)
	var out: Array = []
	vals[id] = mini(real + extra, STAT_CAP)
	var now := _snapshot(id)
	vals[id] = mini(real + extra + 1, STAT_CAP)
	var nxt := _snapshot(id)
	vals[id] = real
	for i in range(mini(now.size(), nxt.size())):  ## same shape by construction, but never trust it
		out.append([now[i][0], now[i][1], nxt[i][1]])
	return out


func _snapshot(id: String) -> Array:
	match id:
		"con":
			return [
				["Max health", "%.0f" % max_health()],
				["Max stamina", "%.0f" % max_stamina()],
				["Health regen", "%.1f/s" % heal_rate()],
			]
		"dex":
			return [
				["Stamina costs", "-%d%%" % roundi((1.0 - stamina_cost_mult()) * 100.0)],
				["Stamina regen", "%.1f/s" % stamina_regen()],
				["Move speed", "+%d%%" % roundi((speed_mult() - 1.0) * 100.0)],
				["Attack speed", "+%d%%" % roundi((1.0 / swing_mult() - 1.0) * 100.0)],
			]
		"str":
			return [
				["Damage per hit", "%.0f" % damage()],
				["Damage taken", "-%d%%" % roundi((1.0 - damage_taken_mult()) * 100.0)],
				["Carry limit", "%.0f wt" % carry_limit()],
			]
		"wis":
			return [
				["XP gained", "+%d%%" % roundi((xp_mult() - 1.0) * 100.0)],
				["Sword arts", "(soon)"],
			]
		"cha":
			return [
				["Gold found", "+%d%%" % roundi((gold_mult() - 1.0) * 100.0)],
				["Persuasion", "(soon)"],
			]
	return []


## ========================= Progression recording ==========================


func record(id: String, amount := 1) -> Array[Dictionary]:
	## Bump a tree's counter; return any tiers completed by it, each as
	## {name, stat, points, overflow} — Player toasts them. Reward goes straight
	## into the linked stat (or the banked pool if that stat is capped).
	var done: Array[Dictionary] = []
	var tree := _tree(id)
	if tree.is_empty() or bool(tree.locked):
		return done
	progress[id] = int(progress[id]) + amount
	var guard := 0  ## thresholds grow geometrically, but never trust a loop
	while guard < 16 and int(progress[id]) >= tier_threshold(id, int(tiers_earned[id])):
		guard += 1
		var idx := int(tiers_earned[id])
		tiers_earned[id] = idx + 1
		var reward := tier_points(idx)
		var stat := String(tree.stat)
		var overflow := false
		for _i in range(reward):
			if get_stat(stat) < STAT_CAP:
				vals[stat] = get_stat(stat) + 1
			else:
				points += 1
				overflow = true
		done.append({
			"name": "%s %s" % [tree.name, roman(idx + 1)],
			"stat": stat, "points": reward, "overflow": overflow,
		})
	return done


func _tree(id: String) -> Dictionary:
	for t: Dictionary in TREES:
		if String(t.id) == id:
			return t
	return {}


func tier_threshold(id: String, idx: int) -> int:
	## What tier number idx (0-based) requires. Inside the authored list it's
	## read straight out; past it, each tier scales by the tree's own growth
	## rate (ratio of its last two authored tiers), rounded to clean numbers —
	## so every completion raises the bar for the next one, forever.
	var tree := _tree(id)
	if tree.is_empty() or (tree.tiers as Array).is_empty():
		return 0x7FFFFFFF  ## locked / undefined: unreachable
	var tiers: Array = tree.tiers
	if idx < tiers.size():
		return int(tiers[idx])
	var last := float(tiers[tiers.size() - 1])
	var growth := 1.6
	if tiers.size() >= 2 and float(tiers[tiers.size() - 2]) > 0.0:
		growth = maxf(1.35, last / float(tiers[tiers.size() - 2]))
	return _nice(last * pow(growth, float(idx - tiers.size() + 1)))


func tier_points(idx: int) -> int:
	## Reward for tier idx; past the authored curve it stays at the top rate.
	return TIER_POINTS[mini(idx, TIER_POINTS.size() - 1)]


func next_threshold(id: String) -> int:
	## The counter value the next tier needs (-1 = locked tree).
	var tree := _tree(id)
	if tree.is_empty() or bool(tree.locked):
		return -1
	return tier_threshold(id, int(tiers_earned[id]))


static func _nice(v: float) -> int:
	## Round up to ~2 significant digits so scaled thresholds read clean
	## (67.5 -> 68, 675 -> 680, 43750 -> 44000).
	if v < 10.0:
		return int(ceilf(v))
	var mag := pow(10.0, floorf(log(v) / log(10.0)) - 1.0)
	return int(ceilf(v / mag) * mag)


static func roman(n: int) -> String:
	if n <= 0:
		return "I"
	const VALS: Array[int] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	const SYMS: Array[String] = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	var left := n
	for i in range(VALS.size()):
		while left >= VALS[i]:
			out += SYMS[i]
			left -= VALS[i]
	return out
