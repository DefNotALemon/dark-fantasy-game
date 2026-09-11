extends SceneTree

## ===========================================================================
## tools/probe_weatherwise.gd
##
## Run BEFORE a single line of scripts/Weatherwise.gd exists. Seven rounds
## running, the probe that goes first has caught the round's worst number
## before an assertion was written -- and twice it chose the feature's shape.
##
## Three questions, asked of the REAL CritterDex and a faithful copy of the
## pool filter WildlifeDirector._roll_species builds:
##
##   1. Does a weather term change WHO YOU MEET, or only shuffle the tail?
##   2. `rain_only` is one flag on one species and NOTHING in the project has
##      ever read it. Does a weather term make the Red Eft a thing a player
##      can actually walk up to -- and keep it unreachable when it is dry?
##   3. Does a storm EMPTY the woods or SORT them? Empty is a bug: fewer
##      animals is the feature, no animals is a ghost town.
## ===========================================================================

const LEVELS := ["CLEAR", "OVERCAST", "DRIZZLE", "RAIN", "STORM"]
const ZONES := ["deep_woods", "field", "moosehead"]
const HOURS := [6.0, 13.0]

## ------------------------------------------------------------------ guilds
## Derived from the dex, never restated. A guild is not a taxon -- it is an
## answer to ONE question: what does foul weather do to this animal?

static func guild_of(k: String) -> String:
	if bool(CritterDex.flag(k, "legend", false)):
		return "LEGEND"
	if bool(CritterDex.flag(k, "audio_only", false)):
		return "VOICE"
	if bool(CritterDex.flag(k, "soars", false)):
		return "SOARING"
	var rig := String(CritterDex.rig_of(k))
	if rig == "SWARM":
		return "FLATTENED"
	if rig == "FISH" or rig == "BIRD_WATER":
		return "UNBOTHERED"
	if rig == "HERP":
		if bool(CritterDex.flag(k, "water", false)):
			return "UNBOTHERED"
		if bool(CritterDex.flag(k, "basks", false)):
			return "SHELTERING"
		return "DRAWN"
	if rig.begins_with("BIRD_"):
		return "SHELTERING"
	if bool(CritterDex.flag(k, "water", false)) and (rig == "MUSTELID" or rig == "CHUNK"):
		return "UNBOTHERED"
	if rig == "CANID" or rig == "FELID" or rig == "MUSTELID":
		return "HUNTING"
	if rig == "RODENT_S":
		return "SHELTERING"
	return "BEDDING"

## -------------------------------------------------------- candidate tables
## Indexed by Weather.Level: CLEAR OVERCAST DRIZZLE RAIN STORM.
## Every set is 1.0 at CLEAR by construction -- fair weather is the world the
## game already has and this feature must not move it.

const SET_A := {
	"SOARING":    [1.0, 0.70, 0.40, 0.20, 0.05],
	"SHELTERING": [1.0, 0.90, 0.60, 0.35, 0.15],
	"FLATTENED":  [1.0, 0.90, 0.50, 0.20, 0.05],
	"DRAWN":      [1.0, 1.40, 1.60, 2.40, 1.80],
	"UNBOTHERED": [1.0, 1.00, 1.00, 1.00, 0.90],
	"HUNTING":    [1.0, 1.05, 1.15, 1.20, 0.80],
	"BEDDING":    [1.0, 1.15, 1.25, 0.60, 0.25],
}
const SET_B := {
	"SOARING":    [1.0, 0.45, 0.12, 0.00, 0.00],
	"SHELTERING": [1.0, 0.80, 0.40, 0.15, 0.05],
	"FLATTENED":  [1.0, 0.85, 0.35, 0.08, 0.00],
	"DRAWN":      [1.0, 1.80, 2.20, 3.40, 2.60],
	"UNBOTHERED": [1.0, 1.00, 1.00, 1.00, 0.85],
	"HUNTING":    [1.0, 1.10, 1.30, 1.35, 0.70],
	"BEDDING":    [1.0, 1.30, 1.45, 0.45, 0.12],
}
const SET_C := {
	"SOARING":    [1.0, 0.25, 0.00, 0.00, 0.00],
	"SHELTERING": [1.0, 0.65, 0.22, 0.06, 0.00],
	"FLATTENED":  [1.0, 0.70, 0.18, 0.02, 0.00],
	"DRAWN":      [1.0, 2.40, 3.20, 5.00, 4.00],
	"UNBOTHERED": [1.0, 1.00, 1.00, 1.00, 0.80],
	"HUNTING":    [1.0, 1.20, 1.50, 1.60, 0.60],
	"BEDDING":    [1.0, 1.50, 1.70, 0.30, 0.06],
}

## SET_D is not a fourth guess. It is the FIT: A and B disagreed, and each was
## right about a different guild. A holds the eft at one animal in six on a wet
## dawn (B makes it nearly one in four, C makes a midday storm in the woods half
## newts); B is the only set where the sky actually empties of soaring birds,
## which is the thing the gap list asked for in as many words. D takes B's
## SOARING row, A's DRAWN / HUNTING / BEDDING / UNBOTHERED rows, and splits the
## difference on SHELTERING, where A left the birds too loud in real rain.
const SET_D := {
	"SOARING":    [1.0, 0.45, 0.12, 0.00, 0.00],
	"SHELTERING": [1.0, 0.85, 0.50, 0.25, 0.10],
	"FLATTENED":  [1.0, 0.85, 0.40, 0.12, 0.00],
	"DRAWN":      [1.0, 1.40, 1.60, 2.40, 1.80],
	"UNBOTHERED": [1.0, 1.00, 1.00, 1.00, 0.90],
	"HUNTING":    [1.0, 1.05, 1.15, 1.20, 0.80],
	"BEDDING":    [1.0, 1.15, 1.25, 0.60, 0.25],
}


