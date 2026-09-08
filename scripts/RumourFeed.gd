class_name RumourFeed
extends CanvasLayer

## ===========================================================================
## THE RUMOUR FEED — the first thing in Myrkfell that can hear the Chronicle.
##
## Since 2026-09-06 fifty-one places have been living their own lives on the
## sky's calendar: wolves at the fold at Sebec, a caravan overdue on the
## Freeport road, ice out early at Bingham. Every one of those resolved into a
## sentence a person would say in a tavern, and every one of those sentences
## was dropped into the boards of every place within a day's walk — and then
## nothing, anywhere in the game, ever read one. Fifty-one places simulating
## and not a word of it on screen.
##
## This is the ear. Walk into earshot of a place and you start catching the
## talk: one line at a time, freshest first, each held long enough to read and
## then let go. Walk out and it stops — news does not follow you into the
## woods. You are never told the same thing twice, in this session or in any
## later one, because what you have heard rides in the save.
##
## FOUR RULES this file keeps:
##
##   1. **It only reads.** The Chronicle is a simulation, not a message queue.
##      Nothing in here fires an event, moves a place's numbers or touches the
##      bias pool. Delete this file and the world is exactly the same world.
##   2. **Earshot is small.** `Chronicle.rumours_at` answers from a day's walk
##      away (RUMOUR_SPREAD, 1400 m) because that is how far news travels.
##      That is the wrong radius for *overhearing* it: at 1400 m you would be
##      told the gossip of a village you cannot see. EARSHOT is the radius of
##      being there.
##   3. **Nothing it does can be a hitch.** The sense pass runs four times a
##      second and is one distance loop over fifty places; the frame pass is a
##      lerp on at most three labels. No allocation in `_advance`.
##   4. **Every collaborator is nullable.** No player, no Chronicle, no
##      viewport: it sits there quietly. That is what lets the suite run the
##      whole state machine headless with nothing but a Chronicle and a
##      Node3D standing in for a body.
##
## Wired up by World.gd (tools/patch_rumours.py):
##     _rumours = RumourFeed.new(); add_child(_rumours); _rumours.boot()
## and its heard-set rides in `save_state()["rumours"]`.
##
## NO INPUT. This file has no input callbacks, no input-map actions and no
## key constants in it, on purpose: it adds no binding and can shadow none.
## RumourFeedTests asserts that against the source rather than trusting this
## comment. It reads `Player.menu_open`, `wheel_open` and `input_locked` only
## to know when to get out of the way.
##
## A node added to `root` from `SceneTree._init()` never gets `_ready()` —
## which is how StepAudio was caught out on 2026-09-05 — so `boot()` is an
## explicit, idempotent setup call the headless suite makes for itself.
## ===========================================================================

## How near you have to be to a place to hear what it is saying. About four
## minutes' walk: close enough that the place is in front of you, far enough
## that you catch the talk on the way in rather than on the doorstep.
const EARSHOT := 260.0
## How often the world is asked where you are and what is being said. Four
## times a second is far finer than a person walks between villages, and it
## keeps the per-frame path free of any lookup at all.
const POLL := 0.25
## Reading speed, characters a second, plus a beat to find the line. These
## produce ~4.5 s for a short line and ~7 s for a long one.
const READ_CPS := 15.0
const READ_LEAD := 1.4
const DWELL_MIN := 3.4
const DWELL_MAX := 9.0
## In and out. Out is slower than in: news should arrive and then linger.
const FADE_IN := 0.5
const FADE_OUT := 1.0
## Quiet between lines, so the board is a conversation rather than a dump.
const GAP := 1.1
## How many lines stand at once. Three is a glance; four is a wall of text.
const MAX_SHOWN := 3
## The place name shows on arrival and for this long after the last line.
const HEAD_HOLD := 3.0
## How much of what you have heard the save carries. Eight rumours a place
## across fifty-one places is 408 lines in the worst case; 320 keeps a long
## game honest without the save growing forever.
const HEARD_KEEP := 320
## A line that arrives while you are standing there is worth an extra beat.
const LIVE_BONUS := 1.6

