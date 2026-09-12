#!/usr/bin/env python3
"""tools/mutate_map.py -- A GREEN SUITE IS EVIDENCE ABOUT THE SUITE.

Reintroduce, one at a time, every bug this round actually made or could have
made, and confirm tests/MapLayerTests.gd goes RED. A mutation that survives is
naming a test nobody wrote -- or a redundancy, or dead code, and then the right
answer is to DELETE THE CODE rather than add an assertion.

⚠ A BAD ANCHOR IS NOT A CAUGHT MUTATION. Every anchor's match count is checked
before it is applied, and a miss is reported as a MISS, never as a catch.
"""
import subprocess, sys, os, shutil

ROOT = "/Users/lemon/dark-fantasy-game"
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/MapLayerTests.gd"
L = "scripts/MapLayers.gd"
P = "scripts/MapPanel.gd"

# (file, old, new, why, expected_matches)  -- expected_matches None == exactly 1
M = [
 # ---- the partition IS region_at -----------------------------------------
 (L, "if d < rr[k] and d < bd:", "if d < bd:",
  "drop the containing-circle rule: nearest centre alone"),
 (L, "out[row + i] = best if best >= 0 else near", "out[row + i] = near",
  "ignore the containing circle entirely"),
 (L, "var wz := origin.y + (float(j) + 0.5) * ch", "var wz := origin.y + float(j) * ch",
  "sample the cell CORNER instead of its centre, in z"),
 (L, "var wx := origin.x + (float(i) + 0.5) * cw", "var wx := origin.x + float(i) * cw",
  "sample the cell corner instead of its centre, in x"),
 (L, "\t\t\t\t\tnear = k", "\t\t\t\t\tnear = 0",
  "always fall back to the first roster entry"),
 (L, "return Vector2(origin.x + i / float(nx) * size.x,",
     "return Vector2(origin.x + i / float(nz) * size.x,",
  "swap nx for nz in the corner mapping"),
 (L, "\t\t\torigin.y + j / float(nz) * size.y)", "\t\t\torigin.y - j / float(nz) * size.y)",
  "flip the sign of the corner mapping in z"),
 # ---- a coastline is not a frontier --------------------------------------
 (L, "if sa != sb and sa != NONE and sb != NONE:", "if sa != sb:",
  "THE ROUND'S OWN FIRST-DRAFT BUG: draw the sea as a border (across)"),
 (L, "if sa != sc and sa != NONE and sc != NONE:", "if sa != sc:",
  "the same bug, down"),
 (L, "\t\tif not state.has(nm):\n\t\t\tout.append(NONE)",
     "\t\tif false:\n\t\t\tout.append(NONE)",
  "let the sea take Factions.holder_of's WILD fallback"),
 (L, "out.append(NONE)", "out.append(Factions.WILD)",
  "call the sea wild country instead of no country"),
 # ---- firmness ------------------------------------------------------------
 (L, "const FIRM_MARGIN := 0.1841", "const FIRM_MARGIN := 0.2062",
  "the per-REGION median: the wrong population, which is what the first draft used"),
 (L, "const FIRM_MARGIN := 0.1841", "const FIRM_MARGIN := Factions.HOLD_MARGIN",
  "collapse the two thresholds into one"),
 (L, "\tif ha == Factions.CONTESTED or hb == Factions.CONTESTED:\n\t\treturn 2",
     "\tif ha == Factions.CONTESTED and hb == Factions.CONTESTED:\n\t\treturn 2",
  "only fray a border when BOTH sides are contested"),
 (L, "\tif ha == Factions.CONTESTED or hb == Factions.CONTESTED:\n\t\treturn 2",
     "\tif ha == Factions.CONTESTED or hb == Factions.CONTESTED:\n\t\treturn 1",
  "call a contested border merely uneasy"),
 (L, "var m := minf(Factions.margin_of(state, a), Factions.margin_of(state, b))",
     "var m := maxf(Factions.margin_of(state, a), Factions.margin_of(state, b))",
  "take the FIRMER side of the pair instead of the weaker"),
 (L, "return 1 if m < FIRM_MARGIN else 0", "return 0",
  "never call a border uneasy"),
 (L, "return 1 if m < FIRM_MARGIN else 0", "return 1",
  "never call a border settled"),
 (L, "const FIRM_DASH: Array[float] = [0.0, 10.0, 4.0]",
     "const FIRM_DASH: Array[float] = [10.0, 10.0, 4.0]",
  "break the settled border's line"),
 (L, "const FIRM_WIDTH: Array[float] = [2.4, 2.0, 1.7]",
     "const FIRM_WIDTH: Array[float] = [1.7, 2.0, 2.4]",
  "draw the frayed border heaviest"),
 # ---- walls ---------------------------------------------------------------
 (L, "var key := \"%d|%d\" % [mini(ra, rb), maxi(ra, rb)]", "var key := \"%d|%d\" % [ra, rb]",
  "key the pair by the order the cells were walked in"),
 (L, "arr.append(Vector2i(c0, c1))", "arr.append(Vector2i(c1, c0))",
  "emit a wall's corners descending (the invariant the deleted guard used to hide)"),
 (L, "_add_wall(out, ra, rb, j * w + (i + 1), (j + 1) * w + (i + 1))",
     "_add_wall(out, ra, rb, j * w + i, (j + 1) * w + (i + 1))",
  "put the vertical wall one corner to the west"),
 (L, "_add_wall(out, ra, rc, (j + 1) * w + i, (j + 1) * w + (i + 1))",
     "_add_wall(out, ra, rc, j * w + i, (j + 1) * w + (i + 1))",
  "put the horizontal wall on a diagonal"),
 (L, "var w := nx + 1              ## a grid of nx cells has nx+1 corner columns",
     "var w := nx              ## a grid of nx cells has nx+1 corner columns",
  "forget that a grid of nx cells has nx+1 corner columns"),
 # ---- chains --------------------------------------------------------------
 (L, "if line.size() >= MIN_CHAIN:", "if line.size() >= 2:",
  "let a single cut corner count as a border"),
 (L, "const MIN_CHAIN := 3", "const MIN_CHAIN := 2", "loosen MIN_CHAIN"),
 (L, "cur = s2.y if s2.x == cur else s2.x", "cur = s2.y",
  "always walk a segment forwards, whichever end you arrived at"),
 (L, "\t\tif (at[c] as Array).size() == 1:", "\t\tif (at[c] as Array).size() == 2:",
  "seed the walk from junctions instead of from the open ends"),
 # ---- chaikin -------------------------------------------------------------
 (L, "nextp.append(a.lerp(b, 0.25))", "nextp.append(a.lerp(b, 0.5))",
  "cut the corner to the midpoint: the line leaves its own cells"),
 (L, "\t\tif not closed:\n\t\t\tnextp.append(cur[0])", "\t\tif false:\n\t\t\tnextp.append(cur[0])",
  "stop pinning the first point"),
 (L, "\t\t\tnextp.append(cur[n - 1])", "\t\t\tnextp.append(cur[0])",
  "pin the last point to the first"),
 (L, "var closed := cur[0].is_equal_approx(cur[n - 1])", "var closed := false",
  "never notice a closed loop, so its seam grows a spike"),
 (L, "for _p in range(maxi(0, passes)):", "for _p in range(maxi(1, passes)):",
  "smooth at least once even when asked for none"),
 (L, "const SMOOTH_PASSES := 4", "const SMOOTH_PASSES := 2",
  "two passes: the sagitta that was photographed as a staircase"),
 (L, "const SMOOTH_PASSES := 4", "const SMOOTH_PASSES := 3", "three passes"),
 (L, "const C_BORDER := Color(0.97, 0.94, 0.87, 0.96)",
     "const C_BORDER := Color(0.08, 0.06, 0.06, 0.96)",
  "a near-black border line, which vanishes into a dark forest"),
 (L, "const C_BORDER_BED := Color(0.05, 0.04, 0.04, 0.75)",
     "const C_BORDER_BED := Color(0.95, 0.94, 0.94, 0.75)",
  "a pale bed under a pale line: no contrast anywhere"),
 (L, "const FIRM_WIDTH: Array[float] = [2.4, 2.0, 1.7]",
     "const FIRM_WIDTH: Array[float] = [2.4, 1.5, 0.8]",
  "fade the frayed border away again, so the busiest ground is the hardest to see"),
 (L, "const BED_EXTRA := 1.8", "const BED_EXTRA := 0.0",
  "a bed no wider than the line it carries"),
 (P, "_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR",
     "_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST",
  "the territory wash as a grid of hard blocks"),
 (P, "_view.draw_polyline(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, true)",
     "pass",
  "drop the SOLID border's dark bed"),
 (P, "_dashed(view, MapLayers.C_BORDER_BED, wsz + MapLayers.BED_EXTRA, dash, gap)",
     "pass",
  "drop the DASHED border's dark bed"),
 (P, "_view.draw_polyline(view, MapLayers.C_BORDER, wsz, true)", "pass",
  "draw only the bed and never the line"),
 # ---- the pipeline --------------------------------------------------------
 (L, "\t\tif xa != ya:\n\t\t\treturn xa < ya", "\t\tif xa != ya:\n\t\t\treturn false",
  "drop the name ordering: a border's draw order becomes march order"),
 (L, "\t\treturn String((x as Dictionary)[\"b\"]) < String((y as Dictionary)[\"b\"]))",
     "\t\treturn false)",
  "order only by the first region, so two borders off one province reshuffle"),
 (L, "var sm := chaikin(line as PackedVector2Array, SMOOTH_PASSES)",
     "var sm := chaikin(line as PackedVector2Array, 0)",
  "never smooth the border"),
 (L, "wl.append(cell_to_world(p.x, p.y, nx, nz, origin, size))",
     "wl.append(cell_to_world(p.y, p.x, nx, nz, origin, size))",
  "transpose the border into world space"),
 # ---- colour and tint -----------------------------------------------------
 (L, "\tif not TINT.has(side):\n\t\treturn Color(0, 0, 0, 0)",
     "\tif false:\n\t\treturn Color(0, 0, 0, 0)",
  "A LIBRARY FALLBACK: answer a colour for anything, sea included"),
 (L, "col.a = FILL_ALPHA if col.a > 0.0 else 0.0", "col.a = FILL_ALPHA",
  "paint the transparent sea at the fill alpha"),
 (L, "const FILL_ALPHA := 0.30", "const FILL_ALPHA := 0.90",
  "let the wash replace the bake instead of tinting it"),
 (L, "img.set_pixel(i, j, col)", "img.set_pixel(i, j, Color(0, 0, 0, 0))",
  "paint nothing at all"),
 # ---- the readout ---------------------------------------------------------
 (L, "\tif h == Factions.CONTESTED:\n\t\treturn \"%s — contested\" % Factions.pretty(region)",
     "\tif false:\n\t\treturn \"%s — contested\" % Factions.pretty(region)",
  "report a leader for contested ground"),
 (L, "return \"%s — %s by %s (%.0f%%)\" % [Factions.pretty(region), word, _who(h), m * 100.0]",
     "return \"%s — %s by %s (%.0f%%)\" % [region, word, _who(h), m * 100.0]",
  "NAMES THE GAME SAYS OUT LOUD ARE NOT DATA: shout the region in capitals"),
 (L, "\tif m < FIRM_MARGIN:\n\t\tword = \"held, barely\"", "\tif m < 0.0:\n\t\tword = \"held, barely\"",
  "never hedge a shaky grip"),
 (L, "\tif region.is_empty() or not state.has(region):\n\t\treturn \"\"",
     "\tif region.is_empty():\n\t\treturn \"\"",
  "let the sea claim a holder in the hover line"),
 (L, "\t\tFactions.GOBLINS:\n\t\t\treturn \"goblins\"", "\t\tFactions.GOBLINS:\n\t\t\treturn \"wolves\"",
  "call the goblins wolves"),
 # ---- the panel -----------------------------------------------------------
 (P, "if bool(_on[L_FRONTIER]):", "if true:",
  "draw the frontier whatever the chip says", 4),
 (P, "if bool(_on[L_CROFTS]):", "if true:", "draw the crofts whatever the chip says"),
 (P, "if bool(_on[L_BANDS]):", "if true:", "draw the travellers whatever the chip says"),
 (P, "if _zoom < LABEL_ZOOM:\n\t\treturn\n\tvar cr := _bus(\"crofts\")",
     "if false:\n\t\treturn\n\tvar cr := _bus(\"crofts\")",
  "draw every croft on the unzoomed map"),
 (P, "cd.get(\"pos\", Vector2.ZERO)", "cd.get(\"position\", Vector2.ZERO)",
  "read a croft key that does not exist"),
 (P, "sd.get(\"was_cold\", false)", "false",
  "forget the hearths that went cold and came back"),
 (P, "wf.call(\"where\", b as Dictionary)", "{}",
  "ask the Wayfarers nothing and draw no bands"),
 (P, "if bool(_on[L_ROADS]):", "if true:", "draw the roads whatever the chip says"),
 (P, "if bool(_on[L_KILLS]):", "if true:", "draw the kills whatever the chip says"),
 (P, "_bus(\"roads\")", "_bus(\"road\")", "look up a bus group nothing joins"),
 (P, "b.focus_mode = Control.FOCUS_NONE", "b.focus_mode = Control.FOCUS_ALL",
  "let a layer chip steal keyboard focus from the game"),
 (P, "if key == _pol_key and not force and _tint != null:", "if false:",
  "re-cut the border every quarter second whether or not anything moved"),
 (P, "if f > Carcasses.BONES_AT:", "if f > 0.0:",
  "draw bones as a full kill"),
 (P, "\t\tvar hl := MapLayers.hold_line(ch.get(\"factions\") as Dictionary, rn)",
     "\t\tvar hl := \"\"",
  "A GUTTED CALL: keep the readout's shape, remove the thing it reads"),
 (P, "var si := Seasons.local_index(float(ch.get(\"days\")), here)",
     "var si := Seasons.index(float(ch.get(\"days\")))",
  "read the GLOBAL season instead of the local one -- bc142ff's whole point"),
]


