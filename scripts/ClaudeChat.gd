class_name ClaudeChat
extends PanelContainer
## ===========================================================================
## CLAUDE, RIDING ALONG -- F4. A live chat with Claude inside the game.
##
## Lemon (2026-09-14): "can you add a live claude chat to the game" -- a dev
## assistant, "but have it take notes for you in haiku and then send it up
## the line." So this is TWO models and a postbag:
##
##   * THE CHAT. F4 drops a card on the left of the screen. You type, Claude
##     answers, streamed token by token, with the game state riding along
##     as context (where you are, the hour, the weather, health, FPS, which
##     menu is up). The game keeps running behind it; the cursor is free
##     while it is open. Backend is a dropdown: ANTHROPIC (api.anthropic.com,
##     Messages API, SSE) or LOCAL (any OpenAI-compatible server on the Mac
##     -- Ollama, LM Studio, oMLX -- at /v1/chat/completions).
##
##   * THE NOTE-TAKER. After every finished exchange a second, cheap call
##     (Haiku) reads the exchange plus the snapshot and writes down anything
##     DURABLE -- a bug seen, an idea, a request, a decision -- as JSON. Those
##     land in user://claude_notes/<date>.md as they happen.
##
##   * UP THE LINE. The "Send up the line" button (and the panel's own exit,
##     if notes are still unsent) writes the notes + the transcript to
##     notes/claude-handoff/<date>-<hhmm>.md in the REPO (user:// when the
##     game is an export and res:// is read-only), which is where the Cowork
##     Claude session that edits this codebase looks for them. Lemon never
##     has to re-type what he noticed while playing.
##
## Config: user://claude.cfg (ConfigFile). The key is read from the
## ANTHROPIC_API_KEY environment variable first, then [anthropic] api_key in
## the cfg -- the panel's KEY field writes the cfg. Nothing here is committed.
##
## Player owns the key: F4 -> Player._toggle_menu("claude") shows and hides
## this panel like every other menu (map, grass lab, spawn), so the cursor,
## Esc and the god panel's overlay arbitration all behave. THIS FILE TAKES NO
## KEY OF ITS OWN from an _input-family callback and registers no action --
## Player asks eat_input() whether a keystroke belongs to the text box, the
## same handshake GodEditor uses for its note fields. ClaudeChatTests scans
## the source for all of this.
##
## Everything network-shaped is a pure function of text where it can be
## (sse_split, anthropic_delta, openai_delta, the body builders, the notes
## parser, the markdown writers) so the suite exercises the parsing without a
## key, and drives the poller end to end against a fake server on localhost.
## ===========================================================================

const CFG_PATH := "user://claude.cfg"
const NOTES_DIR := "user://claude_notes"
const HANDOFF_DIR_RES := "res://notes/claude-handoff"
const HANDOFF_DIR_USER := "user://claude_handoff"

const ANTHROPIC_HOST := "api.anthropic.com"
const ANTHROPIC_PATH := "/v1/messages"
const ANTHROPIC_VERSION := "2023-06-01"
const DEFAULT_CHAT_MODEL := "claude-sonnet-5"
const DEFAULT_NOTES_MODEL := "claude-haiku-4-5-20251001"
const DEFAULT_LOCAL_URL := "http://localhost:8000/v1"
const DEFAULT_LOCAL_MODEL := "default"
const BACKENDS := ["anthropic", "local"]

const MAX_TURNS := 24          ## messages kept in the request window (user+assistant)
const MAX_TOKENS := 1024
const NOTES_MAX_TOKENS := 600
const PANEL_W := 520.0
const PANEL_H := 600.0
const NOTE_KINDS := ["bug", "idea", "request", "decision", "observation"]

## Who's asking. Set by Player after add_child, like GrassLab/MapPanel.
var player: Node = null

## --- where things live (instance copies so a test can point them elsewhere)
var cfg_path := CFG_PATH
var notes_dir := NOTES_DIR
var handoff_override := ""     ## "" = handoff_dir() decides (repo, or user://)

## --- config (user://claude.cfg) --------------------------------------------
var backend := "anthropic"
var api_key := ""
var chat_model := DEFAULT_CHAT_MODEL
var notes_model := DEFAULT_NOTES_MODEL
var local_url := DEFAULT_LOCAL_URL
var local_model := DEFAULT_LOCAL_MODEL
var local_key := ""            ## some local servers want a bearer; most ignore it
var notes_on := true

## --- state -----------------------------------------------------------------
var history: Array = []        ## [{role, text}] the conversation as sent
var notes: Array = []          ## [{kind, text, where, when, pos}] this session
var _unsent := 0               ## notes not yet sent up the line
var _chat: Http = null         ## the streaming reply in flight, or null
var _noter: Http = null        ## the Haiku note call in flight, or null
var _noter_pending: Array = [] ## exchanges waiting for the noter
var _live_text := ""           ## the assistant turn being streamed
var _status := ""
var last_handoff_path := ""    ## where the last "up the line" landed
var _session_started := ""