const LINE_SIZE := 17
const HEAD_SIZE := 13
const MARGIN_X := 46.0
const TOP_FRAC := 0.26          ## where the stack starts, as a fraction of height
const ROW_GAP := 9.0            ## breathing room between one rumour and the next
const SLIDE := 12.0             ## how far a line slides in from the left
## The talk is set in a COLUMN, not across the screen. The catalogue's longest
## outcome line is 150-odd characters, which at 17px is wider than a 1280 window
## and most of a 1080p one -- so it wraps into a readable measure instead, and
## the measure is clamped at both ends so it is neither a ransom note on a
## narrow window nor a full-width banner on an ultrawide.
const WRAP_MIN := 380.0
const WRAP_MAX := 720.0
const WRAP_FRAC := 0.44


## The live instance, found the way Telegraph and the Chronicle find
## themselves — never assumed to exist.
static var inst: RumourFeed = null


var enabled := true
## Both resolved lazily, both allowed to stay null forever.
var player: Node3D = null
var chron: Chronicle = null

var _booted := false
var _here := ""                 ## the place whose talk you are in earshot of
var _poll_t := 0.0
var _gap_t := 0.0
var _head_t := 0.0
var _muted := false

var _queue: Array = []          ## rumour dictionaries waiting to be said
var _lines: Array = []          ## {label, text, age, accent, life, full, born, live}
var _heard: Dictionary = {}     ## key -> true
var _heard_order: Array = []    ## the same keys, oldest first, for the FIFO cap

var _head: Label = null
var _root: Control = null

## Counters the console and the suite read. Cheap, and they are the difference
## between "it looks like it works" and "it said forty-one things".
var said := 0
var arrivals := 0


# ============================== Wiring up ==================================


static func get_bus(from: Node) -> RumourFeed:
	if inst != null and is_instance_valid(inst):
		return inst
	if from != null and from.is_inside_tree():
		var n := from.get_tree().get_first_node_in_group("rumours")
		if n is RumourFeed:
			inst = n as RumourFeed
			return inst
	return null


func _ready() -> void:
	boot()


func _exit_tree() -> void:
	if inst == self:
		inst = null


func boot() -> void:
	## Idempotent: World calls it, `_ready` calls it, and the suite calls it
	## three times in a row.
	if _booted:
		return
	_booted = true
	inst = self
	add_to_group("rumours")
	layer = 0                   ## under the HUD's menus, over the world

	_root = Control.new()
	_root.name = "Feed"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_head = Label.new()
	_head.add_theme_font_size_override("font_size", HEAD_SIZE)
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.modulate = Color(1, 1, 1, 0)
	_root.add_child(_head)


# ================================ The ear ==================================


func _process(delta: float) -> void:
	if not _booted or not enabled:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		sense()
	advance(delta)


func _resolve() -> void:
	## Both of these can fail forever and the feed simply stays quiet.
	if player == null or not is_instance_valid(player):
		player = null
		if is_inside_tree():
			var p := get_tree().get_first_node_in_group("player")
			if p is Node3D:
				player = p as Node3D
	if chron == null or not is_instance_valid(chron):
		chron = null
		if is_inside_tree():
			var c := get_tree().get_first_node_in_group("chronicle")
			if c is Chronicle:
				chron = c as Chronicle
	if chron != null and not chron.event_resolved.is_connected(_on_event_resolved):
		chron.event_resolved.connect(_on_event_resolved)


func muted_now() -> bool:
	## Anything that means the player is not looking at the world: a panel is
	## up, the item wheel is out, they are asleep or being carried through a
	## blackout, or they are dead. The feed does not compete with any of it,
	## and — the point of freezing rather than dropping — it does not spend a
	## rumour behind a menu either.
	if player == null or not is_instance_valid(player):
		return true
	if "input_locked" in player and bool(player.input_locked):
		return true
	if "menu_open" in player and String(player.menu_open) != "":
		return true
	if "wheel_open" in player and bool(player.wheel_open):
		return true
	if "health" in player and float(player.health) <= 0.0:
		return true
	return false


func sense() -> void:
	## Where you are, and whether anyone near enough is saying anything new.
	_resolve()
	_muted = muted_now()
	if chron == null or player == null:
		if _here != "":
			_leave()
		return

	var pos: Vector3 = player.global_position
	var place := chron.nearest_place(pos, EARSHOT)
	var nm := String(place.get("name", "")) if not place.is_empty() else ""
	if nm != _here:
		if _here != "":
			_leave()
		_here = nm
		if nm != "":
			arrivals += 1
			_head_t = HEAD_HOLD
			if _head != null:
				_head.text = nm.to_upper()
	if _here == "" or _muted:
		return
	if _queue.size() < MAX_SHOWN:
		_refill()


