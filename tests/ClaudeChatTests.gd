extends SceneTree
## ===========================================================================
## CLAUDE CHAT (F4) -- the regression net for scripts/ClaudeChat.gd.
##
##   godot --headless --path . --script res://tests/ClaudeChatTests.gd
##
## No key, no network beyond 127.0.0.1. The load-bearing claims:
##   1. the text plumbing is right -- SSE framing across arbitrary chunk
##      boundaries, both APIs' delta and whole-body shapes, the request
##      bodies, the key resolution, the history window;
##   2. the note-taker's reply is parsed defensively and the notes and the
##      handoff render as the markdown the Cowork session expects;
##   3. the real panel builds without a HUD, keeps the keyboard while it is
##      up (Esc and F4 excepted), and takes no key of its own -- F4 is
##      Player's, recorded in DevInputRegistry like every other dev key;
##   4. the poller works end to end against a FAKE server on localhost:
##      a chunked SSE stream paints into a reply, a 4xx body becomes an
##      error line, and a whole exchange -- send, stream, note, write the
##      notes file, send up the line -- lands the files where it says.
## ===========================================================================

const MIN_ASSERTIONS := 110
## Loaded by PATH, not class_name: a headless run right after the file lands has
## no global-class cache entry for it yet, and the suite must not depend on the
## editor having scanned.
const CC := preload("res://scripts/ClaudeChat.gd")
const PORT_BASE := 18917
const CFG := "user://claude_test.cfg"
const NOTES := "user://claude_test_notes"
const HANDOFF := "user://claude_test_handoff"

var _pass := 0
var _fail := 0
var _fails: Array = []
var _srv := TCPServer.new()
var _port := 0


