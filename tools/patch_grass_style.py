#!/usr/bin/env python3
"""The Grass Lab's half of scripts/Grass.gd — a `style` dictionary, apply_style(),
the shader's new uniforms, and the placer reading its knobs off plain floats.

    python3 tools/patch_grass_style.py --check     # report, touch nothing
    python3 tools/patch_grass_style.py             # patch scripts/Grass.gd

Every hunk is anchored on an exact, unique piece of the v2.7 source and skipped
when its marker is already there, so a second run is a no-op. Backup goes to
<root>/../dark-fantasy-game-grass-backup-<stamp>/Grass.gd.
"""
import argparse, datetime, os, shutil, sys

MARK = "GRASS LAB (F3)"

HUNKS = []  # (name, old, new) — old must occur exactly once


def h(name, old, new):
    HUNKS.append((name, old, new))


# ----------------------------------------------------------------- state ----
h("S1 style block before _ready", '''func _ready() -> void:
	add_to_group("grass_system")  ## the sword asks for cuts through here
''', '''## --- GRASS LAB (F3) -----------------------------------------------------------
## Every number the look of the meadow hangs on, in ONE dictionary, so the F3
## lab (scripts/GrassLab.gd) can drag it around live and a chosen style can be
## SHIPPED as design/grass_style.json. Three groups by what a change costs:
##   shader    -> a uniform, instant
##   geometry  -> _build_meshes() + repoint every chunk's MultiMesh, ~ms
##   placement -> re-place the whole ring (reseed()), the expensive one
## The defaults ARE the v2.7 numbers, so a style with nothing in it is the game
## exactly as it was. Colours are "#rrggbb" strings (sRGB, like the shader's
## source_color defaults). The schema string is what the browser bench exports.
const STYLE_SCHEMA := "myrkfell.grass_style/1"
const STYLE_FILE := "res://design/grass_style.json"       ## the SHIPPED style
const STYLE_DIR := "res://design/grass_styles"           ## the presets
const STYLE_DEFAULTS := {
	## placement
	"density": 1.0,        ## x TUFTS_PER_CHUNK attempts (0..3)
	"tall_keep": 0.235,    ## the tall-patch keep roll
	"short_keep": 0.94,    ## SHORT_KEEP
	"clump_cut": -0.62,    ## clump-noise trough below which nothing grows
	"tall_shift": 0.0,     ## added to TALL_T: + = fewer hiding patches, - = more
	"size_var": 1.0,       ## spread of the per-tuft scale rolls (0 = all the same)
	"vigour": 1.0,         ## x the lush/moist height term
	"tint_dry": 0.55,      ## thin-ground burn strength
	"tint_moist": 0.45,    ## damp-ground depth strength
	"w_fescue": 1.0, "w_sedge": 1.0, "w_timothy": 1.0, "w_bluestem": 1.0,
	"w_flower": 1.0, "w_clover": 1.0, "w_fern": 1.0, "w_moss": 1.0,
	## geometry (the fescue tuft and the hiding grass)
	"height": 0.18, "width": 0.030, "blades": 4, "segs": 4, "lean": 0.35, "droop": 0.55,
	"tall_height": 1.35, "tall_width": 0.068,
	## shader
	"col_spring": "#598730", "col_summer": "#406626", "col_autumn": "#877330", "col_winter": "#665c3d",
	"col_dry": "#8f7a40", "col_moss": "#305424", "col_snow": "#ccd6e6", "col_seedhead": "#b39966",
	"col_bluestem_summer": "#577557", "col_bluestem_cured": "#9e5433",
	"pixel_on": 1.0, "cells": 8.0, "side_cells": 3.0, "palette": 5.0, "jitter": 0.14,
	"hue_var": 0.12, "val_var": 0.38, "root_dark": 0.62, "tip_light": 0.40,
	"bands": 4.0, "backlight": 1.0, "normal_up": 0.48, "snow": 1.0, "posterize_gamma": 1.0,
}
const PLACEMENT_KEYS := ["density", "tall_keep", "short_keep", "clump_cut", "tall_shift", "size_var",
	"vigour", "tint_dry", "tint_moist", "w_fescue", "w_sedge", "w_timothy", "w_bluestem", "w_flower",
	"w_clover", "w_fern", "w_moss"]
const GEOMETRY_KEYS := ["height", "width", "blades", "segs", "lean", "droop", "tall_height", "tall_width"]
## shader key -> uniform name (a colour key lands as a Color)
const SHADER_UNIFORMS := {
	"col_spring": "col_spring", "col_summer": "col_summer", "col_autumn": "col_autumn",
	"col_winter": "col_winter", "col_dry": "col_dry", "col_moss": "col_moss", "col_snow": "col_snow",
	"col_seedhead": "col_seedhead", "col_bluestem_summer": "col_bluestem_summer",
	"col_bluestem_cured": "col_bluestem_cured",
	"pixel_on": "pixel_on", "cells": "pixel_cells", "side_cells": "pixel_side_cells",
	"palette": "palette_steps", "jitter": "cell_jitter", "hue_var": "hue_var", "val_var": "val_var",
	"root_dark": "root_dark", "tip_light": "tip_light", "bands": "light_bands", "backlight": "backlight",
	"normal_up": "normal_up", "snow": "snow_amount", "posterize_gamma": "posterize_gamma",
}
var style: Dictionary = STYLE_DEFAULTS.duplicate(true)
## The placer runs on WORKER THREADS and must not read a Dictionary the main
## thread is editing, so the placement knobs are mirrored into plain members
## by _sync_placement_style() -- written on the main thread only, before the
## reseed that makes them visible. Same rule as _gpu_on.
var _s_attempts := TUFTS_PER_CHUNK
var _s_tall_keep := 0.235
var _s_short_keep := SHORT_KEEP
var _s_clump_cut := -0.62
var _s_tall_shift := 0.0
var _s_size_var := 1.0
var _s_vigour := 1.0
var _s_tint_dry := 0.55
var _s_tint_moist := 0.45
var _s_w_fescue := 1.0
var _s_w_sedge := 1.0
var _s_w_timothy := 1.0
var _s_w_bluestem := 1.0
var _s_w_flower := 1.0
var _s_w_clover := 1.0
var _s_w_fern := 1.0
var _s_w_moss := 1.0


func apply_style(d: Dictionary, rebuild := true) -> Dictionary:
	## Merge `d` into the live style and do the CHEAPEST thing that makes it
	## visible. Unknown keys are ignored (a bench export carries wind and sun
	## knobs the game drives itself). Returns which groups changed.
	var changed := {"shader": false, "meshes": false, "placement": false}
	for k in d.keys():
		var key := String(k)
		if not STYLE_DEFAULTS.has(key):
			continue
		var v: Variant = d[k]
		var cur: Variant = style.get(key)
		if cur is String:
			v = String(v)
		elif v is bool:
			v = 1.0 if v else 0.0
		elif cur is int:
			v = int(v)
		else:
			v = float(v)
		if typeof(cur) == typeof(v) and cur == v:
			continue
		style[key] = v
		if GEOMETRY_KEYS.has(key):
			changed["meshes"] = true
		elif PLACEMENT_KEYS.has(key):
			changed["placement"] = true
		else:
			changed["shader"] = true
	_push_style_uniforms()
	_sync_placement_style()
	if rebuild and _mat != null:
		if bool(changed["meshes"]):
			rebuild_meshes()
		if bool(changed["placement"]):
			reseed()
	return changed


func _push_style_uniforms() -> void:
	if _mat == null:
		return
	for key: String in SHADER_UNIFORMS:
		var v: Variant = style[key]
		if v is String:
			_mat.set_shader_parameter(String(SHADER_UNIFORMS[key]), Color.html(String(v)))
		else:
			_mat.set_shader_parameter(String(SHADER_UNIFORMS[key]), float(v))


func _sync_placement_style() -> void:
	_s_attempts = int(clampf(float(style["density"]), 0.0, 3.0) * TUFTS_PER_CHUNK)
	_s_tall_keep = float(style["tall_keep"])
	_s_short_keep = float(style["short_keep"])
	_s_clump_cut = float(style["clump_cut"])
	_s_tall_shift = float(style["tall_shift"])
	_s_size_var = float(style["size_var"])
	_s_vigour = float(style["vigour"])
	_s_tint_dry = float(style["tint_dry"])
	_s_tint_moist = float(style["tint_moist"])
	_s_w_fescue = float(style["w_fescue"])
	_s_w_sedge = float(style["w_sedge"])
	_s_w_timothy = float(style["w_timothy"])
	_s_w_bluestem = float(style["w_bluestem"])
	_s_w_flower = float(style["w_flower"])
	_s_w_clover = float(style["w_clover"])
	_s_w_fern = float(style["w_fern"])
	_s_w_moss = float(style["w_moss"])


func rebuild_meshes() -> void:
	## New geometry, same instances: every chunk's MultiMesh is repointed at
	## the mesh its LOD band already names. No re-placement, no reupload.
	_build_meshes()
	for key: Vector2i in _chunks:
		var lod := int(_chunk_lod.get(key, 6))
		for kind: String in _chunks[key]:
			var mmi := _chunks[key][kind] as MultiMeshInstance3D
			if mmi.multimesh != null:
				mmi.multimesh.mesh = (_mesh[kind] as Array)[lod & 3]


func reseed() -> void:
	## Throw the whole ring away and place it again with the current knobs.
	## The expensive one (it is warm(), synchronous) -- the lab debounces it.
	if _job_gid >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_job_gid)
		_job_gid = -1
	_pending.clear()
	_queue.clear()
	_apply_q.clear()
	_bkeys.clear()
	_bresults.clear()
	for key: Vector2i in _chunks.keys():
		for kind: String in _chunks[key]:
			(_chunks[key][kind] as Node).queue_free()
	_chunks.clear()
	_chunk_lod.clear()
	if field != null:
		warm(_focus)


static func style_from_json(text: String) -> Dictionary:
	## A bench export ({schema, name, params}) or a bare dictionary of keys.
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var d := parsed as Dictionary
	if d.has("params") and d["params"] is Dictionary:
		return (d["params"] as Dictionary).duplicate()
	return d


static func load_style_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return style_from_json(FileAccess.get_file_as_string(path))


func style_to_json(name_v: String, based_on := "") -> String:
	var out := {"schema": STYLE_SCHEMA, "name": name_v, "based_on": based_on,
		"exported": Time.get_datetime_string_from_system(), "params": style.duplicate(true)}
	return JSON.stringify(out, "\\t")


func save_style_file(path: String, name_v: String, based_on := "") -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(style_to_json(name_v, based_on))
	f.close()
	return true


static func preset_files() -> Array:
	## [{name, path}] for every design/grass_styles/*.json, name-sorted.
	var out: Array = []
	if not DirAccess.dir_exists_absolute(STYLE_DIR):
		return out
	for fn in DirAccess.get_files_at(STYLE_DIR):
		var f := String(fn)
		if not f.ends_with(".json"):
			continue
		var path := STYLE_DIR + "/" + f
		var nm := f.get_basename()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).has("name"):
			nm = String((parsed as Dictionary)["name"])
		out.append({"name": nm, "path": path, "file": f.get_basename()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return out


func _ready() -> void:
	add_to_group("grass_system")  ## the sword asks for cuts through here
''')

