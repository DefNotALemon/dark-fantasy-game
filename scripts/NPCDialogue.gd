class_name NPCDialogue
extends RefCounted
## ===========================================================================
## What people SAY. Two halves:
##
##  1. BARKS — one-liners by situation and personality: `line(npc, key)`.
##     "hello", "cold", "retort", "fight", "retreat", "weapon", "warn",
##     "cower", "hit", "sneak", "murder", "farewell", "busy", "night".
##
##  2. TREES — a talk is a dictionary of nodes:
##       {id: {"text": String | [String...],
##              "choices": [{"text": .., "to": id, "if": cond, "do": action}],
##              "end": bool}}
##     with a tiny condition / action vocabulary evaluated over a CONTEXT
##     dictionary (disposition, flags, met, hour, sky, gold, weapon_out,
##     grudge, job). `default_tree(npc)` writes one per job so every person
##     has something to say on day one; an NPC's own `dialogue` overrides it.
##
## Everything here is a pure function of its arguments — no node, no clock,
## no self — so the suite can drive the whole vocabulary without a world.
## ===========================================================================

const PERSONALITIES := ["friendly", "gruff", "wary", "cheerful", "dour"]

## key -> personality (or "*") -> lines. {name} = the speaker, {tod} = time-of-day word.
const LINES := {
	"hello": {
		"friendly": ["Good {tod} to you.", "Well met, stranger.", "{tod_cap}. Fine one, isn't it?"],
		"gruff": ["Hm.", "{tod_cap}.", "What."],
		"wary": ["...{tod}.", "Don't know you.", "Keep walking, friend."],
		"cheerful": ["Ha! Good {tod}!", "Look who's on the road!", "Well now! {tod_cap} to you!"],
		"dour": ["{tod_cap}, for what it's worth.", "Another day.", "Aye."],
	},
	"cold": {
		"*": ["I've nothing to say to you.", "Get away from me.", "Not after what you did."],
	},
	"retort": {
		"friendly": ["No call for that.", "I'll pretend I didn't hear it.", "Easy, now."],
		"gruff": ["Say it again.", "Big words.", "You want to try me?"],
		"wary": ["Leave me be.", "I want no trouble.", "Just go."],
		"cheerful": ["Ha. Someone woke up sour.", "Bit early for that, isn't it?", "You're a charmer."],
		"dour": ["Heard worse.", "That all?", "Mm."],
	},
	"fight": {
		"*": ["That's enough!", "You asked for it.", "Right, then!", "Come on, then!"],
		"guard": ["Halt! You'll answer for that.", "Stand down, or I'll put you down.", "That's a crime, stranger."],
	},
	"retreat": {
		"*": ["Leave me alone!", "I'm going, I'm going!", "Somebody!"],
	},
	"weapon": {
		"friendly": ["Careful with that thing.", "You can put that away.", "No need for steel here."],
		"gruff": ["Sheathe it or use it.", "Point that somewhere else.", "Steel out. Brave."],
		"wary": ["Please... put it away.", "What do you want with that?", "I've nothing worth taking."],
		"cheerful": ["Whoa there! Chopping wood, are we?", "Steady! I'm not a tree.", "Ha — mind where you swing that."],
		"dour": ["Go on, then.", "Of course. Steel.", "It's always steel."],
	},
	"warn": {
		"*": ["Careful where you point that.", "Last warning.", "I said put it away."],
	},
	"cower": {
		"*": ["Don't! Please!", "I've nothing! Nothing!", "Mercy!", "Take what you want, just—"],
	},
	"hit": {
		"*": ["Ah! Why?!", "Help! Help me!", "Stop! Stop!"],
	},
	"sneak": {
		"friendly": ["...You alright back there?", "What are you doing down there?", "Lost something?"],
		"gruff": ["I can see you, you know.", "Get up. You look ridiculous.", "Sneaking. At me. Really."],
		"wary": ["Who's there?!", "Don't— what are you doing?", "Stay back!"],
		"cheerful": ["Playing at hunters, are we?", "Boo. There, I found you.", "Ha! Lost a coin?"],
		"dour": ["Mm. Skulking.", "I'd stand up if I were you.", "Seen you."],
	},
	"murder": {
		"*": ["Murder! MURDER!", "Gods— run!", "They've killed him!", "Get away from me!"],
	},
	"farewell": {
		"friendly": ["Safe roads.", "Mind the woods after dark.", "Go well."],
		"gruff": ["Aye.", "Off you go.", "Mm."],
		"wary": ["Go on, then.", "...Right.", "Good."],
		"cheerful": ["Ha! Till next time!", "Don't be a stranger!", "Off with you!"],
		"dour": ["We'll see.", "Aye. Roads.", "Go on."],
	},
	"busy": {
		"*": ["Not now.", "Working.", "In a moment."],
	},
	"night": {
		"*": ["It's late.", "Shouldn't be out, this hour.", "Get to a fire, stranger."],
	},
}