func _leave() -> void:
	## Out of earshot: the queue is dropped, the standing lines are let go,
	## and the heard-set is kept. Talk does not follow you into the woods.
	_here = ""
	_queue.clear()
	for row in _lines:
		var r := row as Dictionary
		r["life"] = minf(float(r["life"]), FADE_OUT)
	_head_t = 0.0


func _refill() -> void:
	## Chronicle.rumours_at does the sort (freshest first, tiebroken on the
	## text so the order is total) — reusing it rather than re-sorting here
	## means the feed and the board can never disagree about what is newest.
	var pos: Vector3 = player.global_position
	for r in chron.rumours_at(pos, Chronicle.RUMOURS_PER_PLACE):
		if not (r is Dictionary):
			continue
		var rd := r as Dictionary
		var k := key_for(_here, String(rd.get("text", "")))
		if _heard.has(k) or _queued(k):
			continue
		_queue.append(rd)
		if _queue.size() >= MAX_SHOWN:
			return


func _queued(k: String) -> bool:
	for q in _queue:
		if key_for(_here, String((q as Dictionary).get("text", ""))) == k:
			return true
	return false


func _on_event_resolved(ev: Dictionary) -> void:
	## Word arriving while you are standing in the place it is about goes to
	## the front. This is the one moment the feed is not a poll: a fold lost
	## at Sebec while you are at Sebec should not wait its turn behind three
	## days of gossip.
	if _here == "" or String(ev.get("place", "")) != _here:
		return
	var text := String(ev.get("line", ""))
	if text.is_empty():
		return
	var k := key_for(_here, text)
	if _heard.has(k) or _queued(k):
		return
	_queue.push_front({
		"text": text,
		"day": float(ev.get("born", chron.days if chron != null else 0.0)),
		"from": _here,
		"kind": String(ev.get("kind", "")),
		"live": true,
	})
	_gap_t = 0.0


# ============================== The frame ==================================


func advance(delta: float) -> void:
	## Everything time does to what is on screen. Split out from `_process`
	## so the suite can run the state machine a frame at a time without a
	## tree pumping it.
	if _muted:
		## FROZEN, not dropped: the lines fade but keep their remaining life,
		## so closing the map hands you back the sentence you were reading
		## instead of a rumour you have now been marked as having heard.
		for row in _lines:
			(row as Dictionary)["hidden"] = true
		_layout()
		return

	var i := _lines.size() - 1
	while i >= 0:
		var row := _lines[i] as Dictionary
		row["hidden"] = false
		row["life"] = float(row["life"]) - delta
		row["born"] = float(row["born"]) + delta
		if float(row["life"]) <= 0.0:
			var lbl := row.get("label") as Control
			if lbl != null and is_instance_valid(lbl):
				lbl.queue_free()
			_lines.remove_at(i)
		i -= 1

	_gap_t = maxf(0.0, _gap_t - delta)
	_head_t = maxf(0.0, _head_t - delta)
	if not _queue.is_empty() and _lines.size() < MAX_SHOWN and _gap_t <= 0.0:
		_say(_queue.pop_front() as Dictionary)
		_gap_t = GAP
	_layout()


func _say(r: Dictionary) -> void:
	var text := String(r.get("text", ""))
	if text.is_empty():
		return
	var live := bool(r.get("live", false))
	var accent := accent_for(String(r.get("kind", "")))
	if live:
		accent = accent.lightened(0.28)
	var age := 0.0
	if chron != null:
		age = chron.days - float(r.get("day", 0.0))

	var row := {
		"label": null,
		"text": text, "age": age_words(age), "accent": accent,
		"full": dwell_for(text) + (LIVE_BONUS if live else 0.0),
		"life": dwell_for(text) + (LIVE_BONUS if live else 0.0),
		"born": 0.0, "live": live, "hidden": false,
	}
	if _root != null and is_instance_valid(_root):
		## A RichTextLabel rather than a Label so the line and the age it
		## carries are one wrapped paragraph in two colours, instead of two
		## boxes that have to be measured against each other and that come
		## apart the moment the text is longer than the window.
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("normal_font_size", LINE_SIZE)
		lbl.text = "[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
			accent.to_html(false), text, AGE_TINT.to_html(false), String(row["age"])]
		_root.add_child(lbl)
		row["label"] = lbl

	_lines.append(row)
	said += 1
	_head_t = maxf(_head_t, HEAD_HOLD)
	mark_heard(_here, text)