# ----------------------------------------------------------------- setup ----
h("S2 setup loads the shipped style", '''	_build_material()
	_build_meshes()
	_ncx = int(ceil(float(CaveField.CELLS_X) / CHUNK_CELLS))''', '''	_build_material()
	## GRASS LAB (F3): the shipped style, if one was saved, is the game's look --
	## applied before the first mesh is built so it is not a dev-only overlay.
	var shipped := load_style_file(STYLE_FILE)
	if not shipped.is_empty():
		apply_style(shipped, false)
	else:
		_push_style_uniforms()
		_sync_placement_style()
	_build_meshes()
	_ncx = int(ceil(float(CaveField.CELLS_X) / CHUNK_CELLS))''')

# -------------------------------------------------------------- geometry ----
h("G1 fescue tuft from the style", '''	_mesh["std"] = [
		_tuft(0.18, 0.030, 4, 4, 0.35, 0.55),
		_tuft(0.18, 0.030, 4, 2, 0.35, 0.55),
		_tuft(0.18, 0.036, 3, 1, 0.35, 0.55),
	]''', '''	## GRASS LAB (F3): the fescue reads its shape off `style`; the defaults
	## are the v2.7 numbers above, so an empty style is this exact ladder.
	var sh := float(style["height"])
	var sw := float(style["width"])
	var sb := maxi(1, int(style["blades"]))
	var ss := maxi(1, int(style["segs"]))
	var sl := float(style["lean"])
	var sd := float(style["droop"])
	_mesh["std"] = [
		_tuft(sh, sw, sb, ss, sl, sd),
		_tuft(sh, sw, sb, mini(ss, 2), sl, sd),
		_tuft(sh, sw * 1.2, maxi(1, mini(sb, 3)), 1, sl, sd),
	]''')