## --- widgets ---------------------------------------------------------------
var _log: RichTextLabel
var _input: LineEdit
var _send: Button
var _up: Button
var _backend_pick: OptionButton
var _model_lbl: Label
var _status_lbl: Label
var _key_row: HBoxContainer
var _key_edit: LineEdit
var _url_edit: LineEdit
var _notes_check: CheckBox


# ============================================================ HTTP, POLLED
## HTTPClient driven a frame at a time so a streamed reply paints as it
## arrives -- HTTPRequest only speaks when the whole body is in. Handles the
## SSE framing when `sse` is on; otherwise `text` is the whole body at `done`.
class Http extends RefCounted:
	var client := HTTPClient.new()
	var host := ""
	var port := 443
	var tls := true
	var path := "/"
	var headers := PackedStringArray()
	var body := ""
	var sse := false
	var done := false
	var error := ""
	var status_code := 0
	var text := ""                 ## the whole body as text, once `done` (both modes)
	var events: Array = []         ## SSE: `data:` payloads ready to consume
	var _bytes := PackedByteArray()   ## SSE: not-yet-framed tail; non-SSE: everything
	var _all := PackedByteArray()     ## every byte that arrived, for `text`
	var _sse_buf := ""
	var _connecting := false
	var _sent := false
	var _started_ms := 0
	var timeout_ms := 90000

	func begin(url: String, hdrs: PackedStringArray, payload: String, streaming: bool) -> void:
		var u := split_url(url)
		host = String(u["host"])
		port = int(u["port"])
		tls = bool(u["tls"])
		path = String(u["path"])
		headers = hdrs
		body = payload
		sse = streaming
		_started_ms = Time.get_ticks_msec()

	func fail(why: String) -> void:
		if done:
			return
		error = why
		done = true
		client.close()

	func finish() -> void:
		if done:
			return
		if sse:
			_drain_sse(true)
		text = _all.get_string_from_utf8()
		done = true
		client.close()

	func poll() -> void:
		if done:
			return
		if Time.get_ticks_msec() - _started_ms > timeout_ms:
			@warning_ignore("integer_division")
			fail("timed out after %d s" % int(timeout_ms / 1000))
			return
		if not _connecting:
			var tlso: TLSOptions = TLSOptions.client() if tls else null
			var err := client.connect_to_host(host, port, tlso)
			if err != OK:
				fail("connect_to_host failed (%d)" % err)
				return
			_connecting = true
		client.poll()
		var st := client.get_status()
		match st:
			HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
				return
			HTTPClient.STATUS_CONNECTED:
				if not _sent:
					var err := client.request(HTTPClient.METHOD_POST, path, headers, body)
					if err != OK:
						fail("request failed (%d)" % err)
						return
					_sent = true
				else:
					## The response is in and had no (more) body.
					status_code = client.get_response_code()
					finish()
			HTTPClient.STATUS_BODY:
				status_code = client.get_response_code()
				## Several reads per frame -- a streamed reply arrives in many
				## small chunks and one per frame would lag the paint.
				for _i in range(16):
					var chunk := client.read_response_body_chunk()
					if chunk.size() == 0:
						break
					_bytes.append_array(chunk)
					_all.append_array(chunk)
					if sse:
						_drain_sse(false)
					if client.get_status() != HTTPClient.STATUS_BODY:
						break
				if client.get_status() == HTTPClient.STATUS_CONNECTED \
						or client.get_status() == HTTPClient.STATUS_DISCONNECTED:
					finish()
			HTTPClient.STATUS_DISCONNECTED:
				if _sent:
					finish()
				else:
					fail("disconnected before the request went out")
			HTTPClient.STATUS_CANT_RESOLVE:
				fail("can't resolve %s" % host)
			HTTPClient.STATUS_CANT_CONNECT:
				fail("can't connect to %s:%d" % [host, port])
			HTTPClient.STATUS_CONNECTION_ERROR:
				fail("connection error")
			HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
				fail("TLS handshake failed")

	## --- text helpers the poller needs, owned here so the inner class never
	## names the outer one (a cold global-class cache cannot resolve it) ---

	static func split_url(url: String) -> Dictionary:
		## "https://host:port/path" -> {tls, host, port, path}. Defaults: https,
		## 443/80 by scheme, "/" for an empty path.
		var s := url.strip_edges()
		var u_tls := true
		if s.begins_with("http://"):
			u_tls = false
			s = s.substr(7)
		elif s.begins_with("https://"):
			s = s.substr(8)
		var slash := s.find("/")
		var hostport := s if slash < 0 else s.substr(0, slash)
		var u_path := "/" if slash < 0 else s.substr(slash)
		var u_port := 443 if u_tls else 80
		var u_host := hostport
		var colon := hostport.rfind(":")
		if colon >= 0 and hostport.substr(colon + 1).is_valid_int():
			u_host = hostport.substr(0, colon)
			u_port = int(hostport.substr(colon + 1))
		return {"tls": u_tls, "host": u_host, "port": u_port, "path": u_path}


	static func join_path(base: String, tail: String) -> String:
		## "http://h/v1" + "/chat/completions" -> one slash between them.
		var b := base.strip_edges()
		while b.ends_with("/"):
			b = b.substr(0, b.length() - 1)
		return b + ("/" + tail if not tail.begins_with("/") else tail)


	static func sse_split(buf: String) -> Array:
		## Server-Sent Events framing. Returns [datas, remainder]: every COMPLETE
		## event's joined `data:` lines (an event ends at a blank line), and the
		## unterminated tail to keep for the next chunk. `event:`, `id:`, `:`
		## comment lines are dropped; CRLF is tolerated.
		var body_text := buf.replace("\r\n", "\n")
		var datas: Array = []
		var pos := 0
		while true:
			var end := body_text.find("\n\n", pos)
			if end < 0:
				break
			var block := body_text.substr(pos, end - pos)
			pos = end + 2
			var lines: Array = []
			for ln in block.split("\n"):
				if ln.begins_with("data:"):
					var v := ln.substr(5)
					if v.begins_with(" "):
						v = v.substr(1)
					lines.append(v)
			if not lines.is_empty():
				datas.append("\n".join(lines))
		return [datas, body_text.substr(pos)]


	func _drain_sse(flush: bool) -> void:
		## Decode only up to the last newline so a UTF-8 sequence split across
		## two chunks is never decoded in halves.
		var cut := _bytes.size() if flush else _bytes.rfind(10)
		if cut <= 0 and not flush:
			return
		var head := _bytes.slice(0, cut)
		_bytes = _bytes.slice(cut)
		_sse_buf += head.get_string_from_utf8()
		var r := sse_split(_sse_buf + ("\n\n" if flush else ""))
		for d in r[0]:
			events.append(d)
		_sse_buf = "" if flush else String(r[1])


