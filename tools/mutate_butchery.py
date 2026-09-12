#!/usr/bin/env python3
"""tools/mutate_butchery.py -- is ButcheryTests worth anything?

A green suite is evidence about the suite, not only about the source. Each
mutation below reintroduces a bug this round either had, could have had, or
was tempted by. Every one must turn ButcheryTests red.

Thirteen of the mutations live in `Carcasses.gd` and `Player.gd` rather than
in `Butchery.gd`: a stub is not the collaborator, and a round that only CALLS
somebody else's method owes assertions to that method's file too.

    python3 tools/mutate_butchery.py
"""
import subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/ButcheryTests.gd"

B = "scripts/Butchery.gd"
C = "scripts/Carcasses.gd"
P = "scripts/Player.gd"

MUTATIONS = [
    # ---- Butchery.gd: the cut ------------------------------------------
    ("cut-kg", B, "const CUT_KG := 6.0", "const CUT_KG := 5.0"),
    ("edge-bonus-off", B, "const EDGE_TIER_BONUS := 0.12", "const EDGE_TIER_BONUS := 0.0"),
    ("edge-through-fallback", B,
     '\tif not Materials.MATS.has(mat_id):\n\t\treturn -1\n\treturn int((Materials.MATS[mat_id] as Dictionary).get("tier", 0))',
     '\tvar m: Dictionary = Materials.get_mat(mat_id)\n\tif m.is_empty():\n\t\treturn -1\n\treturn int(m.get("tier", 0))'),
    # ("edge-empty-string-ok") RETIRED: it named a REDUNDANCY rather than a
    # hole -- `MATS.has("")` is already false -- and the clause is now gone.
    # ---- Butchery.gd: the wall -----------------------------------------
    ("wall-gone", B, "\tif carried >= limit:\n\t\treturn 0.0\n\tvar t := minf(want, left)",
     "\tvar t := minf(want, left)"),
    ("wall-off-by-one", B, "\tif carried >= limit:\n\t\treturn 0.0\n\tvar t := minf(want, left)",
     "\tif carried > limit:\n\t\treturn 0.0\n\tvar t := minf(want, left)"),
    ("wall-no-whole-kg", B,
     "\tvar whole := floorf(t)\n\treturn whole if whole >= 1.0 else t", "\treturn t"),
    ("wall-eats-the-woodchuck", B,
     "\treturn whole if whole >= 1.0 else t", "\treturn whole"),
    ("meat-count-can-be-zero", B,
     "\treturn maxi(1, int(roundf(got)))", "\treturn int(roundf(got))"),
    ("meat-count-floors", B, "\treturn maxi(1, int(roundf(got)))", "\treturn maxi(1, int(floorf(got)))"),
    # ---- Butchery.gd: no meat ------------------------------------------
    ("nomeat-gate-off", B, '\treturn int(harv.get("meat", 0)) > 0', "\treturn true"),
    ("nomeat-gate-ge", B, '\treturn int(harv.get("meat", 0)) > 0', '\treturn int(harv.get("meat", 0)) >= 0'),
    # ---- Butchery.gd: the parts ----------------------------------------
    ("parts-count-the-meat", B, '\t\tif key == "meat":\n\t\t\tcontinue\n', "\n"),
    ("parts-hide-comes-last", B, "\t\tout[key] = int(ceilf(float(ord_n) * f))",
     "\t\tout[key] = int(floorf(float(ord_n) * f))"),
    # ("parts-uncapped") RETIRED: the cap could not bind under the clamp and
    # was masking the clamp's own mutation. Two guards on one path; one left.
    ("parts-unclamped-fraction", B, "\tvar f := clampf(taken / mass, 0.0, 1.0)", "\tvar f := taken / mass"),
    ("meat-count-ceils", B, "\treturn maxi(1, int(roundf(got)))", "\treturn maxi(1, int(ceilf(got)))"),
    ("parts-double-pay", B,
     "\tvar a := parts_owed(harv, mass, before)\n\tvar b := parts_owed(harv, mass, after)",
     "\tvar a: Dictionary = {}\n\tvar b := parts_owed(harv, mass, after)"),
    ("part-weight-all-default", B,
     "\treturn float(PART_KG.get(part, PART_KG_DEFAULT))", "\treturn PART_KG_DEFAULT"),
    ("hide-weighs-nothing", B, '"hide": 4.0,', '"hide": 0.4,'),
    # ---- Butchery.gd: the floors ---------------------------------------
    ("denied-boundary", B, '\t\tif f <= float((Carcasses.GUILDS[g] as Dictionary)["floor"]):',
     "\t\tif f < float((Carcasses.GUILDS[g] as Dictionary)[\"floor\"]):"),
    ("denied-one-floor-for-all", B, '\t\tif f <= float((Carcasses.GUILDS[g] as Dictionary)["floor"]):',
     "\t\tif f <= 0.2:"),
    ("crossed-fires-every-cut", B,
     "\tvar was := denied(mass, before)\n\tvar now := denied(mass, after)",
     "\tvar was: Array = []\n\tvar now := denied(mass, after)"),
    ("appetite-names-the-smallest", B,
     '\t\tif f > float((Carcasses.GUILDS[g] as Dictionary)["floor"]):\n\t\t\tbest = g',
     '\t\tif f > float((Carcasses.GUILDS[g] as Dictionary)["floor"]) and best < 0:\n\t\t\tbest = g'),
    # ---- Butchery.gd: the names ----------------------------------------
    ("no-venison", B, 'const MEAT_OVERRIDE := {"whitetail": "Venison"}', "const MEAT_OVERRIDE := {}"),
    ("name-first-word", B, '\treturn "%s Meat" % String(parts[parts.size() - 1])',
     '\treturn "%s Meat" % String(parts[0])'),
    # ("name-keeps-the-article") RETIRED: under the LAST-word rule the article
    # strip was dead code. The sweep found it; the code is deleted.
    # ---- Butchery.gd: the prompt ---------------------------------------
    ("prompt-no-bones-branch", B,
     '\tif Carcasses.stage_of(rec) >= Carcasses.STAGE_BONES:\n\t\treturn "Bones. There is nothing on it to take"\n', "\n"),
    ("prompt-no-nomeat-branch", B,
     '\tif not butcherable(harv):\n\t\treturn "There is nothing on a %s a knife is for" % nm.to_lower()\n', "\n"),
    ("prompt-no-edge-branch", B,
     '\tif edge == "":\n\t\treturn "Nothing on you will open it -- it wants an edge"\n', "\n"),
    ("prompt-no-full-branch", B,
     '\tif carried >= limit:\n\t\treturn "Your back is full -- %.0f / %.0f" % [carried, limit]\n', "\n"),
    ("prompt-shouts-the-name", B, "% [nm.to_lower(), left, appetite(mass, left)]",
     "% [nm, left, appetite(mass, left)]"),
    # ---- Carcasses.gd: the collaborator --------------------------------
    ("scent-flat", C, "const OPEN_SCENT := 1.6", "const OPEN_SCENT := 1.0"),
    ("scent-boundary", C, "\treturn OPEN_SCENT if left / mass <= OPENED_AT else 1.0",
     "\treturn OPEN_SCENT if left / mass < OPENED_AT else 1.0"),
    ("scent-wrong-stage", C, "\treturn OPEN_SCENT if left / mass <= OPENED_AT else 1.0",
     "\treturn OPEN_SCENT if left / mass <= PICKED_AT else 1.0"),
    ("scent-massless-smells", C, "\tif mass <= 0.0:\n\t\treturn 1.0\n\treturn OPEN_SCENT",
     "\tif mass <= 0.0:\n\t\treturn OPEN_SCENT\n\treturn OPEN_SCENT"),
    ("find-gain-ignores-open", C, " * draw_of(mass) * open_mult(mass, left)", " * draw_of(mass)"),
    ("find-gain-fed-the-mass", C, 'find_gain(g, mass, float(rec.get("left", 0.0)), hour, sky, season)',
     "find_gain(g, mass, mass, hour, sky, season)"),
    # ---- Player.gd: the call site --------------------------------------
    ("player-nomeat-gate-off", P,
     '\tif not Butchery.butcherable(harv0):\n\t\t_add_log_msg("There is nothing on a %s a knife is for"\n\t\t\t% String(rec.get("nm", "beast")).to_lower(), Color(0.80, 0.80, 0.80))\n\t\treturn\n', "\n"),
    ("player-cut-is-a-literal", P,
     "\tvar want := Butchery.take_for(before, Butchery.cut_kg(edge), carried, limit)",
     "\tvar want := Butchery.take_for(before, 6.0, carried, limit)"),
    ("player-ignores-the-wall", P,
     "\tvar want := Butchery.take_for(before, Butchery.cut_kg(edge), carried, limit)",
     "\tvar want := Butchery.cut_kg(edge)"),
    ("player-no-wet", P,
     "\tif warmth_survival():\n\t\texposure.wet = minf(1.0, exposure.wet + Butchery.CUT_WET)\n", "\n"),
    ("player-wet-ungated", P,
     "\tif warmth_survival():\n\t\texposure.wet = minf(1.0, exposure.wet + Butchery.CUT_WET)",
     "\texposure.wet = minf(1.0, exposure.wet + Butchery.CUT_WET)"),
    ("player-no-cooldown", P, "\t_cut_cd = Butchery.CUT_SECONDS\n", "\n"),
    ("player-no-stamina", P, "\tstamina = maxf(0.0, stamina - Butchery.CUT_STAMINA)\n", "\n"),
    ("player-raw-kg-in-the-pack", P, "\tvar kg := Butchery.meat_count(got)", "\tvar kg := int(got)"),
    ("player-parts-off-the-whole", P,
     "Butchery.parts_due(harv, mass, mass - before, mass - after)",
     "Butchery.parts_due(harv, mass, 0.0, mass)"),
    ("player-everything-is-an-edge", P,
     '\t\tif Butchery.edge_tier(m) >= 0:\n\t\t\treturn m', "\t\treturn m"),
    ("player-e-does-not-reach-it", P,
     '\t\t\t\telif menu_open == "" and kd_phase == "" and not _carc_target.is_empty():\n\t\t\t\t\t_butcher_cut()   ## [butchery]\n', "\n"),
    ("player-prompt-blind-to-the-row", P,
     "\t\t\tpickup_prompt.text = Butchery.prompt_for(_carc_target, chv, _edge_mat(),",
     "\t\t\tpickup_prompt.text = Butchery.prompt_for(_carc_target, {}, _edge_mat(),"),
    ("player-no-harvest-call", P,
     '\tvar got := carc.harvest_at(rec["at"] as Vector3, 1.0, want)',
     "\tvar got := want"),
]