h("G2 tall tuft from the style", '''	_mesh["tall"] = [
		_tuft(1.35, 0.068, 6, 4, 0.30, 0.80),
		_tuft(1.35, 0.068, 5, 2, 0.30, 0.80),
		_tuft(1.35, 0.076, 3, 1, 0.30, 0.80),
	]''', '''	var th := float(style["tall_height"])
	var tw := float(style["tall_width"])
	_mesh["tall"] = [
		_tuft(th, tw, 6, 4, 0.30, 0.80),
		_tuft(th, tw, 5, 2, 0.30, 0.80),
		_tuft(th, tw * 1.12, 3, 1, 0.30, 0.80),
	]''')

# ------------------------------------------------------------- placement ----
h("P1 tall threshold", '''	return _tall.get_noise_2d(wx, wz) > TALL_T
''', '''	return _tall.get_noise_2d(wx, wz) > TALL_T + _s_tall_shift   ## GRASS LAB (F3)
''')

h("P2 pick_kind weights", '''	if in_tall:
		if cut:
			return K_STUB
		return K_SEDGE if moist > 0.30 else K_TALL
	var r := rng.randf()
	if moist > 0.50 and r < 0.14:
		return K_MOSS
	if moist > 0.32 and r < 0.30:
		return K_FERN
	if lush > 0.22 and r < 0.24:
		return K_CLOVER
	if lush > 0.06 and r < 0.055:
		return K_FLOWER''', '''	## GRASS LAB (F3): each gate's probability is scaled by that species'
	## weight, so every weight at 1.0 is this function exactly as it was, a
	## weight of 0 removes the species, and -1 means "nothing grows here".
	if in_tall:
		if cut:
			return K_STUB
		return K_SEDGE if moist > 0.30 and _s_w_sedge > 0.0 else K_TALL
	var r := rng.randf()
	if moist > 0.50 and r < 0.14 * _s_w_moss:
		return K_MOSS
	if moist > 0.32 and r < 0.30 * _s_w_fern:
		return K_FERN
	if lush > 0.22 and r < 0.24 * _s_w_clover:
		return K_CLOVER
	if lush > 0.06 and r < 0.055 * _s_w_flower:
		return K_FLOWER''')