# ================================================================ PURE TEXT
## Everything below `static` is a function of its arguments and nothing else,
## so ClaudeChatTests can hand it strings.

static func split_url(url: String) -> Dictionary:
	return Http.split_url(url)


static func join_path(base: String, tail: String) -> String:
	return Http.join_path(base, tail)


static func sse_split(buf: String) -> Array:
	return Http.sse_split(buf)


static func anthropic_delta(data: String) -> Dictionary:
	## One Messages-API stream event -> {text, done, error}.
	var out := {"text": "", "done": false, "error": ""}
	var j = JSON.parse_string(data)
	if not (j is Dictionary):
		return out
	var t := String(j.get("type", ""))
	match t:
		"content_block_delta":
			var d: Dictionary = j.get("delta", {})
			if String(d.get("type", "")) == "text_delta":
				out["text"] = String(d.get("text", ""))
		"message_stop":
			out["done"] = true
		"error":
			var e: Dictionary = j.get("error", {})
			out["error"] = "%s: %s" % [String(e.get("type", "error")), String(e.get("message", ""))]
			out["done"] = true
	return out


static func openai_delta(data: String) -> Dictionary:
	## One chat.completions stream event -> {text, done, error}.
	var out := {"text": "", "done": false, "error": ""}
	if data.strip_edges() == "[DONE]":
		out["done"] = true
		return out
	var j = JSON.parse_string(data)
	if not (j is Dictionary):
		return out
	if j.has("error"):
		var e = j["error"]
		out["error"] = String(e.get("message", str(e))) if e is Dictionary else str(e)
		out["done"] = true
		return out
	var ch: Array = j.get("choices", [])
	if ch.is_empty():
		return out
	var c0: Dictionary = ch[0]
	var d: Dictionary = c0.get("delta", {})
	var content = d.get("content", "")
	if content is String:
		out["text"] = content
	if c0.get("finish_reason", null) != null:
		out["done"] = true
	return out


static func anthropic_body(model: String, system: String, msgs: Array, max_tokens: int, stream: bool) -> String:
	var m: Array = []
	for h in msgs:
		m.append({"role": String(h["role"]), "content": String(h["text"])})
	return JSON.stringify({"model": model, "max_tokens": max_tokens, "system": system,
		"messages": m, "stream": stream})


static func openai_body(model: String, system: String, msgs: Array, max_tokens: int, stream: bool) -> String:
	var m: Array = [{"role": "system", "content": system}]
	for h in msgs:
		m.append({"role": String(h["role"]), "content": String(h["text"])})
	return JSON.stringify({"model": model, "messages": m, "max_tokens": max_tokens, "stream": stream})


static func anthropic_headers(key: String) -> PackedStringArray:
	return PackedStringArray(["content-type: application/json", "x-api-key: %s" % key,
		"anthropic-version: %s" % ANTHROPIC_VERSION, "accept: text/event-stream"])


static func openai_headers(key: String) -> PackedStringArray:
	var h := PackedStringArray(["content-type: application/json", "accept: text/event-stream"])
	if key != "":
		h.append("authorization: Bearer %s" % key)
	return h