func _alpha_for(row: Dictionary) -> float:
	if bool(row.get("hidden", false)):
		return 0.0
	var a := clampf(float(row["born"]) / FADE_IN, 0.0, 1.0)
	var out := clampf(float(row["life"]) / FADE_OUT, 0.0, 1.0)
	## Older lines stand back so the newest is the one being read.
	return minf(a, out)


## The measure the talk is set in, for a viewport of this width. Pure, so the
## suite can hold the readability rule to account instead of somebody eyeballing
## a screenshot: never past WRAP_MAX, never under WRAP_MIN, and never so wide
## that the column runs off the right-hand side of the screen.
static func wrap_width(vp_x: float) -> float:
	return minf(clampf(vp_x * WRAP_FRAC, WRAP_MIN, WRAP_MAX), maxf(vp_x - MARGIN_X * 2.0, 80.0))


func _layout() -> void:
	if _root == null or not is_instance_valid(_root) or not is_inside_tree():
		return
	var vp := _root.get_viewport_rect().size
	if vp.x < 1.0:
		return
	var w := wrap_width(vp.x)
	var y := vp.y * TOP_FRAC
	if _head != null and is_instance_valid(_head):
		var ha := clampf(_head_t / 0.6, 0.0, 1.0)
		if _here == "" or _muted:
			ha = 0.0
		_head.modulate = Color(0.72, 0.70, 0.62, ha * 0.85)
		_head.position = Vector2(MARGIN_X, y - 22.0)
	var n := _lines.size()
	for i in range(n):
		var row := _lines[i] as Dictionary
		var a := _alpha_for(row)
		## The oldest of a full stack stands back, so the eye always lands on
		## the line that just arrived.
		var depth := 1.0 - 0.22 * float(n - 1 - i)
		var lbl := row.get("label") as Control
		var slide := SLIDE * (1.0 - clampf(float(row["born"]) / FADE_IN, 0.0, 1.0))
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.size.x = w
		lbl.custom_minimum_size.x = w
		lbl.modulate.a = a * depth
		lbl.position = Vector2(MARGIN_X - slide, y)
		## Rows are as tall as their own wrapped text: a one-line rumour and a
		## three-line one cannot be stacked on the same pitch without one of
		## them sitting on top of the next.
		var h := float(LINE_SIZE) + 6.0
		if lbl is RichTextLabel:
			h = maxf((lbl as RichTextLabel).get_content_height(), h)
		y += h + ROW_GAP


# ============================ What you have heard ==========================


func mark_heard(place: String, text: String) -> void:
	var k := key_for(place, text)
	if _heard.has(k):
		return
	_heard[k] = true
	_heard_order.append(k)
	while _heard_order.size() > HEARD_KEEP:
		var old := String(_heard_order.pop_front())
		_heard.erase(old)


func has_heard(place: String, text: String) -> bool:
	return _heard.has(key_for(place, text))


func heard_count() -> int:
	return _heard_order.size()


static func key_for(place: String, text: String) -> String:
	## The place is part of the key on purpose. Outcome lines are shared prose
	## and the same sentence can be true of two villages in the same week;
	## being told it once at Bangor should not silence it at Ellsworth.
	return "%s|%s" % [place, text]


static func pick_next(rumours: Array, heard: Dictionary, place: String) -> Dictionary:
	## The first thing in a freshest-first list that has not been said here.
	for r in rumours:
		if not (r is Dictionary):
			continue
		var rd := r as Dictionary
		if heard.has(key_for(place, String(rd.get("text", "")))):
			continue
		return rd
	return {}


# ================================= Prose ===================================


## Read at READ_CPS with a beat to find the line, clamped at both ends: a
## three-word line still gets long enough to notice, and the longest line in
## the catalogue does not park itself on screen for a quarter of a minute.
static func dwell_for(text: String) -> float:
	return clampf(float(text.length()) / READ_CPS + READ_LEAD, DWELL_MIN, DWELL_MAX)