h("P3 pick_kind tail weights", '''	if lush < -0.10 and moist < 0.25 and r < 0.55:
		return K_BLUESTEM
	if lush > -0.05 and r < 0.085:
		return K_TIMOTHY
	return K_STD
''', '''	if lush < -0.10 and moist < 0.25 and r < 0.55 * _s_w_bluestem:
		return K_BLUESTEM
	if lush > -0.05 and r < 0.085 * _s_w_timothy:
		return K_TIMOTHY
	if _s_w_fescue < 1.0 and rng.randf() >= _s_w_fescue:
		return -1
	return K_STD
''')

h("P4 attempts", '''	for _i in range(TUFTS_PER_CHUNK):
		var wx := ox + rng.randf() * CHUNK_M''', '''	for _i in range(_s_attempts):   ## GRASS LAB (F3): TUFTS_PER_CHUNK x style density
		var wx := ox + rng.randf() * CHUNK_M''')

h("P5 tall keep", '''			if rng.randf() > 0.235 * cover:
				continue      ## HALF the v2.1 tall density (per Lemon), against''',
  '''			if rng.randf() > _s_tall_keep * cover:   ## GRASS LAB (F3): 0.235 by default
				continue      ## HALF the v2.1 tall density (per Lemon), against''')

h("P6 short keep", '''		elif rng.randf() > (0.88 + _density.get_noise_2d(wx, wz) * 0.10) * SHORT_KEEP * cover:
			continue''', '''		elif rng.randf() > (0.88 + _density.get_noise_2d(wx, wz) * 0.10) * _s_short_keep * cover:
			continue''')

h("P7 clump cut", '''		if not in_tall and _clump.get_noise_2d(wx, wz) < -0.62:
			continue''', '''		if not in_tall and _clump.get_noise_2d(wx, wz) < _s_clump_cut:
			continue''')

h("P8 kind skip", '''		var kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)
''', '''		var kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)
		if kind < 0:
			continue      ## GRASS LAB (F3): the fescue weight said no
''')

h("P9 vigour and size", '''		var vigour := 1.0 + lush * 0.34 + moist * 0.12
		var sxz := rng.randf_range(0.82, 1.28)
		var sy := rng.randf_range(0.72, 1.36) * vigour''', '''		var vigour := (1.0 + lush * 0.34 + moist * 0.12) * _s_vigour
		var sxz := 1.0 + (rng.randf_range(0.82, 1.28) - 1.0) * _s_size_var
		var sy := (1.0 + (rng.randf_range(0.72, 1.36) - 1.0) * _s_size_var) * vigour''')

