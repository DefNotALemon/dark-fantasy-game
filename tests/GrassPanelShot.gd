extends SceneTree
## GrassPanelShot — a picture of the F3 panel itself.
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x800 \
##       --script res://tests/GrassPanelShot.gd -- <out_dir>
##
## GrassLabTests proves the panel BUILDS and that every knob is wired. It
## cannot say whether you can read it, or whether it still swallows the
## screen. This puts it on a CanvasLayer at a real window size and saves one
## PNG per tab, which is the only way to check "more readable, different
## spot" without opening the game.

var _lab: GrassLab
var _tabs: TabContainer
var _out := "user://panel/"
var _i := 0
var _wait := 6


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = String(args[0])
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)

	## a flat ground colour behind the panel so the card's own background and
	## border are visible -- on black they read as nothing
	var bg := ColorRect.new()
	bg.color = Color(0.24, 0.30, 0.18)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(bg)

	## the panel finds the meadow through the "grass_system" group on open, and
	## only then does it list the presets -- without one in the tree the
	## palette shows a single swatch and the shot proves nothing
	var gs := GrassSystem.new()
	root.add_child(gs)

	_lab = GrassLab.new()
	_lab.visible = false
	layer.add_child(_lab)
	_lab.visible = true      ## fires visibility_changed -> _load_presets()
	for c in _lab.find_children("*", "TabContainer", true, false):
		_tabs = c as TabContainer
		break
	process_frame.connect(_tick)


func _tick() -> void:
	_wait -= 1
	if _wait > 0:
		return
	if _tabs == null or _i >= _tabs.get_tab_count():
		print("GrassPanelShot: done")
		quit()
		return
	## save the tab that is ALREADY showing, then switch and wait -- setting
	## current_tab and grabbing in the same frame photographs the old tab
	var name_v := _tabs.get_tab_title(_i)
	root.get_texture().get_image().save_png("%s%d_%s.png" % [_out, _i, name_v.to_lower()])
	print("  tab %d %s" % [_i, name_v])
	_i += 1
	if _i < _tabs.get_tab_count():
		_tabs.current_tab = _i
	_wait = 3
