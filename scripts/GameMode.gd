class_name GameMode
extends RefCounted

## ===========================================================================
## THE THREE WAYS TO PLAY — Peaceful / Normal / Hardcore   docs/GAME_MODES.md
##
## One static switch the whole game reads. Nothing here ticks and nothing here
## is a node: every system asks GameMode a question at the exact moment it
## matters and gets a number or a yes/no back. That means the switch in
## Settings lands on the very next swing — no restart, no reload — the same
## trick Settings -> Blood plays on HitFX.blood_enabled.
##
## PEACEFUL   Nothing picks the fight with you. The bear still rears up, huffs
##            and holds its ground; the moose still stamps; the boar still
##            turns and snorts — none of them ever COMMIT unless you swing
##            first, and one you do swing on is a real animal again for the
##            rest of the fight (Enemy.provoked never clears).
##            The caves stay caves: what lives down there still hunts you,
##            because a cave that cannot hurt you is just a room — but ONLY
##            down there. A monster standing in daylight is off the clock
##            (may_engage asks mob_in_cave), and the moment the switch is
##            thrown, everything OUTSIDE a cave stands down instantly with
##            its grudge wiped — the surface amnesty in settle(). It is only
##            much less lethal — half-size packs, a shorter notice radius, and
##            every creature blow at 40%. Wounds close about three times
##            faster and start closing sooner.
##            What Peaceful deliberately does NOT touch: the ground at the
##            bottom of a fall, fire, drowning, a felled trunk coming down on
##            your back. Peaceful is a rule about things with teeth, not a
##            rule about physics — same call Minecraft makes.
##
## NORMAL     The game as built. Every multiplier below is exactly 1.0 and
##            every gate is open. This is the path everything was tuned on.
##
## HARDCORE   Normal, meaner — and you get ONE. Creature blows land 20%
##            harder and wounds close slower, but the real difference is the
##            ending: die once and the run is over. The slot is sealed with a
##            tombstone (SaveGame.seal) and Load refuses it from then on, in
##            this session and every session after it. "New Run" in Settings
##            is the only way forward, and it starts you with nothing.
##
## HOW OTHER SCRIPTS USE IT (all duck-typed on purpose — GameMode must never
## name Enemy/Critter/Player, or the class table goes cyclic):
##   Enemy._physics_process   may_engage() gates waking up, aggro_mult() the radius
##   Enemy.take_damage        sets `provoked`
##   Critter._do_bluffer      may_engage() gates the charge at the top of the ladder
##   Player.take_damage       creature_damage_mult()
##   Player regen             heal_rate_mult() / heal_delay_mult()
##   CaveRegion._spawn_pack   pack_count()
##   CritterSwarm             swarm_damage_mult()
## ===========================================================================

enum Mode { PEACEFUL, NORMAL, HARDCORE }

const KEYS: Array[String] = ["peaceful", "normal", "hardcore"]
const NAMES: Array[String] = ["Peaceful", "Normal", "Hardcore"]

## ------------------------------- the dials --------------------------------
## Every Peaceful/Hardcore number in the game is one of these nine constants.
## Tune here; nothing else needs touching.
const PEACE_CREATURE_DAMAGE := 0.40   ## every bite, swing and gore, at 40%
const PEACE_MONSTER_AGGRO := 0.55     ## cave dwellers notice you this late
const PEACE_PACK := 0.5               ## and come in packs this much smaller
const PEACE_HEAL_RATE := 3.0          ## wounds close three times as fast
const PEACE_HEAL_DELAY := 0.35        ## and start closing after ~1s, not 3
const PEACE_SWARM := 0.0              ## blackflies still swarm, never bite

const HARD_CREATURE_DAMAGE := 1.20
const HARD_HEAL_RATE := 0.60
const HARD_HEAL_DELAY := 1.60

static var mode: int = Mode.NORMAL
## HARDCORE: this character died. Set for the session by Player._die; the
## matching permanent mark lives on disk as SaveGame's tombstone.
static var run_lost := false


## ============================== The switch =================================


static func is_peaceful() -> bool:
	return mode == Mode.PEACEFUL


static func is_hardcore() -> bool:
	return mode == Mode.HARDCORE


static func key() -> String:
	return KEYS[clampi(mode, 0, KEYS.size() - 1)]


static func mode_name() -> String:
	return NAMES[clampi(mode, 0, NAMES.size() - 1)]


static func from_key(k: String) -> int:
	var i := KEYS.find(k)
	return i if i >= 0 else int(Mode.NORMAL)


static func set_mode(m: int, tree: SceneTree = null) -> void:
	mode = clampi(m, 0, KEYS.size() - 1)
	if mode != Mode.HARDCORE:
		## Leaving Hardcore lifts the session seal. The tombstone on the save
		## file itself does NOT lift — that run is still dead, it just stops
		## being your problem.
		run_lost = false
	settle(tree)


## ============================ Who may fight ================================