h("P10 tint strengths", '''		tint = tint.lerp(Color(1.18, 1.06, 0.72), dry * 0.55)          ## thin ground burns off
		tint = tint.lerp(Color(0.82, 1.02, 0.80), clampf(moist, 0.0, 1.0) * 0.45)  ## damp ground is deeper''',
  '''		tint = tint.lerp(Color(1.18, 1.06, 0.72), dry * _s_tint_dry)          ## thin ground burns off
		tint = tint.lerp(Color(0.82, 1.02, 0.80), clampf(moist, 0.0, 1.0) * _s_tint_moist)  ## damp ground is deeper''')

# ---------------------------------------------------------------- shader ----
h("H1 uniforms", '''uniform float pixel_cells : hint_range(4.0, 32.0) = 8.0;
uniform float pixel_side_cells : hint_range(1.0, 6.0) = 3.0;
uniform float palette_steps : hint_range(3.0, 16.0) = 5.0;
uniform float cell_jitter : hint_range(0.0, 0.5) = 0.14;
''', '''uniform float pixel_cells : hint_range(4.0, 32.0) = 8.0;
uniform float pixel_side_cells : hint_range(1.0, 6.0) = 3.0;
uniform float palette_steps : hint_range(2.0, 16.0) = 5.0;
uniform float cell_jitter : hint_range(0.0, 0.5) = 0.14;
// --- GRASS LAB (F3): the knobs that used to be literals ---------------------
uniform float pixel_on : hint_range(0.0, 1.0) = 1.0;        // 0 = smooth blades, no cells, no posterize
uniform float hue_var : hint_range(0.0, 0.5) = 0.12;        // per-plant hue rotate
uniform float val_var : hint_range(0.0, 1.0) = 0.38;        // per-plant value spread
uniform float root_dark : hint_range(0.0, 1.0) = 0.62;      // how much darker the root cells are
uniform float tip_light : hint_range(0.0, 1.0) = 0.40;      // the yellowing of the tip cells
uniform float light_bands : hint_range(1.0, 6.0) = 4.0;     // 1 = smooth Lambert, 4 = the hand-picked game bands
uniform float backlight : hint_range(0.0, 1.0) = 1.0;       // sun through a thin blade lights the tip
uniform float normal_up : hint_range(0.0, 1.0) = 0.48;      // how far the root's normal is bent toward up
uniform float posterize_gamma : hint_range(0.0, 1.0) = 1.0; // posterize in gamma space (1) or linear (0)
''')

h("H2 fragment variance", '''	if (v_matid < 0.5) {
		// no two plants the same green: value spread, then a small hue rotate
		col *= 0.80 + 0.38 * v_hash;
		col = mix(col, col.gbr, (v_hash - 0.5) * 0.12);
	}''', '''	if (v_matid < 0.5) {
		// no two plants the same green: value spread, then a small hue rotate
		col *= (1.0 - val_var * 0.5) + val_var * v_hash;
		col = mix(col, col.gbr, (v_hash - 0.5) * hue_var);
	}''')

h("H3 fragment cells", '''	float cu = (floor(v_u * pixel_cells) + 0.5) / pixel_cells;
	float cs = floor(v_side * pixel_side_cells);
	// one stable random per cell per plant — sprite-noise, not film grain
	float cj = fract(sin(cu * 127.1 + cs * 311.7 + v_hash * 74.7) * 43758.5453);
	col *= 1.0 - cell_jitter * 0.5 + cell_jitter * cj;

	// Depth in the mass, per-cell: shaded root cells, lit yellowing tip cells.
	col *= mix(0.38, 1.0, smoothstep(0.0, 0.55, cu));
	col = mix(col, col * vec3(1.22, 1.15, 0.76), smoothstep(0.5, 1.0, cu) * 0.40);
''', '''	bool px = pixel_on > 0.5;
	float cu = px ? (floor(v_u * pixel_cells) + 0.5) / pixel_cells : v_u;
	float cs = px ? floor(v_side * pixel_side_cells) : v_side;
	// one stable random per cell per plant — sprite-noise, not film grain
	float cj = fract(sin(cu * 127.1 + cs * 311.7 + v_hash * 74.7) * 43758.5453);
	if (px) col *= 1.0 - cell_jitter * 0.5 + cell_jitter * cj;

	// Depth in the mass, per-cell: shaded root cells, lit yellowing tip cells.
	col *= mix(1.0 - root_dark, 1.0, smoothstep(0.0, 0.55, cu));
	col = mix(col, col * vec3(1.22, 1.15, 0.76), smoothstep(0.5, 1.0, cu) * tip_light);
''')