static func anthropic_text(body: String) -> String:
	## A NON-streamed Messages response -> its text, "" if it is not one.
	var j = JSON.parse_string(body)
	if not (j is Dictionary):
		return ""
	var out := ""
	for c in j.get("content", []):
		if c is Dictionary and String(c.get("type", "")) == "text":
			out += String(c.get("text", ""))
	return out


static func openai_text(body: String) -> String:
	var j = JSON.parse_string(body)
	if not (j is Dictionary):
		return ""
	var ch: Array = j.get("choices", [])
	if ch.is_empty():
		return ""
	var msg: Dictionary = (ch[0] as Dictionary).get("message", {})
	var c = msg.get("content", "")
	return c if c is String else ""


static func api_error(body: String, code: int) -> String:
	## What a failed call SAID, for the transcript, from either API's shape.
	var j = JSON.parse_string(body)
	if j is Dictionary and j.has("error"):
		var e = j["error"]
		if e is Dictionary:
			return "HTTP %d -- %s" % [code, String(e.get("message", str(e)))]
		return "HTTP %d -- %s" % [code, str(e)]
	return "HTTP %d" % code if body.strip_edges() == "" else "HTTP %d -- %s" % [code, body.left(200)]


static func resolve_key(env_key: String, cfg_key: String) -> String:
	## The environment wins; the cfg is the fallback. Whitespace is never a key.
	var e := env_key.strip_edges()
	return e if e != "" else cfg_key.strip_edges()


static func window(msgs: Array, keep: int) -> Array:
	## The last `keep` messages, trimmed to start on a USER turn -- Anthropic
	## rejects a conversation that opens with the assistant.
	var w: Array = msgs.slice(maxi(0, msgs.size() - keep))
	while not w.is_empty() and String(w[0]["role"]) != "user":
		w.remove_at(0)
	return w


static func chat_system(snap: Dictionary) -> String:
	return ("You are Claude, riding along inside Myrkfell -- a Godot 4.7 first-person "
		+ "dark-fantasy survival RPG set on a stylised map of Maine -- as the developer's "
		+ "in-game assistant. The developer (Lemon) is playing right now and talking to you "
		+ "from a small chat card over the game. Be brief and concrete: two to five sentences "
		+ "unless asked for more. Use the live game state below when it is relevant. You "
		+ "cannot run commands or change the game from here. A second model takes notes on "
		+ "this conversation -- bugs, ideas, requests, decisions -- and sends them up the "
		+ "line to the Claude Code session that edits the repo, so when Lemon says 'note "
		+ "that' or 'remember this', acknowledge in a few words and move on.\n\n"
		+ "GAME STATE (JSON): " + JSON.stringify(snap))


static func notes_system() -> String:
	return ("You are the note-taker riding along in a Godot game-dev play session for Myrkfell. "
		+ "You are given the live game state and the latest exchange between the developer "
		+ "(Lemon) and the in-game assistant. Extract only DURABLE notes worth relaying to "
		+ "the Claude Code session that edits the repository: bugs seen, ideas, requests, "
		+ "decisions, or observations about the build. Skip chit-chat and anything already "
		+ "obvious from the state. Each note: one sentence, specific, in the developer's "
		+ "words where possible. Reply with ONLY this JSON and nothing else:\n"
		+ "{\"notes\":[{\"kind\":\"bug|idea|request|decision|observation\",\"text\":\"...\",\"where\":\"place or system\"}]}\n"
		+ "Reply {\"notes\":[]} when nothing durable was said.")


static func notes_user(snap: Dictionary, user_text: String, assistant_text: String) -> String:
	return ("GAME STATE: %s\n\nLEMON SAID:\n%s\n\nASSISTANT REPLIED:\n%s" %
		[JSON.stringify(snap), user_text, assistant_text])


static func parse_notes(raw: String) -> Array:
	## The noter's reply -> [{kind, text, where}], tolerant of code fences and
	## chatter around the JSON. Unknown kinds become "observation"; empty text
	## is dropped.
	var s := raw
	var a := s.find("{")
	var b := s.rfind("}")
	if a < 0 or b <= a:
		return []
	var j = JSON.parse_string(s.substr(a, b - a + 1))
	if not (j is Dictionary):
		return []
	var out: Array = []
	for n in j.get("notes", []):
		if not (n is Dictionary):
			continue
		var text := String(n.get("text", "")).strip_edges()
		if text == "":
			continue
		var kind := String(n.get("kind", "observation")).to_lower().strip_edges()
		if not NOTE_KINDS.has(kind):
			kind = "observation"
		out.append({"kind": kind, "text": text, "where": String(n.get("where", "")).strip_edges()})
	return out


static func note_line(n: Dictionary) -> String:
	## One note as one markdown bullet.
	var where := String(n.get("where", ""))
	var stamp := PackedStringArray()
	for k in ["when", "pos"]:
		var v := String(n.get(k, ""))
		if v != "":
			stamp.append(v)
	var tail := ("  _(%s)_" % ", ".join(stamp)) if not stamp.is_empty() else ""
	return "- **%s**%s %s%s" % [String(n["kind"]), (" [%s]" % where) if where != "" else "",
		String(n["text"]), tail]