## Hub choices every tree shares. `if` is a condition string, `do` an action.
const COMMON_CHOICES := [
	{"text": "Who are you?", "to": "who"},
	{"text": "What is this place?", "to": "place"},
	{"text": "Any news?", "to": "news"},
	{"text": "How's the sky been?", "to": "sky"},
	{"text": "Could you spare some bread?", "to": "food", "if": "disp>=25 and !flag:fed_today"},
	{"text": "Farewell.", "to": "bye"},
]

const NEWS_POOL := [
	"Wolves came down to the road last week. Two sheep. Nobody saw them go.",
	"They say a tree fell across the Freeport road and lay there three days.",
	"The pedlar hasn't come through this month. That's not like him.",
	"Something's been at the woodpiles. Not a bear. Bears don't stack.",
	"A courier came through saying the coast fog's thicker than it was.",
	"There was a light on Katahdin. Hunters, probably. Probably.",
	"Somebody's croft went cold up the valley. Nobody's gone to look.",
	"The river's high. Don't try the ford after rain.",
]

const SKY_LINES := [
	"Clear as a bell. Make the most of it.",
	"Grey. Holding, but grey.",
	"Drizzle all morning. Nothing dries.",
	"Rain like this and the road's a river.",
	"A gale. Bar the shutters and don't go out in it.",
]


## ------------------------------------------------------------- barks ------