## How old the news is, in the words a person would use. Measured in game
## days against the Chronicle's own clock, so this is the one place in the
## game where the calendar the sim runs on is legible to a player.
const AGE_WORDS: Array = [
	[0.35, "just now"],
	[1.0, "today"],
	[2.0, "yesterday"],
	[3.0, "two days back"],
	[4.0, "three days back"],
	[6.0, "a few days back"],
]


static func age_words(age_days: float) -> String:
	## A clock wound backwards (the sky menu, a load) reads as "just now"
	## rather than as a negative number of days, because the first band has
	## no lower bound.
	for row in AGE_WORDS:
		if age_days < float(row[0]):
			return String(row[1])
	return "last week"


## Tag -> colour, in PRIORITY ORDER: the first tag a kind carries that appears
## in this list wins. The order is the point. `wolves_at_fold` carries
## ["wolves", "livestock", "night", "alarm"] and should read as a threat, not
## as wildlife, so every alarm tag sits above every animal tag.
const ACCENTS: Array = [
	["raid", Color(0.92, 0.34, 0.30)],
	["goblins", Color(0.90, 0.38, 0.34)],
	["bandits", Color(0.90, 0.42, 0.36)],
	["alarm", Color(0.94, 0.52, 0.36)],
	["unrest", Color(0.90, 0.55, 0.42)],
	["fire", Color(0.98, 0.70, 0.30)],
	["sickness", Color(0.72, 0.80, 0.46)],
	["murrain", Color(0.72, 0.80, 0.46)],
	["hunger", Color(0.84, 0.64, 0.40)],
	["wolves", Color(0.64, 0.76, 0.94)],
	["deer", Color(0.70, 0.82, 0.72)],
	["moose", Color(0.70, 0.82, 0.72)],
	["wildlife", Color(0.70, 0.82, 0.72)],
	["storm", Color(0.60, 0.68, 0.82)],
	["weather", Color(0.62, 0.70, 0.80)],
	["ice", Color(0.72, 0.86, 0.92)],
	["sea", Color(0.44, 0.82, 0.80)],
	["boat", Color(0.44, 0.82, 0.80)],
	["fish", Color(0.48, 0.84, 0.78)],
	["river", Color(0.52, 0.78, 0.86)],
	["omen", Color(0.80, 0.68, 0.96)],
	["faith", Color(0.80, 0.68, 0.96)],
	["sky", Color(0.80, 0.68, 0.96)],
	["harvest", Color(0.70, 0.86, 0.52)],
	["fair", Color(0.86, 0.82, 0.56)],
	["trade", Color(0.88, 0.82, 0.54)],
]
const ACCENT_DEFAULT := Color(0.88, 0.84, 0.72)
## The age clause is always the same dim grey, whatever the line it trails.
const AGE_TINT := Color(0.62, 0.60, 0.54)


static func accent_for(kind_id: String) -> Color:
	## An id that is not in the catalogue — a save from a build where the kind
	## was named something else — reads in the default parchment rather than
	## crashing or vanishing.
	var kind := ChronicleEvents.by_id(kind_id)
	if kind.is_empty():
		return ACCENT_DEFAULT
	var tags: Array = kind.get("tags", [])
	for row in ACCENTS:
		if tags.has(String(row[0])):
			return row[1] as Color
	return ACCENT_DEFAULT


# ============================== Save / load ================================


func to_dict() -> Dictionary:
	## Only what cannot be worked out again: what you have already been told.
	## The queue and the standing lines are deliberately NOT saved — loading
	## into the middle of a half-faded sentence would be worse than loading
	## into quiet, and the queue refills from the board on the next poll.
	return {"v": 1, "heard": _heard_order.duplicate()}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or int(d.get("v", 1)) > 1:
		return
	_heard.clear()
	_heard_order.clear()
	for k in (d.get("heard", []) as Array):
		var s := String(k)
		if s.is_empty() or _heard.has(s):
			continue
		_heard[s] = true
		_heard_order.append(s)
	while _heard_order.size() > HEARD_KEEP:
		var old := String(_heard_order.pop_front())
		_heard.erase(old)


func report() -> Dictionary:
	## For the console and the suite.
	return {
		"here": _here,
		"queued": _queue.size(),
		"showing": _lines.size(),
		"heard": _heard_order.size(),
		"said": said,
		"arrivals": arrivals,
		"muted": _muted,
	}


func lines_on_screen() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _lines:
		out.append(String((row as Dictionary)["text"]))
	return out