func ok(c: bool, what: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		_fails.append(what)
		print("  FAIL: ", what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func section(n: String) -> void:
	print("--- ", n)


func read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=== Myrkfell Claude Chat tests ===")
	_t_url()
	_t_sse()
	_t_deltas()
	_t_bodies()
	_t_misc()
	_t_notes()
	_t_handoff()
	_t_panel()
	_t_sources()
	await _t_wire()
	await _t_exchange()
	_cleanup()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	if _pass + _fail < MIN_ASSERTIONS:
		print("  FAIL: only %d assertions ran (want >= %d)" % [_pass + _fail, MIN_ASSERTIONS])
		_fail += 1
	for f in _fails:
		print("  x ", f)
	quit(1 if _fail > 0 else 0)


# ------------------------------------------------------------------ pure text

func _t_url() -> void:
	section("split_url / join_path")
	var u := CC.split_url("https://api.anthropic.com/v1/messages")
	eq(u["host"], "api.anthropic.com", "https host")
	eq(u["port"], 443, "https default port")
	eq(u["tls"], true, "https is tls")
	eq(u["path"], "/v1/messages", "path kept")
	u = CC.split_url("http://localhost:8000/v1/chat/completions")
	eq(u["host"], "localhost", "http host")
	eq(u["port"], 8000, "explicit port")
	eq(u["tls"], false, "http is plain")
	u = CC.split_url("http://127.0.0.1:1234")
	eq(u["path"], "/", "no path -> /")
	eq(u["port"], 1234, "ip:port")
	u = CC.split_url("localhost")
	eq(u["port"], 443, "bare host defaults to https")
	eq(CC.join_path("http://h/v1", "/chat/completions"), "http://h/v1/chat/completions", "join, one slash")
	eq(CC.join_path("http://h/v1/", "chat/completions"), "http://h/v1/chat/completions", "join, trailing + bare")


func _t_sse() -> void:
	section("sse_split")
	var r := CC.sse_split("event: x\ndata: {\"a\":1}\n\ndata: two\n\ndata: part")
	eq((r[0] as Array).size(), 2, "two complete events")
	eq(r[0][0], "{\"a\":1}", "data payload, event: line dropped")
	eq(r[0][1], "two", "second payload")
	eq(r[1], "data: part", "unterminated tail kept")
	r = CC.sse_split("data: a\r\ndata: b\r\n\r\n")
	eq(r[0][0], "a\nb", "multi-line data joined; CRLF tolerated")
	eq(r[1], "", "nothing left over")
	r = CC.sse_split(": keepalive\n\n")
	eq((r[0] as Array).size(), 0, "a comment-only event yields no data")
	r = CC.sse_split("")
	eq((r[0] as Array).size(), 0, "empty in, nothing out")
	## The chunk-boundary case that streaming actually hits: the same stream
	## cut at every byte must yield the same events when reassembled.
	var stream := "event: message_start\ndata: {\"type\":\"message_start\"}\n\nevent: d\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hé\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
	var whole := CC.sse_split(stream)[0] as Array
	var agree := true
	for cut in range(1, stream.length()):
		var first := CC.sse_split(stream.substr(0, cut))
		var rest := CC.sse_split(String(first[1]) + stream.substr(cut))
		var got: Array = (first[0] as Array) + (rest[0] as Array)
		if got != whole:
			agree = false
			break
	ok(agree, "cutting the stream at any byte and reassembling gives the same events")
	eq(whole.size(), 3, "three events in the reference stream")


func _t_deltas() -> void:
	section("anthropic_delta / openai_delta")
	var d := CC.anthropic_delta("{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi \"}}")
	eq(d["text"], "Hi ", "text_delta text")
	eq(d["done"], false, "not done")
	d = CC.anthropic_delta("{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\"}}")
	eq(d["text"], "", "a tool-use delta is not text")
	d = CC.anthropic_delta("{\"type\":\"message_stop\"}")
	eq(d["done"], true, "message_stop is done")
	d = CC.anthropic_delta("{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}")
	ok(String(d["error"]).contains("overloaded_error") and d["done"], "stream error surfaces and ends")
	d = CC.anthropic_delta("not json")
	eq(d["text"], "", "garbage is ignored")
	d = CC.openai_delta("{\"choices\":[{\"delta\":{\"content\":\"yo\"},\"finish_reason\":null}]}")
	eq(d["text"], "yo", "openai delta content")
	eq(d["done"], false, "openai not done while finish_reason null")
	d = CC.openai_delta("{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
	eq(d["done"], true, "finish_reason ends it")
	d = CC.openai_delta("[DONE]")
	eq(d["done"], true, "[DONE] ends it")
	d = CC.openai_delta("{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}")
	eq(d["text"], "", "a role-only first delta has no text")
	d = CC.openai_delta("{\"error\":{\"message\":\"model not found\"}}")
	ok(String(d["error"]).contains("model not found"), "openai error shape")
	eq(CC.anthropic_text("{\"content\":[{\"type\":\"text\",\"text\":\"A\"},{\"type\":\"text\",\"text\":\"B\"}]}"), "AB", "whole-body anthropic text")
	eq(CC.anthropic_text("{}"), "", "no content, no text")
	eq(CC.openai_text("{\"choices\":[{\"message\":{\"content\":\"C\"}}]}"), "C", "whole-body openai text")
	eq(CC.openai_text("nope"), "", "openai garbage -> empty")
	ok(CC.api_error("{\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}", 401).contains("invalid x-api-key"), "api_error reads the message")
	ok(CC.api_error("", 502).begins_with("HTTP 502"), "api_error with no body is the code")


func _t_bodies() -> void:
	section("request bodies + headers")
	var msgs := [{"role": "user", "text": "hi"}, {"role": "assistant", "text": "hello"}, {"role": "user", "text": "again"}]
	var b = JSON.parse_string(CC.anthropic_body("m", "SYS", msgs, 77, true))
	eq(b["model"], "m", "anthropic model")
	eq(b["system"], "SYS", "anthropic system is top-level")
	eq(int(b["max_tokens"]), 77, "anthropic max_tokens")
	eq(b["stream"], true, "anthropic stream flag")
	eq((b["messages"] as Array).size(), 3, "three messages, no system among them")
	eq(b["messages"][0]["content"], "hi", "content is the text")
	var o = JSON.parse_string(CC.openai_body("lm", "SYS", msgs, 50, false))
	eq((o["messages"] as Array).size(), 4, "openai: system is message zero")
	eq(o["messages"][0]["role"], "system", "openai system role")
	eq(o["stream"], false, "openai stream flag off")
	var h := CC.anthropic_headers("sk-test")
	ok("x-api-key: sk-test" in h, "x-api-key header")
	ok(("anthropic-version: %s" % CC.ANTHROPIC_VERSION) in h, "anthropic-version header")
	ok("content-type: application/json" in h, "json content type")
	eq(CC.openai_headers("").size(), 2, "no bearer without a key")
	ok("authorization: Bearer k" in CC.openai_headers("k"), "bearer with a key")


func _t_misc() -> void:
	section("resolve_key / window / system prompts")
	eq(CC.resolve_key("env", "cfg"), "env", "environment wins")
	eq(CC.resolve_key("  ", "cfg"), "cfg", "blank env falls to cfg")
	eq(CC.resolve_key("", ""), "", "neither -> empty")
	var hist := []
	for i in range(10):
		hist.append({"role": "assistant" if i % 2 else "user", "text": str(i)})
	var w := CC.window(hist, 4)
	eq(w.size(), 4, "window keeps the last four")
	eq(w[0]["text"], "6", "starting where it should")
	w = CC.window(hist, 3)
	eq(w.size(), 2, "an odd window is trimmed to start on a user turn")
	eq(w[0]["role"], "user", "first turn is user")
	w = CC.window([], 5)
	eq(w.size(), 0, "empty stays empty")
	var sys := CC.chat_system({"pos": [1, 2, 3], "weather": "rain"})
	ok(sys.contains("\"weather\":\"rain\""), "the snapshot rides in the system prompt")
	ok(sys.contains("Myrkfell"), "and it knows what game it is in")
	ok(CC.notes_system().contains("\"notes\""), "the noter is told the JSON shape")
	ok(CC.notes_user({"a": 1}, "U", "A").contains("LEMON SAID:\nU"), "notes_user carries the exchange")


func _t_notes() -> void:
	section("parse_notes / note_line")
	var n := CC.parse_notes("```json\n{\"notes\":[{\"kind\":\"bug\",\"text\":\"grass pops at 40 m\",\"where\":\"Grass.gd\"},{\"kind\":\"weird\",\"text\":\"x\"},{\"kind\":\"idea\",\"text\":\"   \"}]}\n```")
	eq(n.size(), 2, "fenced JSON parsed; the empty note dropped")
	eq(n[0]["kind"], "bug", "kind kept")
	eq(n[0]["where"], "Grass.gd", "where kept")
	eq(n[1]["kind"], "observation", "unknown kind -> observation")
	eq(CC.parse_notes("{\"notes\":[]}").size(), 0, "empty notes")
	eq(CC.parse_notes("Sure! Here you go.").size(), 0, "no JSON -> no notes, no crash")
	eq(CC.parse_notes("{\"notes\":\"nope\"}").size(), 0, "notes not an array -> none")
	var line := CC.note_line({"kind": "bug", "text": "T", "where": "W", "when": "day 3 14:00", "pos": "@ 10, 20"})
	eq(line, "- **bug** [W] T  _(day 3 14:00, @ 10, 20)_", "note line, full")
	eq(CC.note_line({"kind": "idea", "text": "T"}), "- **idea** T", "note line, bare")


func _t_handoff() -> void:
	section("handoff_md")
	var notes := [{"kind": "idea", "text": "I1"}, {"kind": "bug", "text": "B1", "where": "Player.gd"}, {"kind": "bug", "text": "B2"}]
	var talk := [{"role": "user", "text": "hi"}, {"role": "assistant", "text": "hello"}]
	var md := CC.handoff_md("T", "now", {"fps": 60}, notes, talk)
	ok(md.begins_with("# T\n"), "title first")
	ok(md.find("### Bug") < md.find("### Idea"), "kinds in NOTE_KINDS order, bugs first")
	ok(md.contains("- **bug** [Player.gd] B1"), "bug line present")
	ok(md.contains("**Lemon:** hi") and md.contains("**Claude:** hello"), "transcript present")
	ok(md.contains("\"fps\": 60"), "snapshot at the end")
	ok(md.contains("## Notes (3)"), "note count in the heading")
	md = CC.handoff_md("T", "now", {}, [], [])
	ok(md.contains("_No durable notes this session._") and md.contains("_(empty)_"), "empty session says so")
	ok(CC.stamp_day().length() == 10, "stamp_day is YYYY-MM-DD")
	ok(CC.stamp_clock().length() == 5, "stamp_clock is HH:MM")
	eq(CC._clock(13.5), "13:30", "game clock formats")
	eq(CC._clock(-1.0), "?", "unknown hour")


# --------------------------------------------------------------------- panel

func _mk():
	## Untyped on purpose: the class is loaded by path, so its members are
	## reached dynamically.
	var c = CC.new()
	c.cfg_path = CFG
	c.notes_dir = NOTES
	c.handoff_override = HANDOFF
	root.add_child(c)
	return c


func _key(code: Key, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	return e


func _t_panel() -> void:
	section("the panel")
	var cf := ConfigFile.new()
	cf.set_value("chat", "backend", "local")
	cf.set_value("local", "url", "http://127.0.0.1:1/v1")
	cf.set_value("local", "model", "tiny")
	cf.set_value("anthropic", "api_key", "sk-cfg")
	cf.save(CFG)
	var c = _mk()
	ok(c._log != null and c._input != null and c._send != null and c._up != null, "widgets built")
	eq(c.visible, false, "starts hidden")
	eq(c.backend, "local", "cfg backend read")
	eq(c.local_model, "tiny", "cfg local model read")
	eq(c.local_url, "http://127.0.0.1:1/v1", "cfg local url read")
	ok(c.api_key == "sk-cfg" or OS.get_environment("ANTHROPIC_API_KEY").strip_edges() != "", "cfg key read (unless the environment has one)")
	eq(c.ready_to_talk(), "", "local backend with a url is ready")
	eq(c.eat_input(_key(KEY_M)), false, "hidden: takes nothing")
	c.visible = true
	eq(c.eat_input(_key(KEY_M)), true, "shown: a letter is typing, not the map")
	eq(c.eat_input(_key(KEY_G)), true, "shown: G is typing, not the creative menu")
	eq(c.eat_input(_key(KEY_ESCAPE)), false, "shown: Esc falls through to Player (close)")
	eq(c.eat_input(_key(KEY_F4)), false, "shown: F4 falls through to Player (toggle)")
	var mb := InputEventMouseButton.new()
	eq(c.eat_input(mb), false, "mouse buttons are not ours")
	var snap := c.snapshot()
	ok(snap.has("fps") and not snap.has("pos"), "snapshot without a player: fps only, no crash")
	c.backend = "anthropic"
	c.api_key = ""
	ok(c.ready_to_talk().contains("No Anthropic key"), "anthropic with no key says what is missing")
	c.send("hello?")
	ok(c._chat == null, "and refuses to send")
	c.backend = "local"
	c.send("   ")
	ok(c._chat == null and c.talk().is_empty(), "blank input is not a turn")
	c.save_cfg()
	var cf2 := ConfigFile.new()
	cf2.load(CFG)
	eq(String(cf2.get_value("chat", "backend", "")), "local", "save_cfg round-trips the backend")
	c.queue_free()


func _t_sources() -> void:
	section("sources -- F4 is Player's, the card takes no key")
	var src := read("res://scripts/ClaudeChat.gd")
	ok(src.length() > 10000, "ClaudeChat.gd read (%d bytes)" % src.length())
	for fn in ["_input", "_unhandled_input", "_unhandled_key_input", "_shortcut_input", "_gui_input"]:
		ok(not src.contains("func %s(" % fn), "no %s in the card" % fn)
	ok(not src.contains("InputMap."), "no InputMap actions registered")
	ok(src.contains("func eat_input(event: InputEvent) -> bool:"), "eat_input is the handshake")
	var pl := read("res://scripts/Player.gd")
	ok(pl.length() > 100000, "Player.gd read")
	ok(pl.contains("\t\t\tKEY_F4:\n") and pl.contains("_toggle_menu(\"claude\")"), "Player's match block has F4 -> the claude menu")
	ok(pl.contains("claude_chat.eat_input(event)"), "Player asks the card before acting on a key")
	ok(pl.find("godmode.eat_input(event)") < pl.find("claude_chat.eat_input(event)"), "after the god editor's first refusal")
	ok(pl.contains("claude_chat.visible = which == \"claude\""), "the panel table shows/hides it")
	ok(pl.contains("claude_chat = ClaudeChat.new()") and pl.contains("claude_chat.player = self"), "built by Player, told who is asking")
	var reg := read("res://tests/DevInputRegistry.gd")
	ok(reg.contains("\"tok\": \"KEY_F4\"") and reg.contains("\"expect\": \"claude\""), "DevInputRegistry has the F4 row opening 'claude'")
	var rd := read("res://README.md")
	ok(rd.contains("| F4 |"), "README lists F4")


# ---------------------------------------------------------------- the wire

func _listen() -> bool:
	for i in range(8):
		if _srv.listen(PORT_BASE + i, "127.0.0.1") == OK:
			_port = PORT_BASE + i
			return true
	return false


var _reqs: Array = []
var _serving := false


func _serve(responses: Array) -> void:
	## Accept one connection per response, read its request whole (headers
	## plus Content-Length body), write the response in the pieces given
	## (each piece: a String, written with a frame's gap so the client sees
	## real chunk boundaries), then close. Fire-and-forget: the request texts
	## land in _reqs and _serving drops when every response has gone out --
	## `await _served()` for them.
	_reqs = []
	_serving = true
	for pieces in responses:
		var peer: StreamPeerTCP = null
		var req := ""
		var frames := 0
		while frames < 900:
			if peer == null and _srv.is_connection_available():
				peer = _srv.take_connection()
			if peer != null:
				peer.poll()
				var n := peer.get_available_bytes()
				if n > 0:
					req += peer.get_utf8_string(n)
				var hdr_end := req.find("\r\n\r\n")
				if hdr_end >= 0:
					var want := 0
					for ln in req.substr(0, hdr_end).split("\r\n"):
						if ln.to_lower().begins_with("content-length:"):
							want = int(ln.substr(15).strip_edges())
					if req.length() - (hdr_end + 4) >= want:
						break
			await process_frame
			frames += 1
		_reqs.append(req)
		if peer == null:
			continue
		for p in pieces:
			peer.put_data(String(p).to_utf8_buffer())
			await process_frame
			await process_frame
		peer.disconnect_from_host()
	_serving = false


func _served() -> Array:
	var frames := 0
	while _serving and frames < 2400:
		await process_frame
		frames += 1
	return _reqs


static func chunked(head: String, datas: Array) -> Array:
	## An HTTP/1.1 chunked response: the header block, then one chunk per
	## data string, then the terminator -- as separate write pieces.
	var out: Array = [head]
	for d in datas:
		var s := String(d)
		out.append("%x\r\n%s\r\n" % [s.to_utf8_buffer().size(), s])
	out.append("0\r\n\r\n")
	return out


const SSE_HEAD := "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"


func _t_wire() -> void:
	section("the wire -- Http against a fake server")
	ok(_listen(), "fake server listening on 127.0.0.1:%d" % _port)
	if _port == 0:
		return
	## 1. a chunked SSE stream, openai shape, cut mid-event on purpose
	var ev := "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"lo wörld\"}}]}\n\n"
	var pieces := chunked(SSE_HEAD, [ev.substr(0, 37), ev.substr(37), "data: [DONE]\n\n"])
	var h := CC.Http.new()
	h.begin("http://127.0.0.1:%d/v1/chat/completions" % _port, CC.openai_headers(""), "{\"x\":1}", true)
	_serve([pieces])
	var frames := 0
	var got := ""
	var done := false
	while frames < 900 and not done:
		h.poll()
		while not h.events.is_empty():
			var d := CC.openai_delta(String(h.events.pop_front()))
			got += String(d["text"])
			if d["done"]:
				done = true
		if h.done:
			break
		await process_frame
		frames += 1
	var reqs: Array = await _served()
	eq(got, "Hello wörld", "the streamed text reassembled across chunk cuts, UTF-8 intact")
	eq(h.status_code, 200, "status 200")
	eq(h.error, "", "no transport error")
	ok(String(reqs[0]).begins_with("POST /v1/chat/completions HTTP/1.1"), "it POSTed to the path")
	ok(String(reqs[0]).contains("{\"x\":1}"), "with the body")
	ok(String(reqs[0]).to_lower().contains("content-type: application/json"), "and the json header")
	## 2. a 401 with a JSON body, non-streaming
	var body := "{\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"
	var resp := "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.length(), body]
	var h2 := CC.Http.new()
	h2.begin("http://127.0.0.1:%d/v1/messages" % _port, CC.anthropic_headers("bad"), "{}", false)
	_serve([[resp]])
	frames = 0
	while frames < 900 and not h2.done:
		h2.poll()
		await process_frame
		frames += 1
	await _served()
	eq(h2.status_code, 401, "401 seen")
	eq(h2.text, body, "whole body read")
	ok(CC.api_error(h2.text, h2.status_code).contains("invalid x-api-key"), "and it reads as the API's message")
	## 3. nobody home
	var h3 := CC.Http.new()
	h3.begin("http://127.0.0.1:1/v1/messages", CC.anthropic_headers("k"), "{}", true)
	frames = 0
	while frames < 900 and not h3.done:
		h3.poll()
		await process_frame
		frames += 1
	ok(h3.done and h3.error != "", "a dead port fails with a reason: %s" % h3.error)


func _t_exchange() -> void:
	section("a whole exchange -- send, stream, note, file, up the line")
	if _port == 0:
		return
	var c = _mk()
	c.backend = "local"
	c.api_key = ""
	c.local_url = "http://127.0.0.1:%d/v1" % _port
	c.local_model = "tiny"
	c.notes_on = true
	c.visible = true
	## response 1: the chat reply (SSE). response 2: the noter (whole body).
	var reply := chunked(SSE_HEAD, [
		"data: {\"choices\":[{\"delta\":{\"content\":\"The grass \"}}]}\n\n",
		"data: {\"choices\":[{\"delta\":{\"content\":\"pops at 40 m.\"},\"finish_reason\":\"stop\"}]}\n\n",
		"data: [DONE]\n\n"])
	var notes_json := "{\"notes\":[{\"kind\":\"bug\",\"text\":\"grass pops in at 40 m near Portland\",\"where\":\"Grass.gd\"}]}"
	var nbody := JSON.stringify({"choices": [{"message": {"role": "assistant", "content": "```json\n%s\n```" % notes_json}}]})
	var nresp := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [nbody.to_utf8_buffer().size(), nbody]
	_serve([reply, [nresp]])
	c.send("why does the grass pop in?")
	ok(c._chat != null, "a send puts a call in flight")
	var frames := 0
	while frames < 1200 and (c._chat != null or c._noter != null or not c._noter_pending.is_empty() or c.notes.is_empty()):
		await process_frame
		frames += 1
	var reqs: Array = await _served()
	eq(reqs.size(), 2, "two calls went out: the chat and the noter")
	var t := c.talk()
	eq(t.size(), 2, "user + assistant in the transcript")
	eq(t[1]["text"], "The grass pops at 40 m.", "the streamed reply, whole")
	var req0 = JSON.parse_string(String(reqs[0]).substr(String(reqs[0]).find("\r\n\r\n") + 4))
	ok(req0 is Dictionary and req0["stream"] == true and req0["model"] == "tiny", "the chat call streamed on the local model")
	ok(req0 is Dictionary and String(req0["messages"][0]["content"]).contains("GAME STATE"), "with the snapshot in the system message")
	var req1 = JSON.parse_string(String(reqs[1]).substr(String(reqs[1]).find("\r\n\r\n") + 4))
	ok(req1 is Dictionary and req1["stream"] == false, "the noter did not stream")
	ok(req1 is Dictionary and String(req1["messages"][1]["content"]).contains("why does the grass pop in?"), "and was handed the exchange")
	eq(c.notes.size(), 1, "one note taken")
	eq(c.notes[0]["kind"], "bug", "a bug")
	eq(c._unsent, 1, "unsent")
	var nfile := "%s/%s.md" % [NOTES, CC.stamp_day()]
	var ntext := read(nfile)
	ok(ntext.contains("- **bug** [Grass.gd] grass pops in at 40 m near Portland"), "the note landed in today's notes file")
	ok(ntext.begins_with("# Claude notes -- "), "with a heading")
	var path := c.send_up_the_line(false)
	ok(path.begins_with(HANDOFF + "/"), "up the line writes under the handoff dir: %s" % path)
	var md := read(path)
	ok(md.contains("### Bug") and md.contains("**Lemon:** why does the grass pop in?") and md.contains("**Claude:** The grass pops at 40 m."), "the handoff carries notes and transcript")
	eq(c._unsent, 0, "nothing unsent after sending")
	eq(c.send_up_the_line(true), "", "the exit path writes nothing when nothing is unsent")
	c._unsent = 1
	var p2 := c.send_up_the_line(true)
	ok(p2 != "" and p2 != path, "the exit path writes when notes are unsent, to a fresh name")
	c.queue_free()


func _cleanup() -> void:
	_srv.stop()
	for p in [CFG]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for d in [NOTES, HANDOFF]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			da.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d))