static func tod_word(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h < 5.0:
		return "night"
	if h < 12.0:
		return "morning"
	if h < 17.5:
		return "afternoon"
	if h < 21.0:
		return "evening"
	return "night"


static func pick(pool: Array, seed_v: int) -> String:
	if pool.is_empty():
		return ""
	return String(pool[absi(seed_v) % pool.size()])


static func line_for(key: String, personality: String, job: String, hour: float, npc_name: String, seed_v: int) -> String:
	## Pure: the bark for a situation, personality first, job second, "*" last.
	var table: Dictionary = LINES.get(key, {})
	var pool: Array = []
	if table.has(job):
		pool = table[job]
	elif table.has(personality):
		pool = table[personality]
	elif table.has("*"):
		pool = table["*"]
	if pool.is_empty():
		return ""
	var s := pick(pool, seed_v)
	var tod := tod_word(hour)
	return s.replace("{tod_cap}", tod.capitalize()).replace("{tod}", tod).replace("{name}", npc_name)


static func line(npc: Node, key: String) -> String:
	## The bark for THIS person now (reads their clock through the NPC).
	if npc == null:
		return ""
	var hour := 12.0
	if npc.has_method("hour_now"):
		hour = float(npc.call("hour_now"))
	var seed_v := randi()
	return line_for(key, String(npc.get("personality")), String(npc.get("job")), hour, String(npc.get("npc_name")), seed_v)


## ------------------------------------------------------------- vocabulary -

static func eval_cond(cond: String, ctx: Dictionary) -> bool:
	## "" is true. Terms joined by " and ", each optionally negated with "!":
	##   disp>=N  disp>N  disp<=N  disp<N   flag:NAME   met   grudge   weapon_out
	##   gold>=N  hour>=H  hour<H   job:NAME   sky>=N   personality:NAME
	## An unknown term is FALSE (a typo must not open a door).
	var c := cond.strip_edges()
	if c == "":
		return true
	for raw in c.split(" and "):
		var term := String(raw).strip_edges()
		if term == "":
			continue
		var want := true
		if term.begins_with("!"):
			want = false
			term = term.substr(1).strip_edges()
		if _term(term, ctx) != want:
			return false
	return true


static func _term(term: String, ctx: Dictionary) -> bool:
	var disp := float(ctx.get("disp", 0.0))
	var flags: Dictionary = ctx.get("flags", {})
	if term == "met":
		return bool(ctx.get("met", false))
	if term == "grudge":
		return bool(ctx.get("grudge", false))
	if term == "weapon_out":
		return bool(ctx.get("weapon_out", false))
	if term.begins_with("flag:"):
		return flags.has(term.substr(5)) and bool(flags[term.substr(5)])
	if term.begins_with("job:"):
		return String(ctx.get("job", "")) == term.substr(4)
	if term.begins_with("personality:"):
		return String(ctx.get("personality", "")) == term.substr(12)
	for pair in [["disp", disp], ["gold", float(ctx.get("gold", 0))], ["hour", float(ctx.get("hour", 12.0))], ["sky", float(ctx.get("sky", 0))]]:
		var k := String(pair[0])
		var v := float(pair[1])
		if term.begins_with(k):
			var rest := term.substr(k.length())
			for op in [">=", "<=", ">", "<", "=="]:
				if rest.begins_with(op):
					var num := float(rest.substr(op.length()))
					match op:
						">=":
							return v >= num
						"<=":
							return v <= num
						">":
							return v > num
						"<":
							return v < num
						_:
							return is_equal_approx(v, num)
	return false


static func parse_actions(action: String) -> Dictionary:
	## "disp+5; flag:helped; gold-3; give:Bread; act:wave; hostile; end" ->
	## {"disp": 5.0, "flags_set": [..], "flags_clear": [..], "gold": -3,
	##  "give": ["Bread"], "act": "wave", "hostile": false, "end": true}
	var out := {"disp": 0.0, "flags_set": [], "flags_clear": [], "gold": 0, "give": [], "act": "", "hostile": false, "end": false}
	for raw in action.split(";"):
		var a := String(raw).strip_edges()
		if a == "":
			continue
		if a.begins_with("disp"):
			out["disp"] = float(out["disp"]) + float(a.substr(4))
		elif a.begins_with("flag:"):
			(out["flags_set"] as Array).append(a.substr(5))
		elif a.begins_with("unflag:"):
			(out["flags_clear"] as Array).append(a.substr(7))
		elif a.begins_with("gold"):
			out["gold"] = int(out["gold"]) + int(a.substr(4))
		elif a.begins_with("give:"):
			(out["give"] as Array).append(a.substr(5))
		elif a.begins_with("act:"):
			out["act"] = a.substr(4)
		elif a == "hostile":
			out["hostile"] = true
		elif a == "end":
			out["end"] = true
	return out


static func choices_for(node: Dictionary, ctx: Dictionary) -> Array:
	## The choices the player may actually pick right now.
	var out: Array = []
	for c in node.get("choices", []):
		if c is Dictionary and eval_cond(String((c as Dictionary).get("if", "")), ctx):
			out.append(c)
	return out


static func text_of(node: Dictionary, ctx: Dictionary, seed_v: int) -> String:
	## The line to show: a string, or one of several, with {name} / {tod}
	## / {place} filled in.
	var t = node.get("text", "")
	var s := ""
	if t is Array:
		s = pick(t as Array, seed_v)
	else:
		s = String(t)
	var tod := tod_word(float(ctx.get("hour", 12.0)))
	return s.replace("{tod_cap}", tod.capitalize()).replace("{tod}", tod) \
		.replace("{name}", String(ctx.get("name", ""))).replace("{place}", String(ctx.get("place", "these parts"))) \
		.replace("{sky}", sky_line(int(ctx.get("sky", 0))))


static func first_node(tree: Dictionary, ctx: Dictionary) -> String:
	## Where a talk opens: the tree's "start" unless a gated opener applies
	## (a grudge, a stranger, an old friend). Openers are listed under
	## tree["openers"] = [{"if": cond, "to": id}] and taken in order.
	for o in tree.get("openers", []):
		if o is Dictionary and eval_cond(String((o as Dictionary).get("if", "")), ctx):
			return String((o as Dictionary).get("to", "start"))
	return "start"


static func validate(tree: Dictionary) -> Array:
	## Every choice must point at a node that exists; "start" must exist.
	## Returns the problems (empty = fine).
	var problems: Array = []
	if not tree.has("start"):
		problems.append("no start node")
	for id in tree.keys():
		if id == "openers":
			for o in tree[id]:
				if not tree.has(String((o as Dictionary).get("to", ""))):
					problems.append("opener -> missing node %s" % String((o as Dictionary).get("to", "")))
			continue
		var node = tree[id]
		if not (node is Dictionary):
			problems.append("%s is not a node" % String(id))
			continue
		for c in (node as Dictionary).get("choices", []):
			var to := String((c as Dictionary).get("to", ""))
			if not tree.has(to):
				problems.append("%s -> missing node %s" % [String(id), to])
	return problems


## ------------------------------------------------------------- trees ------

static func default_tree(job: String, personality: String) -> Dictionary:
	## One talk per job. Every node's choices lead somewhere that exists —
	## validate() is asserted over every job in the suite.
	var who := ""
	match job:
		"crofter":
			who = "I keep the croft up the way. Two beasts, a plot, and a woodpile that's never tall enough. Autumn's for the pile; winter's for finding out if you kept it."
		"woodcutter":
			who = "I cut. Notch the trunk on the side you want it to fall and stand on the other. Cut what you need, plant what you cut."
		"fisher":
			who = "Fisher. The lakes feed us and the lakes take a few back. Don't swim them after dark, whatever you hear from the water."
		"guard":
			who = "I keep the peace here, such as it is. Steel stays sheathed in the village. That's the whole law."
		"merchant":
			who = "I trade. Or I will, when the carts get through again. Roads are a river every time it rains."
		"priest":
			who = "I keep the chapel and bury who needs burying. There's been more of the second lately."
		_:
			who = "Nobody. I live here. Chop wood, carry water, mind the fire, same as everyone."
	var start_text: Array = []
	match personality:
		"gruff":
			start_text = ["What do you want?", "Speak, then."]
		"wary":
			start_text = ["...Yes?", "What is it? Quickly."]
		"cheerful":
			start_text = ["Ha! A visitor! What can I do for you?", "Well now! Talk to me, stranger."]
		"dour":
			start_text = ["Go on.", "Say your piece."]
		_:
			start_text = ["Good {tod}. What can I do for you?", "Well met. Something on your mind?"]
	var tree := {
		"openers": [
			{"if": "grudge", "to": "grudge"},
			{"if": "weapon_out", "to": "steel"},
			{"if": "met and disp>=30", "to": "friend"},
			{"if": "met", "to": "again"},
		],
		"start": {"text": start_text, "choices": COMMON_CHOICES},
		"again": {"text": ["You again. Well?", "Back so soon? What is it?"], "choices": COMMON_CHOICES},
		"friend": {"text": ["Good to see you, friend. What do you need?", "Ah, it's you! Sit, talk."], "choices": COMMON_CHOICES},
		"grudge": {"text": "I remember you. I've nothing to say and I'll thank you to go.", "choices": [
			{"text": "I'm sorry for what happened.", "to": "sorry", "if": "!flag:apologised"},
			{"text": "Fine.", "to": "bye_cold"},
		]},
		"sorry": {"text": "...Words are cheap. But they're something. Go on, then.", "choices": COMMON_CHOICES, "do": "flag:apologised; disp+15"},
		"steel": {"text": "Put that away before we talk. I mean it.", "choices": [
			{"text": "Make me.", "to": "bye_cold", "do": "disp-10"},
			{"text": "Alright.", "to": "start", "do": "disp-2"},
		]},
		"who": {"text": who, "choices": [{"text": "I see.", "to": "hub"}]},
		"place": {"text": "This is {place}. Was a quieter country once, they say. Now the woods have things in them and the roads have fewer people on them every year.", "choices": [{"text": "I see.", "to": "hub"}]},
		"news": {"text": NEWS_POOL, "choices": [
			{"text": "Anything else?", "to": "news2"},
			{"text": "Thanks.", "to": "hub"},
		]},
		"news2": {"text": NEWS_POOL, "choices": [{"text": "Thanks.", "to": "hub"}]},
		"sky": {"text": "{sky}", "choices": [{"text": "I see.", "to": "hub"}]},
		"food": {"text": "Here. It's not much, but it's bread. Don't tell everyone.", "do": "give:Bread; flag:fed_today; disp+3", "choices": [{"text": "Thank you.", "to": "hub"}]},
		"hub": {"text": ["Anything else?", "Something else?", "Well?"], "choices": COMMON_CHOICES},
		"bye": {"text": ["Safe roads.", "Go well.", "Mind the woods after dark."], "end": true, "do": "disp+1"},
		"bye_cold": {"text": "Hm.", "end": true},
	}
	match job:
		"merchant":
			(tree["start"] as Dictionary)["choices"] = _with(COMMON_CHOICES, {"text": "What have you got for sale?", "to": "trade"})
			(tree["hub"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["again"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["friend"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			tree["trade"] = {"text": "Nothing today. The carts haven't come through since the rain. Come back and ask again.", "choices": [{"text": "I'll do that.", "to": "hub"}]}
		"priest":
			(tree["start"] as Dictionary)["choices"] = _with(COMMON_CHOICES, {"text": "Would you bless me?", "to": "bless", "if": "!flag:blessed"})
			(tree["hub"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["again"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["friend"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			tree["bless"] = {"text": "Go with what light there is. Keep to the roads and keep your fire.", "do": "flag:blessed; disp+4; act:bow", "choices": [{"text": "Thank you.", "to": "hub"}]}
		"guard":
			(tree["start"] as Dictionary)["choices"] = _with(COMMON_CHOICES, {"text": "Any trouble lately?", "to": "trouble"})
			(tree["hub"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["again"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			(tree["friend"] as Dictionary)["choices"] = (tree["start"] as Dictionary)["choices"]
			tree["trouble"] = {"text": "Wolves on the road, a croft gone quiet, and a stranger with a sword asking me about trouble. Keep it sheathed and we'll get along.", "choices": [{"text": "Understood.", "to": "hub"}]}
	return tree


static func _with(base: Array, extra: Dictionary) -> Array:
	## COMMON_CHOICES plus one, inserted before "Farewell."
	var out := base.duplicate(true)
	out.insert(maxi(0, out.size() - 1), extra)
	return out


static func tree_for(npc: Node) -> Dictionary:
	if npc == null:
		return default_tree("villager", "friendly")
	var own = npc.get("dialogue")
	if own is Dictionary and not (own as Dictionary).is_empty():
		return own
	return default_tree(String(npc.get("job")), String(npc.get("personality")))


static func context_for(npc: Node, player: Node, sky: int, place: String) -> Dictionary:
	## The dictionary the vocabulary reads. Built by NPCFocus each time a
	## talk opens or a choice is taken.
	var ctx := {
		"disp": 0.0, "flags": {}, "met": false, "grudge": false, "weapon_out": false,
		"gold": 0, "hour": 12.0, "sky": sky, "job": "villager", "personality": "friendly",
		"name": "", "place": place,
	}
	if npc != null:
		ctx["disp"] = float(npc.get("disposition"))
		ctx["flags"] = npc.get("flags")
		ctx["grudge"] = bool(npc.get("grudge"))
		ctx["job"] = String(npc.get("job"))
		ctx["personality"] = String(npc.get("personality"))
		ctx["name"] = String(npc.get("npc_name"))
		if npc.has_method("hour_now"):
			ctx["hour"] = float(npc.call("hour_now"))
		## "met" = we have talked before. Build the context BEFORE begin_talk
		## stamps met_day, or every first talk reads as a second one.
		ctx["met"] = int(npc.get("met_day")) >= 0
	if player != null:
		if "gold" in player:
			ctx["gold"] = int(player.get("gold"))
		var st: float = float(player.get("sheath_t")) if "sheath_t" in player else 1.0
		var w: String = String(player.get("current_weapon")) if "current_weapon" in player else ""
		ctx["weapon_out"] = st < 0.5 and w != ""
	return ctx


static func sky_line(level: int) -> String:
	return SKY_LINES[clampi(level, 0, SKY_LINES.size() - 1)]
