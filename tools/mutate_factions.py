#!/usr/bin/env python3
"""tools/mutate_factions.py -- a green suite is evidence about the SUITE.

Reintroduces, one at a time, every bug this round could plausibly have and
demands the suite go red for each. A mutation that survives is naming a test
that does not exist -- or dead code, or a redundancy, and the round has to say
which.

    python3 tools/mutate_factions.py            # the whole sweep
    python3 tools/mutate_factions.py --only 12  # one, by index

Fourteen of the mutations below live in Chronicle.gd, Crofts.gd and
WildlifeDirector.gd rather than in Factions.gd. A STUB IS NOT THE
COLLABORATOR, and a call site can be deleted by somebody else tomorrow.
"""
import subprocess, sys, os, shutil, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
FAC = "scripts/Factions.gd"
CHR = "scripts/Chronicle.gd"
CRO = "scripts/Crofts.gd"
WLD = "scripts/WildlifeDirector.gd"

FT = ["FactionTests"]
FTC = ["FactionTests", "CroftTests"]

# (file, old, new, label, suites)
M = [
 (FAC, "const SEAT_HALF := 4.0", "const SEAT_HALF := 12.0", "seat-half-wide", FT),
 (FAC, "const REACH_DECAY := 0.45", "const REACH_DECAY := 0.98", "reach-never-fades", FT),
 (FAC, "const CLAIMED := 0.75", "const CLAIMED := 0.20", "nothing-is-claimed", FT),
 (FAC, "const HOLD_MARGIN := 0.06", "const HOLD_MARGIN := 0.0", "no-contested-state", FT),
 (FAC, "const PUSH_HALFLIFE_DAYS := 14.0", "const PUSH_HALFLIFE_DAYS := 1.0", "world-forgets-overnight", FT),
 (FAC, "const HOLD_HALFLIFE_DAYS := 40.0", "const HOLD_HALFLIFE_DAYS := 2.0", "border-snaps-back", FT),
 (FAC, "const PUSH_GAIN := 0.04", "const PUSH_GAIN := 0.0", "events-move-nothing", FT),
 (FAC, "const SPILL := 0.06", "const SPILL := 0.0", "no-frontier-spill", FT),
 (FAC, "const NEUTRAL_SHARE := 0.25", "const NEUTRAL_SHARE := 0.0", "neutral-is-nothing", FT),
 (FAC, "const PRESSURE_SPAN := 1.0", "const PRESSURE_SPAN := 0.0", "territory-means-nothing", FTC),
 (FAC, "const SEA_U := 0.999", "const SEA_U := 9.0", "the-sea-is-ground", FT),
 (FAC, "const MULT_MIN := 0.15", "const MULT_MIN := 0.0", "local-extinction", FT),
 (FAC, "const MEN_FLOOR := 0.60", "const MEN_FLOOR := 0.0", "no-wall-anywhere", FT),
 (FAC, "const MEN_FLOOR := 0.60", "const MEN_FLOOR := 0.99", "nothing-can-be-lost", FT),
 (FAC, "out[rn] = float(out.get(rn, 0.0)) + 1.0 + float(int(pd.get(\"rank\", 0)))",
       "out[rn] = float(out.get(rn, 0.0)) + 1.0", "rank-ignored", FT),
 (FAC, "out[rn] = float(out.get(rn, 0.0)) + 1.0 + float(int(pd.get(\"rank\", 0)))",
       "out[rn] = float(out.get(rn, 0.0)) + float(int(pd.get(\"rank\", 0)))", "a-hamlet-is-worth-nothing", FT),
 (FAC, "\tif seat > 0.0:\n\t\treturn false", "\tif seat > -1.0:\n\t\treturn false", "nothing-is-ever-sea", FT),
 (FAC, "if maxf(ap.distance_to(cp), bp.distance_to(cp)) < dab:",
       "if maxf(ap.distance_to(cp), bp.distance_to(cp)) <= dab:", "adjacency-off-by-a-tie", FT),
 (FAC, "if maxf(ap.distance_to(cp), bp.distance_to(cp)) < dab:",
       "if minf(ap.distance_to(cp), bp.distance_to(cp)) < dab:", "adjacency-min-not-max", FT),
 (FAC, "dist[vn] = int(dist[u]) + 1", "dist[vn] = int(dist[u]) + 2", "hops-double-counted", FT),
 (FAC, "\treturn seat / (seat + SEAT_HALF)", "\treturn minf(1.0, seat / 8.0)", "grip-is-linear", FT),
 (FAC, "GOBLINS: rest * CLAIMED * deep,\n\t\t\tWOLVES: rest * CLAIMED * (1.0 - deep),",
       "GOBLINS: rest * CLAIMED * (1.0 - deep),\n\t\t\tWOLVES: rest * CLAIMED * deep,", "predators-swapped", FT),
 (FAC, "WILD: rest * (1.0 - CLAIMED),", "WILD: 0.0,", "no-empty-country", FT),
 (FAC, "\t\tif who.is_empty():\n\t\t\tcontinue\n\t\tout[who] = float(out[who]) + float(b[t])",
       "\t\tif who.is_empty() or who == LAWLESS:\n\t\t\tcontinue\n\t\tout[who] = float(out[who]) + float(b[t])",
       "disorder-costs-nothing", FT),
 (FAC, "out[who] = float(out[who]) + float(b[t])", "out[who] = float(out[who]) - float(b[t])", "push-sign-flipped", FT),
 # ---- KNOWN, EXPLAINED SURVIVOR. Leave it in the list; do not "fix" it.
 # Removing the membership half of this guard makes `note` read a missing
 # Dictionary key, which Godot reports as a SCRIPT ERROR, aborts the function,
 # and RETURNS THE SAME `false` the guard returns. Measured directly on
 # 2026-09-12: `real=true missing=false` either way, the caller carries on, and
 # no state anywhere differs. The guard is therefore real -- it is what stops a
 # script error per coastal event, since `region_at` answers over all eighteen
 # regions while `pushes` has bags for the seventeen that are land -- but it is
 # not observable from inside the game, so no assertion can bite on it. The
 # suite instead proves the case is REACHABLE (a point in the open Gulf really
 # does resolve to a region with no bag) and that `note` reports the drop.
 (FAC, "\tif region.is_empty() or not pushes.has(region):\n\t\treturn false",
       "\tif region.is_empty():\n\t\treturn false", "note-into-nowhere-EXPECTED", FT),
 (FAC, "\tfor f in add:\n\t\tbag[f] = float(bag.get(f, 0.0)) + float(add[f])\n\treturn true",
       "\tfor f in add:\n\t\tbag[f] = float(bag.get(f, 0.0)) + float(add[f])\n\treturn false",
       "note-never-admits-landing", FT),
 (FAC, "\t\tbag[f] = float(bag.get(f, 0.0)) + float(add[f])", "\t\tbag[f] = float(add[f])", "no-memory-only-today", FT),
 (FAC, "\tvar pk := pow(0.5, days / PUSH_HALFLIFE_DAYS)", "\tvar pk := 1.0", "world-never-stops-shouting", FT),
 (FAC, "\tvar hk := 1.0 - pow(0.5, days / HOLD_HALFLIFE_DAYS)", "\tvar hk := 0.0", "no-spring-at-all", FT),
 (FAC, "\t\tvar g := PUSH_GAIN * days / (1.0 + float(seats.get(nm, 0.0)) / SEAT_HALF)",
       "\t\tvar g := PUSH_GAIN * days", "cities-as-fragile-as-outposts", FT),
 (FAC, "- g * lawless)", "+ g * lawless)", "disorder-helps-the-men", FT),
 (FAC, "\t\t\t\tvar qh: Dictionary = before.get(String(q), {})",
       "\t\t\t\tvar qh: Dictionary = state.get(String(q), {})", "spill-reads-live-state", FT),
 (FAC, "\t\t\tvar take := SPILL * days * press * float(h2[WILD])",
       "\t\t\tvar take := SPILL * days * press", "spill-ignores-empty-ground", FT),
 (FAC, "\t\tfor f in CLAIMANTS:\n\t\t\th3[f] = float(h3[f]) / total",
       "\t\tfor f in CLAIMANTS:\n\t\t\th3[f] = float(h3[f])", "ground-does-not-add-up", FT),
 (FAC, "\t\tvar floor_men := MEN_FLOOR * men_anchor(float(seats.get(nm, 0.0)))",
       "\t\tvar floor_men := MEN_FLOOR * 0.0", "floor-detached-from-seats", FT),
 (FAC, "\tif first - second < HOLD_MARGIN:\n\t\treturn CONTESTED", "\tif false:\n\t\treturn CONTESTED",
       "contested-unreachable", FT),
 (FAC, "\treturn maxf(0.0, first - second)", "\treturn maxf(0.0, first)", "margin-is-the-lead-not-the-gap", FT),
 (FAC, "\t\t\tif bn <= an:\n\t\t\t\tcontinue", "\t\t\tif false:\n\t\t\t\tcontinue", "frontier-named-twice", FT),
 (FAC, "\t\t\tif ha == hb:\n\t\t\t\tcontinue", "\t\t\tif false:\n\t\t\t\tcontinue", "everything-is-a-frontier", FT),
 (FAC, "\t\tif d < float(rd.get(\"r\", 500.0)) and d < bd:", "\t\tif false:", "region-circles-ignored", FT),
 (FAC, "\treturn best if not best.is_empty() else near", "\treturn best", "points-outside-a-circle-are-nowhere", FT),
 (FAC, "\tif who.is_empty() or who == LAWLESS:\n\t\treturn 0.0",
       "\tif who.is_empty():\n\t\treturn 0.0", "disorder-gets-territory", FTC),
 (FAC, "\treturn PRESSURE_SPAN * (float(h.get(who, 0.0)) - NEUTRAL_SHARE)",
       "\treturn PRESSURE_SPAN * float(h.get(who, 0.0))", "pressure-term-never-negative", FT),
 (FAC, "\tif HUNTER_ARCH.has(arch):\n\t\treturn BAND_HUNTER", "\tif false:\n\t\treturn BAND_HUNTER",
       "no-hunters-at-all", FT),
 (FAC, "const SCAV_ARCH: Array[String] = [\"SCAVENGER\"]", "const SCAV_ARCH: Array[String] = [\"STALKER\"]",
       "scavengers-misclassified", FT),
 (FAC, "\tif hold.is_empty():\n\t\treturn 1.0", "\tif false:\n\t\treturn 1.0", "no-chronicle-changes-spawning", FT),
 (FAC, "\treturn clampf(m, MULT_MIN, MULT_MAX)", "\treturn m", "spawn-weight-unclamped", FT),
 (FAC, "\t\tm += (float(hold.get(f, 0.0)) - NEUTRAL_SHARE) * float(row.get(f, 0.0))",
       "\t\tm += float(hold.get(f, 0.0)) * float(row.get(f, 0.0))", "neutral-ground-is-not-1.0", FT),
 (FAC, "\tvar parts := region.to_lower().split(\" \")",
       "\tvar parts := PackedStringArray([region.to_lower()])",
       "THE-LIVE-BUG-place-names-muttered", FT),
 (FAC, "\t\tout.append(_cap_hyphenated(w))", "\t\tout.append(w)", "no-capitals-at-all", FT),
 (FAC, "\tvar bits := w.split(\"-\")", "\tvar bits := PackedStringArray([w])", "hyphen-swallowed", FT),
 (FAC, "\t\tif i > 0 and SMALL_WORDS.has(w):", "\t\tif false:", "Gulf-Of-Maine", FT),
 (FAC, "\tvar now := holder_of(state, region)\n\tif now == was:\n\t\treturn \"\"",
       "\tvar now := holder_of(state, region)\n\tif false:\n\t\treturn \"\"", "silence-has-a-sentence", FT),
 (FAC, "\t\tif who != LAWLESS and not CLAIMANTS.has(who):", "\t\tif false:", "validator-ignores-claimants", FT),
 (FAC, "\t\t\tif not (adj.get(bn, []) as Array).has(an):", "\t\t\tif false:", "validator-ignores-symmetry", FT),
 (FAC, "\t\t\tif not row.has(f):", "\t\t\tif false:", "validator-ignores-unpriced-bands", FT),
 (FAC, "\t\tvar seen := hops_from(String(land[0]), adj)\n\t\tfor a in land:\n\t\t\tif not seen.has(String(a)):",
       "\t\tvar seen := hops_from(String(land[0]), adj)\n\t\tfor a in land:\n\t\t\tif false:",
       "validator-ignores-islands", FT),
 (FAC, "\tif total <= 0.0:\n\t\tout.append(\"not one seat on the whole map\")",
       "\tif false:\n\t\tout.append(\"not one seat on the whole map\")", "validator-ignores-empty-map", FT),
 (FAC, "\t\treturn {MEN: 0.0, GOBLINS: 0.0, WOLVES: 0.0, WILD: 1.0}",
       "\t\treturn {MEN: 1.0, GOBLINS: 0.0, WOLVES: 0.0, WILD: 0.0}", "nowhere-belongs-to-the-men", FT),
 # ---- collaborators ----
 (CHR, "\t_step_factions(t)\n", "\t\n", "chronicle-never-steps-the-border", FT),
 (CHR, "\tFactions.note(fpush, Factions.region_at(Vector3(epos.x, 0.0, epos.y), REGION_ROSTER), b)",
       "\tpass", "outcomes-never-reach-a-region", FT),
 (CHR, "\tp += Factions.pressure_bonus(factions, Factions.region_at(pos, REGION_ROSTER), tag)",
       "\tpass", "pressure_at-forgets-where-you-are", FTC),
 (CHR, "\tp += Factions.pressure_bonus(factions, Factions.region_at(pos, REGION_ROSTER), tag)",
       "\tp += Factions.pressure_bonus(factions, \"CASCO BAY\", tag)", "pressure_at-always-asks-casco-bay", FTC),
 (CHR, "\t_rebuild_factions()\n\t_booted = true", "\t_booted = true", "boot-builds-no-map", FT),
 (CHR, "\t\t\"factions\": _fdup(factions),", "", "save-drops-the-frontier", FT),
 (CHR, "\t\t\"fpush\": _fdup(fpush),", "", "save-drops-the-pressure", FT),
 (CHR, "\t\tdeposit_rumour(seat, {\"text\": line, \"day\": t, \"from\": seat, \"kind\": \"frontier\"})",
       "\t\tpass", "the-border-has-no-voice", FT),
 (CHR, "\t\tif rank > br or (rank == br and nm < best):", "\t\tif false:", "no-chief-seat-to-speak", FT),
 (CHR, "\tFactions.step(factions, fpush, _fanch, _fadj, _fseats, STEP_HOURS / 24.0)",
       "\tFactions.step(factions, fpush, _fanch, _fadj, _fseats, 0.0)", "step-of-no-time", FT),
 (CHR, "\treturn Factions.region_at(Vector3(pos.x, 0.0, pos.y), REGION_ROSTER)",
       "\treturn \"\"", "no-place-has-a-region", FT),
 (CRO, "const ALARM_TAGS: Array = [\"goblins\", \"wolves\", \"bandits\", \"unrest\"]",
       "const ALARM_TAGS: Array = [\"raid\", \"beast\", \"wolf\", \"war\"]", "THE-ORIGINAL-BUG-dead-alarm-tags", FTC),
 (CRO, "const SHUT_PRESSURE := 0.90", "const SHUT_PRESSURE := 0.55", "doors-barred-four-days-in-ten", FTC),
 (WLD, "\t\tw *= Factions.spawn_mult(k, ground)", "\t\tpass", "ground-does-not-reach-the-spawner", FT),
 (WLD, "\tvar ground := _ground()", "\tvar ground := {}", "GUTTED-CALL-ground-hardcoded", FT),
 (WLD, "\treturn Factions.hold_of(ch.factions, rn)", "\treturn {}", "_ground-always-neutral", FT),
]