static func is_creature(who: Variant) -> bool:
	## Everything alive answers to "monster": Enemy declares the property and
	## every subclass inherits it. Environment damage arrives with no attacker
	## at all — which is exactly how it keeps paying full price.
	if who == null or not (who is Object):
		return false
	if not is_instance_valid(who as Object):
		return false
	return "monster" in who


static func is_monster(who: Variant) -> bool:
	## A monster is a thing that hunts you because that is what it IS — the
	## cave dwellers. Wildlife, boars and horses are not monsters no matter
	## how badly a moose has gone for you in the past.
	return is_creature(who) and bool((who as Object).get("monster"))


static func mob_in_cave(mob: Variant) -> bool:
	## Where the Peaceful monster exemption STOPS (Lemon, 2026-08-29): a
	## monster is only exempt while it is actually underground. Duck-typed
	## through the "cave_regions" group (naming CaveRegion here would go
	## cyclic, same rule as everything else in this file) — any region that
	## answers contains_point() gets asked.
	if not (mob is Node3D):
		return false
	var n := mob as Node3D
	if not n.is_inside_tree():
		return false
	for r in n.get_tree().get_nodes_in_group("cave_regions"):
		if r != null and (r as Node).has_method("contains_point") \
				and bool((r as Node).call("contains_point", n.global_position)):
			return true
	return false


static func may_engage(mob: Variant, target: Variant) -> bool:
	## Peaceful's one rule: nothing starts it. Three exemptions, in order —
	## a creature squaring up to ANOTHER creature (never was your business),
	## a monster (the caves stay dangerous), and anything you hit first.
	if mode != Mode.PEACEFUL:
		return true
	if not is_creature(mob):
		return true
	if target is Node and not (target as Node).is_in_group("player"):
		return true
	if is_monster(mob):
		## The caves stay caves — but ONLY the caves (Lemon, 2026-08-29). A
		## goblin standing in daylight on Peaceful is off the clock: the
		## monster exemption applies underground and nowhere else.
		return mob_in_cave(mob)
	return "provoked" in mob and bool((mob as Object).get("provoked"))


static func aggro_mult(mob: Variant) -> float:
	## Peaceful pulls the cave dwellers' eyesight in. Everything else keeps
	## its own radius — it is allowed to NOTICE you all day, it simply is not
	## allowed to do anything about it (see may_engage).
	if mode == Mode.PEACEFUL and is_monster(mob):
		return PEACE_MONSTER_AGGRO
	return 1.0


## ============================== The numbers ================================


static func creature_damage_mult(attacker: Variant) -> float:
	## Scales ONLY a blow thrown by something alive. A fall, a fire, a trunk
	## on your back and the fog past the dead coast all arrive with no
	## attacker and are charged in full, in every mode.
	if not is_creature(attacker):
		return 1.0
	match mode:
		Mode.PEACEFUL:
			return PEACE_CREATURE_DAMAGE
		Mode.HARDCORE:
			return HARD_CREATURE_DAMAGE
	return 1.0


static func heal_rate_mult() -> float:
	match mode:
		Mode.PEACEFUL:
			return PEACE_HEAL_RATE
		Mode.HARDCORE:
			return HARD_HEAL_RATE
	return 1.0


static func heal_delay_mult() -> float:
	match mode:
		Mode.PEACEFUL:
			return PEACE_HEAL_DELAY
		Mode.HARDCORE:
			return HARD_HEAL_DELAY
	return 1.0


static func swarm_damage_mult() -> float:
	## The blackflies are Maine, not a monster: on Peaceful the cloud still
	## finds you, still sounds like that, and still wants smoke — it just
	## never takes anything off the bar.
	return PEACE_SWARM if mode == Mode.PEACEFUL else 1.0


static func pack_count(n: int) -> int:
	## Half a pack, never an empty pocket: a chamber that spawned four orcs
	## spawns two, and one that spawned one still spawns one.
	if mode != Mode.PEACEFUL:
		return n
	if n <= 0:
		return n
	return maxi(1, int(round(float(n) * PEACE_PACK)))


## =========================== Landing the switch ============================


static func settle(tree: SceneTree) -> void:
	## Peace has to land on the fight you are ALREADY in, or the switch is a
	## lie for the next thirty seconds. Anything mid-hunt that would no longer
	## be allowed to start that hunt stands down where it stands.
	if tree == null:
		return
	var pl: Node = tree.get_first_node_in_group("player")
	for n in tree.get_nodes_in_group("enemies"):
		if n == null or not is_instance_valid(n):
			continue
		## SURFACE AMNESTY (Lemon, 2026-08-29): flipping to Peaceful pardons
		## everything under the open sky ON THE SPOT — provoked animals and
		## surfaced monsters alike stand down the frame the switch lands.
		## Only the caves keep their grudges. Hit something again afterwards
		## and it is a real animal again: the amnesty is the switch itself,
		## not a new rule of engagement.
		if mode == Mode.PEACEFUL and "provoked" in n and not mob_in_cave(n):
			(n as Object).set("provoked", false)
		if may_engage(n, pl):
			continue
		if n.has_method("peace_settle"):
			n.call("peace_settle")