static func handoff_md(title: String, when: String, snap: Dictionary, session_notes: Array, transcript: Array) -> String:
	## The file that goes up the line: notes grouped by kind, then the
	## transcript, then the state at the moment it was sent.
	var out := "# %s\n\n" % title
	out += "_Written by the in-game Claude chat (F4) at %s. Read me at the start of the next Cowork session._\n\n" % when
	out += "## Notes (%d)\n\n" % session_notes.size()
	if session_notes.is_empty():
		out += "_No durable notes this session._\n\n"
	else:
		for k in NOTE_KINDS:
			var rows: Array = []
			for n in session_notes:
				if String(n["kind"]) == k:
					rows.append(n)
			if rows.is_empty():
				continue
			out += "### %s\n\n" % k.capitalize()
			for n in rows:
				out += note_line(n) + "\n"
			out += "\n"
	out += "## Transcript\n\n"
	if transcript.is_empty():
		out += "_(empty)_\n\n"
	for h in transcript:
		var who := "**Lemon:**" if String(h["role"]) == "user" else "**Claude:**"
		out += "%s %s\n\n" % [who, String(h["text"]).strip_edges()]
	out += "## Game state when sent\n\n```json\n%s\n```\n" % JSON.stringify(snap, "  ")
	return out


static func stamp_day() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func stamp_clock() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d" % [t["hour"], t["minute"]]


static func handoff_dir() -> String:
	## The repo when we ARE the repo (running from the editor / a project
	## folder); the user dir when res:// is a read-only pack.
	return HANDOFF_DIR_RES if OS.has_feature("editor") else HANDOFF_DIR_USER


# ================================================================== CONFIG
func load_cfg() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(cfg_path)
	var cfg_key := ""
	if err == OK:
		backend = String(cf.get_value("chat", "backend", backend))
		notes_on = bool(cf.get_value("chat", "notes", notes_on))
		cfg_key = String(cf.get_value("anthropic", "api_key", ""))
		chat_model = String(cf.get_value("anthropic", "model", chat_model))
		notes_model = String(cf.get_value("anthropic", "notes_model", notes_model))
		local_url = String(cf.get_value("local", "url", local_url))
		local_model = String(cf.get_value("local", "model", local_model))
		local_key = String(cf.get_value("local", "api_key", local_key))
	if not BACKENDS.has(backend):
		backend = "anthropic"
	api_key = resolve_key(OS.get_environment("ANTHROPIC_API_KEY"), cfg_key)


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(cfg_path)   ## keep anything hand-added
	cf.set_value("chat", "backend", backend)
	cf.set_value("chat", "notes", notes_on)
	## Only write the key when it did not come from the environment, so the
	## cfg never silently copies a shell secret to disk.
	if OS.get_environment("ANTHROPIC_API_KEY").strip_edges() == "":
		cf.set_value("anthropic", "api_key", api_key)
	cf.set_value("anthropic", "model", chat_model)
	cf.set_value("anthropic", "notes_model", notes_model)
	cf.set_value("local", "url", local_url)
	cf.set_value("local", "model", local_model)
	cf.set_value("local", "api_key", local_key)
	cf.save(cfg_path)


func ready_to_talk() -> String:
	## "" when the current backend can take a message, else what is missing.
	if backend == "anthropic" and api_key == "":
		return "No Anthropic key. Paste one in the KEY field (saved to user://claude.cfg) or set ANTHROPIC_API_KEY before launching."
	if backend == "local" and local_url.strip_edges() == "":
		return "No local URL. Point me at an OpenAI-compatible server, e.g. http://localhost:8000/v1"
	return ""