h("H4 posterize in gamma space", '''	// ---- and POSTERIZE: the whole meadow shares one limited palette ----
	col = floor(col * palette_steps + 0.5) / palette_steps;

	ALBEDO = col;

	// ROUNDED NORMALS, then blended toward world-up at the base. The tips stay
	// round so they read as blades; the roots read as ground. Without the
	// blend a meadow sparkles like tinsel at every camera move.
	vec3 n = normalize(mix(v_wnormal, vec3(0.0, 1.0, 0.0), mix(0.48, 0.06, v_u)));''',
  '''	// ---- and POSTERIZE: the whole meadow shares one limited palette ----
	// In GAMMA space by default (GRASS LAB, 2026-09-12): the steps then land
	// where the eye sees them. Posterizing the LINEAR value crushed every dark
	// tint into the bottom step -- a shaded tuft came out black, and the
	// warmed winter blade rounded into the red cell (the bright-red winter
	// meadow). 16 steps is "no posterize".
	if (px && palette_steps < 15.5) {
		if (posterize_gamma > 0.5) {
			col = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
			col = floor(col * palette_steps + 0.5) / palette_steps;
			col = pow(col, vec3(2.2));
		} else {
			col = floor(col * palette_steps + 0.5) / palette_steps;
		}
	}

	ALBEDO = col;

	// ROUNDED NORMALS, then blended toward world-up at the base. The tips stay
	// round so they read as blades; the roots read as ground. Without the
	// blend a meadow sparkles like tinsel at every camera move.
	vec3 n = normalize(mix(v_wnormal, vec3(0.0, 1.0, 0.0), mix(normal_up, 0.06, v_u)));''')

h("H5 light bands", '''	float nl = dot(NORMAL, LIGHT);
	float band;
	if (nl > 0.55) band = 1.0;
	else if (nl > 0.18) band = 0.72;
	else if (nl > -0.12) band = 0.45;
	else band = 0.26;''', '''	float nl = dot(NORMAL, LIGHT);
	float band;
	if (light_bands > 3.5 && light_bands < 4.5) {
		// the game's own four, hand-picked
		if (nl > 0.55) band = 1.0;
		else if (nl > 0.18) band = 0.72;
		else if (nl > -0.12) band = 0.45;
		else band = 0.26;
	} else if (light_bands < 1.5) {
		band = 0.26 + 0.74 * clamp(nl * 0.5 + 0.5, 0.0, 1.0);   // smooth Lambert
	} else {
		float nb = floor(light_bands + 0.5);
		float q = floor(clamp(nl * 0.5 + 0.5, 0.0, 0.999) * nb) / (nb - 1.0);
		band = 0.26 + 0.74 * q;
	}''')

h("H6 backlight", '''	float bband = back > 0.6 ? 0.42 : (back > 0.25 ? 0.20 : 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * bband * v_u * (1.0 - wetness * 0.45) * ATTENUATION / PI;''',
  '''	float bband = (back > 0.6 ? 0.42 : (back > 0.25 ? 0.20 : 0.0)) * backlight;
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * bband * v_u * (1.0 - wetness * 0.45) * ATTENUATION / PI;''')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    path = os.path.join(a.root, "scripts", "Grass.gd")
    src = open(path, encoding="utf-8", newline="").read()
    if MARK in src:
        print("Grass.gd already carries the GRASS LAB hunks; nothing to do")
        return
    out = src
    for name, old, new in HUNKS:
        n = out.count(old)
        if n != 1:
            raise SystemExit("%s: anchor matches %d times, want 1" % (name, n))
        out = out.replace(old, new, 1)
        print("  %-32s +%d / -%d" % (name, new.count("\n"), old.count("\n")))
    print("Grass.gd: %+d lines" % (out.count("\n") - src.count("\n")))
    if a.check:
        return
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    bdir = os.path.join(os.path.dirname(os.path.abspath(a.root)), "dark-fantasy-game-grass-backup-%s" % stamp)
    os.makedirs(bdir, exist_ok=True)
    shutil.copy2(path, os.path.join(bdir, "Grass.gd"))
    open(path, "w", encoding="utf-8", newline="").write(out)
    print("written; backup in", bdir)


if __name__ == "__main__":
    main()