def run():
    r = subprocess.run([GODOT, "--headless", "--path", ".", "--script", SUITE],
                       cwd=ROOT, capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
    return ("ALL GREEN" in out), out


def main():
    ok, out = run()
    if not ok:
        print("BASELINE IS NOT GREEN -- fix that first")
        print(out[-2500:])
        return 2
    print("baseline green\n")
    caught = surv = miss = 0
    for m in M:
        f, old, new, why = m[0], m[1], m[2], m[3]
        want = m[4] if len(m) > 4 else 1
        path = os.path.join(ROOT, f)
        src = open(path).read()
        n = src.count(old)
        if n != want:
            print("MISS   %-52s  (anchor matched %d times, wanted %d)" % (why[:52], n, want))
            miss += 1
            continue
        shutil.copyfile(path, path + ".mutbak")
        open(path, "w").write(src.replace(old, new))
        try:
            green, _ = run()
        finally:
            shutil.copyfile(path + ".mutbak", path)
            os.remove(path + ".mutbak")
        if green:
            print("SURVIVED  %s  [%s]" % (why, f))
            surv += 1
        else:
            print("caught    %s" % why)
            caught += 1
    print("\n%d caught, %d SURVIVED, %d bad anchors, of %d" % (caught, surv, miss, len(M)))
    ok2, _ = run()
    print("restored green: %s" % ok2)
    return 0 if (surv == 0 and miss == 0 and ok2) else 1


sys.exit(main())