# ================================================================== THE UI
func _ready() -> void:
	name = "ClaudeChat"
	visible = false
	_session_started = "%s %s" % [stamp_day(), stamp_clock()]
	load_cfg()
	_build_ui()
	_refresh_header()
	visibility_changed.connect(_on_visibility)
	set_process(true)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	offset_left = 16.0
	offset_bottom = -16.0
	offset_top = -16.0 - PANEL_H
	offset_right = 16.0 + PANEL_W
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.09, 0.93)
	bg.border_color = Color(0.86, 0.62, 0.32, 0.8)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(10)
	add_theme_stylebox_override("panel", bg)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	## header: title . backend . model . status
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := Label.new()
	title.text = "CLAUDE"
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	_backend_pick = OptionButton.new()
	_backend_pick.add_item("Anthropic", 0)
	_backend_pick.add_item("Local", 1)
	_backend_pick.select(BACKENDS.find(backend))
	_backend_pick.item_selected.connect(_on_backend)
	_backend_pick.focus_mode = Control.FOCUS_NONE
	head.add_child(_backend_pick)
	_model_lbl = Label.new()
	_model_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	_model_lbl.add_theme_font_size_override("font_size", 12)
	_model_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_lbl.clip_text = true
	head.add_child(_model_lbl)
	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	head.add_child(_status_lbl)

	## settings row: key / url + notes toggle
	_key_row = HBoxContainer.new()
	_key_row.add_theme_constant_override("separation", 6)
	col.add_child(_key_row)
	_key_edit = LineEdit.new()
	_key_edit.placeholder_text = "KEY  sk-ant-..."
	_key_edit.secret = true
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_edit.text_submitted.connect(func(t: String): _set_key(t))
	_key_edit.focus_exited.connect(func(): _set_key(_key_edit.text))
	_key_row.add_child(_key_edit)
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "LOCAL URL  http://localhost:8000/v1"
	_url_edit.text = local_url
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.text_submitted.connect(func(t: String): _set_url(t))
	_url_edit.focus_exited.connect(func(): _set_url(_url_edit.text))
	_key_row.add_child(_url_edit)
	_notes_check = CheckBox.new()
	_notes_check.text = "notes"
	_notes_check.button_pressed = notes_on
	_notes_check.focus_mode = Control.FOCUS_NONE
	_notes_check.toggled.connect(func(on: bool):
		notes_on = on
		save_cfg()
		_refresh_header())
	_key_row.add_child(_notes_check)

	## the transcript
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_font_size_override("bold_font_size", 14)
	_log.focus_mode = Control.FOCUS_NONE
	var lbg := StyleBoxFlat.new()
	lbg.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	lbg.set_content_margin_all(8)
	lbg.set_corner_radius_all(4)
	_log.add_theme_stylebox_override("normal", lbg)
	col.add_child(_log)

	## the line
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "Ask Claude...  (Enter sends, Esc closes)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(t: String): send(t))
	row.add_child(_input)
	_send = Button.new()
	_send.text = "Send"
	_send.focus_mode = Control.FOCUS_NONE
	_send.pressed.connect(func(): send(_input.text))
	row.add_child(_send)
	_up = Button.new()
	_up.text = "Send up the line"
	_up.tooltip_text = "Write this session's notes + transcript into notes/claude-handoff/ for the Cowork session"
	_up.focus_mode = Control.FOCUS_NONE
	_up.pressed.connect(func(): send_up_the_line(false))
	row.add_child(_up)
	var clr := Button.new()
	clr.text = "Clear"
	clr.focus_mode = Control.FOCUS_NONE
	clr.pressed.connect(clear_chat)
	row.add_child(clr)

	## Any click on the card hands the keyboard back to the line, so a
	## stray letter can never fall through to the game.
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_input.grab_focus())

	_greet()


func _greet() -> void:
	var missing := ready_to_talk()
	if missing != "":
		_line("sys", missing)
	else:
		_line("sys", "F4 again or Esc to close. Enter sends. Notes ride along%s." %
			(" in " + notes_model if notes_on else " (off)"))
	_render()


func _refresh_header() -> void:
	if _model_lbl == null:
		return
	_model_lbl.text = chat_model if backend == "anthropic" else "%s @ %s" % [local_model, local_url]
	_key_edit.visible = backend == "anthropic"
	_url_edit.visible = backend == "local"
	if backend == "anthropic":
		_key_edit.placeholder_text = ("KEY  (set: ...%s)" % api_key.right(4)) if api_key != "" else "KEY  sk-ant-..."
	_status_lbl.text = _status


func _on_visibility() -> void:
	if visible:
		_input.call_deferred("grab_focus")
	else:
		if _input.has_focus():
			_input.release_focus()


func _on_backend(idx: int) -> void:
	backend = BACKENDS[clampi(idx, 0, BACKENDS.size() - 1)]
	save_cfg()
	_refresh_header()
	var missing := ready_to_talk()
	if missing != "":
		_line("sys", missing)
	else:
		_line("sys", "Backend: %s." % _model_lbl.text)
	_render()


func _set_key(t: String) -> void:
	var k := t.strip_edges()
	if k == "":
		return
	api_key = k
	_key_edit.text = ""
	save_cfg()
	_refresh_header()
	_line("sys", "Key saved to user://claude.cfg (...%s)." % api_key.right(4))
	_render()
	_input.grab_focus()


func _set_url(t: String) -> void:
	var u := t.strip_edges()
	if u == "" or u == local_url:
		return
	local_url = u
	save_cfg()
	_refresh_header()


## Player asks this before acting on a key while we are up. True = ours.
## Only Esc (close, via Player) and F4 (toggle, via Player) fall through --
## everything else is typing, or would be if the line had focus, and a
## stray M or G must never open the map or the creative menu mid-sentence.
func eat_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_F4:
			return false
		if k.pressed and not k.echo and not _input.has_focus() \
				and not _key_edit.has_focus() and not _url_edit.has_focus():
			_input.grab_focus()
		return true
	return false