def run_suite(name):
    r = subprocess.run([GODOT, "--headless", "--path", ".", "--script",
                        "res://tests/%s.gd" % name], cwd=ROOT,
                       capture_output=True, text=True, timeout=900)
    out = r.stdout
    if "ALL GREEN" in out:
        return True
    for line in out.split("\n"):
        if "passed," in line and "0 failed" in line:
            return True
    return False


def main():
    only = None
    if "--only" in sys.argv:
        only = int(sys.argv[sys.argv.index("--only") + 1])
    caught, survived, bad = [], [], []
    for i, (path, old, new, label, suites) in enumerate(M):
        if only is not None and i != only:
            continue
        full = os.path.join(ROOT, path)
        src = open(full, encoding="utf-8").read()
        n = src.count(old)
        if n != 1:
            bad.append("%d %s (%s matched %d times)" % (i, label, path, n))
            print("  ?? %3d %-42s BAD ANCHOR in %s (%d matches)" % (i, label, path, n), flush=True)
            continue
        open(full, "w", encoding="utf-8").write(src.replace(old, new))
        try:
            green = True
            for s in suites:
                if not run_suite(s):
                    green = False
                    break
        finally:
            open(full, "w", encoding="utf-8").write(src)
        if green:
            survived.append("%d %s" % (i, label))
            print("  !! %3d %-42s SURVIVED  (%s)" % (i, label, path), flush=True)
        else:
            caught.append(label)
            print("  ok %3d %-42s caught" % (i, label), flush=True)
    print("")
    print("caught %d / %d,  survived %d,  bad anchors %d"
          % (len(caught), len(M) if only is None else 1, len(survived), len(bad)))
    for s in survived:
        print("  SURVIVED: %s" % s)
    for b in bad:
        print("  BAD ANCHOR: %s" % b)


if __name__ == "__main__":
    main()