func _init() -> void:
	print("=== WEATHERWISE PROBE =====================================")
	_roster()
	_pools()
	_noise()
	_swarms()
	quit()


## ---------------------------------------------------------------- roster
func _roster() -> void:
	print("\n--- 1. the roster, sorted into guilds -----------------------")
	var by: Dictionary = {}
	for k in CritterDex.DEX.keys():
		var g := guild_of(String(k))
		if not by.has(g):
			by[g] = []
		(by[g] as Array).append(String(k))
	for g in by.keys():
		var a := by[g] as Array
		print("  %-11s %2d  %s" % [g, a.size(), ", ".join(a)])


## ----------------------------------------------------------------- pools
func _pool(zone: String, hour: float, phase: float, water: bool) -> Array:
	## A faithful copy of WildlifeDirector._roll_species' filter chain, minus
	## the roll. If this drifts from that function the answer is worthless, so
	## the suite that follows asserts the chain against the real source.
	var outp: Array = []
	for e in CritterDex.species_for_zone(zone):
		var k := String(e["key"])
		if CritterDex.rig_of(k) == "SWARM":
			continue
		if not CritterDex.is_awake(k, hour, phase):
			continue
		if bool(CritterDex.flag(k, "audio_only", false)):
			continue
		if bool(CritterDex.flag(k, "water", false)) and not water:
			continue
		if bool(CritterDex.flag(k, "cliff", false)) or bool(CritterDex.flag(k, "island_only", false)) \
				or bool(CritterDex.flag(k, "far_only", false)) or bool(CritterDex.flag(k, "marine", false)):
			continue
		var w := float(e["w"])
		var rare = CritterDex.flag(k, "rare", 1.0)
		w *= float(rare) if rare is float else 1.0
		if bool(CritterDex.flag(k, "dusk", false)):
			var dusk := (hour >= 18.6 and hour < 21.2) or (hour >= 4.6 and hour < 7.4)
			w *= 1.8 if dusk else 0.45
		outp.append({"key": k, "w": w, "g": guild_of(k)})
	return outp


func _pools() -> void:
	print("\n--- 2. who you meet, by weather -----------------------------")
	var sets := {"A": SET_A, "B": SET_B, "C": SET_C, "D": SET_D}
	for zone_v in ZONES:
		var zone: String = zone_v
		var water: bool = zone == "bog" or zone == "moosehead" or zone == "beacon_coast"
		for hour_v in HOURS:
			var hour: float = hour_v
			var base := _pool(zone, hour, 0.45, water)
			if base.is_empty():
				continue
			print("\n  [%s] h=%.0f  water=%s  %d candidates" % [zone, hour, water, base.size()])
			for sn in sets.keys():
				var tbl := sets[sn] as Dictionary
				var line := "    set %s  " % sn
				for lv in range(5):
					var tot := 0.0
					var eft := 0.0
					var soar := 0.0
					var clear_tot := 0.0
					for e in base:
						var k := String(e["key"])
						var g := String(e["g"])
						var w0 := float(e["w"])
						clear_tot += w0
						var m := 1.0
						if tbl.has(g):
							m = float((tbl[g] as Array)[lv])
						## the hard gate: rain_only is unreachable when it is dry
						if bool(CritterDex.flag(k, "rain_only", false)) and lv < 2:
							m = 0.0
						var w := w0 * m
						tot += w
						if k == "red_eft":
							eft += w
						if g == "SOARING":
							soar += w
					var share_eft := 100.0 * eft / tot if tot > 0.0 else 0.0
					var share_soar := 100.0 * soar / tot if tot > 0.0 else 0.0
					var retain := 100.0 * tot / clear_tot if clear_tot > 0.0 else 0.0
					line += "| %s keep%3.0f%% eft%4.1f%% soar%4.1f%% " % [
						LEVELS[lv].substr(0, 2), retain, share_eft, share_soar]
				print(line)


## ----------------------------------------------------------------- noise
func _noise() -> void:
	print("\n--- 3. rain as stealth --------------------------------------")
	## Telegraph.player_noise rings at lerpf(10, 34, loudness). If rain masks
	## the walker, the question is: at what mask does a SPRINT stop reaching a
	## deer that has not already seen you? Those radii are the dex's, not ours.
	for k in ["whitetail", "moose", "hare", "red_squirrel", "turkey", "grouse"]:
		var e := CritterDex.DEX[k] as Dictionary
		var see := e.get("see", [0.0, 0.0]) as Array
		print("  %-13s notice %5.1f m   panic %5.1f m" % [k, float(see[0]), float(see[1])])
	print("  sprint ring 34.0 m, careful walk (0.35) %.1f m" % lerpf(10.0, 34.0, 0.35))
	for mask in [0.85, 0.70, 0.55, 0.40, 0.25]:
		print("  mask %.2f -> sprint rings %5.1f m, walk rings %5.1f m" % [
			mask, 34.0 * mask, lerpf(10.0, 34.0, 0.35) * mask])


## ---------------------------------------------------------------- swarms
func _swarms() -> void:
	print("\n--- 4. the swarms are a SEPARATE door -----------------------")
	## _roll_species skips rig SWARM outright -- swarms come through
	## _try_swarm and its own budget. So the insect half of this feature
	## cannot ride the spawn-weight hook and needs its own.
	for k in CritterDex.DEX.keys():
		if CritterDex.rig_of(String(k)) != "SWARM":
			continue
		print("  %-11s audio_only=%s harasses=%s" % [String(k),
			bool(CritterDex.flag(String(k), "audio_only", false)),
			bool(CritterDex.flag(String(k), "harasses", false))])