# ================================================================ THE CHAT
func send(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	if _chat != null:
		_line("sys", "Still answering -- one at a time.")
		_render()
		return
	var missing := ready_to_talk()
	if missing != "":
		_line("sys", missing)
		_render()
		return
	_input.text = ""
	history.append({"role": "user", "text": t})
	_live_text = ""
	_render()
	var snap := snapshot()
	var msgs := window(talk(), MAX_TURNS)
	_chat = Http.new()
	if backend == "anthropic":
		_chat.begin("https://%s%s" % [ANTHROPIC_HOST, ANTHROPIC_PATH], anthropic_headers(api_key),
			anthropic_body(chat_model, chat_system(snap), msgs, MAX_TOKENS, true), true)
	else:
		_chat.begin(join_path(local_url, "/chat/completions"), openai_headers(local_key),
			openai_body(local_model, chat_system(snap), msgs, MAX_TOKENS, true), true)
	_status = "thinking"
	_refresh_header()


func talk() -> Array:
	## The transcript minus the system lines -- what actually goes to the API.
	var out: Array = []
	for h in history:
		if String(h["role"]) != "sys":
			out.append(h)
	return out


func clear_chat() -> void:
	if _chat != null:
		_chat.fail("cleared")
		_chat = null
	history.clear()
	_live_text = ""
	_status = ""
	_refresh_header()
	_line("sys", "Cleared. Notes from before are kept until you send them up.")
	_render()


func _process(_dt: float) -> void:
	if _chat != null:
		_pump_chat()
	if _noter != null:
		_pump_noter()
	elif notes_on and not _noter_pending.is_empty():
		_start_noter(_noter_pending.pop_front())


func _pump_chat() -> void:
	_chat.poll()
	var got := false
	var err := ""
	while not _chat.events.is_empty():
		var data := String(_chat.events.pop_front())
		var d := anthropic_delta(data) if backend == "anthropic" else openai_delta(data)
		if String(d["text"]) != "":
			_live_text += String(d["text"])
			got = true
		if String(d["error"]) != "":
			err = String(d["error"])
	if got:
		_status = "%d chars" % _live_text.length()
		_render()
	if not _chat.done:
		return
	## Finished, one way or the other.
	if _chat.error != "":
		err = _chat.error
	elif _chat.status_code >= 400:
		err = api_error(_chat.text, _chat.status_code)
	var reply := _live_text.strip_edges()
	if reply != "":
		history.append({"role": "assistant", "text": reply})
		var last_user := ""
		for i in range(history.size() - 2, -1, -1):
			if String(history[i]["role"]) == "user":
				last_user = String(history[i]["text"])
				break
		if notes_on:
			_noter_pending.append({"user": last_user, "assistant": reply, "snap": snapshot()})
	if err != "":
		if reply == "" and not history.is_empty() and String(history[-1]["role"]) == "user":
			## Drop the dangling user turn so the window still starts clean
			## and the next send is not a doubled question.
			history.pop_back()
		_line("sys", "Error: %s" % err)
	_live_text = ""
	_chat = null
	_status = "" if err == "" else "error"
	_refresh_header()
	_render()


func _line(role: String, text: String) -> void:
	## System lines live in the transcript but are never SENT (see talk()).
	history.append({"role": role, "text": text})


func _render() -> void:
	if _log == null:
		return
	var out := ""
	for h in history:
		var role := String(h["role"])
		var text := String(h["text"])
		match role:
			"user":
				out += "[color=#f2c777][b]Lemon[/b][/color]  %s\n\n" % _esc(text)
			"assistant":
				out += "[color=#9fd3ff][b]Claude[/b][/color]  %s\n\n" % _esc(text)
			_:
				out += "[color=#8a8a90][i]%s[/i][/color]\n\n" % _esc(text)
	if _chat != null:
		out += "[color=#9fd3ff][b]Claude[/b][/color]  %s[color=#666]▌[/color]\n" % _esc(_live_text)
	_log.text = out


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


# ============================================================ THE NOTE-TAKER
func _start_noter(ex: Dictionary) -> void:
	var snap: Dictionary = ex["snap"]
	var msgs := [{"role": "user", "text": notes_user(snap, String(ex["user"]), String(ex["assistant"]))}]
	_noter = Http.new()
	_noter.set_meta("snap", snap)
	if backend == "anthropic" or api_key != "":
		## Haiku takes the notes whenever there is a key -- even when the chat
		## itself is on a local model. That is the point of the second line.
		_noter.begin("https://%s%s" % [ANTHROPIC_HOST, ANTHROPIC_PATH], anthropic_headers(api_key),
			anthropic_body(notes_model, notes_system(), msgs, NOTES_MAX_TOKENS, false), false)
		_noter.set_meta("api", "anthropic")
	else:
		_noter.begin(join_path(local_url, "/chat/completions"), openai_headers(local_key),
			openai_body(local_model, notes_system(), msgs, NOTES_MAX_TOKENS, false), false)
		_noter.set_meta("api", "openai")


func _pump_noter() -> void:
	_noter.poll()
	if not _noter.done:
		return
	var n := _noter
	_noter = null
	if n.error != "" or n.status_code >= 400:
		_status = "notes: %s" % (n.error if n.error != "" else "HTTP %d" % n.status_code)
		_refresh_header()
		return
	var raw := anthropic_text(n.text) if String(n.get_meta("api", "anthropic")) == "anthropic" else openai_text(n.text)
	var snap: Dictionary = n.get_meta("snap", {})
	var got := parse_notes(raw)
	if got.is_empty():
		return
	take_notes(got, snap)


func take_notes(got: Array, snap: Dictionary) -> void:
	## Stamp, keep, and append to today's notes file.
	var when := "day %s %s" % [str(snap.get("day", "?")), _clock(float(snap.get("hour", -1.0)))]
	var pos := ""
	if snap.has("pos"):
		var p: Array = snap["pos"]
		pos = "@ %.0f, %.0f" % [float(p[0]), float(p[2])]
		if snap.has("near") and String(snap["near"]) != "":
			pos += " near %s" % String(snap["near"])
	var lines := ""
	for n in got:
		var row: Dictionary = n.duplicate()
		row["when"] = when
		row["pos"] = pos
		notes.append(row)
		lines += note_line(row) + "\n"
	_unsent += got.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(notes_dir))
	var path := "%s/%s.md" % [notes_dir, stamp_day()]
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		if f.get_length() == 0:
			f.store_string("# Claude notes -- %s\n\n" % stamp_day())
		else:
			f.seek_end()
		f.store_string("<!-- %s -->\n%s" % [stamp_clock(), lines])
		f.close()
	_status = "%d note%s" % [_unsent, "" if _unsent == 1 else "s"]
	_refresh_header()