def run_suite():
    r = subprocess.run([GODOT, "--headless", "--path", ".", "--script", SUITE],
                       cwd=ROOT, capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    return ("ALL GREEN" in out), out


def main():
    caught, survived, bad = [], [], []
    base_ok, base_out = run_suite()
    if not base_ok:
        print("BASELINE IS NOT GREEN -- fix that first")
        print(base_out[-3000:])
        return 1
    print("baseline green")
    for name, path, old, new in MUTATIONS:
        full = os.path.join(ROOT, path)
        src = open(full).read()
        n = src.count(old)
        if n != 1:
            bad.append("%s (anchor matched %d times in %s)" % (name, n, path))
            print("  BAD ANCHOR  %s: %d matches" % (name, n))
            continue
        open(full, "w").write(src.replace(old, new, 1))
        try:
            green, out = run_suite()
        finally:
            open(full, "w").write(src)
        if green:
            survived.append(name)
            print("  SURVIVED    %s" % name)
        else:
            caught.append(name)
            print("  caught      %s" % name)
    print("")
    print("%d caught, %d SURVIVED, %d bad anchors, of %d"
          % (len(caught), len(survived), len(bad), len(MUTATIONS)))
    for s in survived:
        print("  survivor: %s" % s)
    for b in bad:
        print("  bad anchor: %s" % b)
    return 0 if (not survived and not bad) else 1


if __name__ == "__main__":
    sys.exit(main())