static func _clock(hour: float) -> String:
	if hour < 0.0:
		return "?"
	var h := int(floor(hour)) % 24
	var m := int(floor((hour - floor(hour)) * 60.0))
	return "%02d:%02d" % [h, m]


# ============================================================ UP THE LINE
func send_up_the_line(auto: bool) -> String:
	## Write notes + transcript for the Cowork session. Returns the path, or
	## "" when there was nothing to send. `auto` is the exit path: quiet, and
	## only when there are unsent notes.
	var spoken: Array = talk()
	if auto and _unsent == 0:
		return ""
	if not auto and notes.is_empty() and spoken.is_empty():
		_line("sys", "Nothing to send yet.")
		_render()
		return ""
	var dir := handoff_override if handoff_override != "" else handoff_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var day := stamp_day()
	var clock := stamp_clock().replace(":", "")
	var path := "%s/%s-%s.md" % [dir, day, clock]
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s/%s-%s-%d.md" % [dir, day, clock, n]
		n += 1
	var md := handoff_md("Claude handoff -- %s %s" % [day, stamp_clock()], "%s %s (session started %s)" %
		[day, stamp_clock(), _session_started], snapshot(), notes, spoken)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if not auto:
			_line("sys", "Couldn't write %s (%d)." % [path, FileAccess.get_open_error()])
			_render()
		return ""
	f.store_string(md)
	f.close()
	_unsent = 0
	last_handoff_path = path
	if not auto:
		_line("sys", "Sent up the line: %s (%d notes, %d turns)." % [ProjectSettings.globalize_path(path), notes.size(), spoken.size()])
		_status = "sent"
		_refresh_header()
		_render()
	return path


func _exit_tree() -> void:
	## The card goes down with the world (quit, or the 5-key restart). Notes
	## nobody sent go up anyway -- that is the whole point of a note-taker.
	send_up_the_line(true)


# ============================================================== THE SNAPSHOT
func snapshot() -> Dictionary:
	## What the assistant knows about the moment: cheap, defensive, and never
	## a reason for the chat to fail. Every field is optional.
	var d := {"fps": Engine.get_frames_per_second(), "godot": Engine.get_version_info().get("string", "")}
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return d
	var p: Vector3 = player.global_position
	d["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
	for k in ["health", "stamina", "thirst", "menu_open", "god", "flying", "editing",
			"cam_mode", "crouching", "prone", "swimming", "current_weapon", "sheathed"]:
		var v = player.get(k)
		if v != null:
			d[k] = snappedf(v, 0.1) if v is float else v
	var dn := _find("DayNight")
	if dn != null:
		var day = dn.get("day")
		var hour = dn.get("hour")
		if day != null:
			d["day"] = int(day)
			d["season"] = Seasons.name_of(Seasons.index(float(day)))
		if hour != null:
			d["hour"] = _clock(float(hour))
	var w := _find("Weather")
	if w != null and w.has_method("level_name"):
		d["weather"] = w.level_name()
	var ow := _find("Overworld")
	if ow != null and ow.has_method("place_name_at"):
		var near: String = ow.place_name_at(p)
		if near != "":
			d["near"] = near
	var z := WorldPlan.zone_at(p.x, p.z)
	if not z.is_empty():
		d["zone"] = "%s (%s)" % [str(z.get("name", "?")), str(z.get("kind", "?"))]
	return d


func _find(cls: String) -> Node:
	## A node by script class name, anywhere under the root. Godot's
	## find_children takes a global class; the manual sweep is the fallback
	## for the odd script that never got one.
	var tree := get_tree()
	if tree == null:
		return null
	var hits := tree.root.find_children("*", cls, true, false)
	if not hits.is_empty():
		return hits[0]
	return null
