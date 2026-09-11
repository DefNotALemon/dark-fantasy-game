#!/usr/bin/env python3
"""tools/mutate_garments.py -- does GarmentTests actually hold Garments up?

A green suite is evidence about the SUITE, not only about the source. This
reintroduces, one at a time, every defect the design could plausibly have
had, and demands the suite go red for each. A mutation that SURVIVES names
a test that does not exist -- or dead code, or a redundancy, and the honest
answer to each of those three is different.

Sixteen of the mutations below live in `scripts/Exposure.gd` and
`scripts/Player.gd` rather than in `Garments.gd`, because a suite that only
mutates its own file proves nothing about whether anybody CALLS it. A
method nobody calls is not a feature.

    python3 tools/mutate_garments.py            # the whole sweep
    python3 tools/mutate_garments.py --list     # just name them

Nothing is left on disk: every file is restored from memory after each run,
and again on any exception or interrupt.
"""

import io
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/GarmentTests.gd"

G = "scripts/Garments.gd"
E = "scripts/Exposure.gd"
P = "scripts/Player.gd"

# (file, exact text to find, what to put there instead, what defect that is)
MUTATIONS = [
    # ---- the tables -------------------------------------------------------
    (G, '\t"chest": 0.38,\n\t"arms": 0.16,\n\t"pants": 0.22,\n\t"shoes": 0.10,',
        '\t"chest": 0.10,\n\t"arms": 0.16,\n\t"pants": 0.22,\n\t"shoes": 0.38,',
        "boots cover more of a man than his chest does"),
    (G, '\t"cold_iron": 1.70,', '\t"cold_iron": 1.00,',
        "cold iron is no colder to wear than steel"),
    (G, '\t"dragonsteel": -0.30,', '\t"dragonsteel": 0.30,',
        "dragonsteel conducts heat away instead of giving it back"),
    (G, '\t"voidsteel": -0.10,', '\t"voidsteel": 1.00,',
        "voidsteel carries Soulfire and is priced as plain metal"),
    (G, '\t"meteoric": 0.35,', '\t"meteoric": 1.00,',
        "meteoric carries Ember and is priced as plain metal"),
    (G, '\t"mithril": 0.85,', '\t"mithril": 1.15,',
        "mithril conducts more than plain metal"),
    (G, '\t"adamant": 1.15,', '\t"adamant": 0.85,',
        "adamant runs cool despite carrying Quake"),
    (G, '\t"bronze": 1.00,', '\t"bronze": 1.30,',
        "a metal with no element is not plain metal"),
    (G, 'const WARM_ELEMENTS: Array[String] = ["Ember", "Dragonfire", "Soulfire"]',
        'const WARM_ELEMENTS: Array[String] = ["Ember", "Dragonfire"]',
        "Soulfire drops out of the warm elements"),
    (G, 'const COLD_ELEMENTS: Array[String] = ["Frost"]',
        'const COLD_ELEMENTS: Array[String] = []',
        "nothing in the game is cold to the touch any more"),

    # ---- the four numbers -------------------------------------------------
    (G, "const STILL_C := 1.2", "const STILL_C := 0.0",
        "being covered is worth nothing in still air"),
    (G, "const STILL_C := 1.2", "const STILL_C := 2.6",
        "being covered is worth twice what it was measured at"),
    (G, "const WIND_BREAK_C := 2.2", "const WIND_BREAK_C := 0.0",
        "plate does not break wind"),
    (G, "const WIND_BREAK_C := 2.2", "const WIND_BREAK_C := 3.6",
        "a harness hands back more of the gale than the gale took"),
    (G, "const CONDUCT_FRACTION := 0.17", "const CONDUCT_FRACTION := 0.0",
        "metal does not conduct at all"),
    (G, "const CONDUCT_FRACTION := 0.17", "const CONDUCT_FRACTION := 0.30",
        "metal conducts nearly twice what was measured"),
    (G, "const WET_CONDUCT_MULT := 1.6", "const WET_CONDUCT_MULT := 1.0",
        "wet metal is no worse than dry metal"),
    (G, "const DRY_MULT_FULL := 0.6", "const DRY_MULT_FULL := 1.0",
        "a harness does not slow drying"),
    (G, "const TIE_EPS := 0.0005", "const TIE_EPS := 5.0",
        "every metal is a tie, so dress() only ever answers with armour"),

    # ---- what is on the body ----------------------------------------------
    (G, "\t\"pants\": 0.22,", "\t\"pants\": 0.40,",
        "the cover weights no longer add up to a whole body"),
    (G, "const COVER_TOTAL := 1.0", "const COVER_TOTAL := 2.0",
        "a whole body is redefined as two of them"),
    (G, '\t\tif String(worn[slot]) == "":\n\t\t\tcontinue',
        '\t\tif String(worn[slot]) == "NEVER":\n\t\t\tcontinue',
        "an empty slot counts as covered"),
    (G, '\t\tif COVER.has(slot) and String(worn[slot]) != "":',
        '\t\tif String(worn[slot]) != "":',
        "a sword counts as a piece of clothing"),
    (G, "\treturn num / den", "\treturn num",
        "conduction is a sum, so five pieces conduct five times as hard"),
    (G, "\t\tnum += w * float(CONDUCT.get(m, CONDUCT_BARE))",
        "\t\tnum += float(CONDUCT.get(m, CONDUCT_BARE))",
        "conduction is not weighted by coverage, so one boot decides the set"),
    (G, "\t\tnum += w * float(CONDUCT.get(m, CONDUCT_BARE))",
        "\t\tnum += w * float(CONDUCT.get(m, 0.0))",
        "a metal nobody has heard of does not conduct at all"),
    (G, "\t\tp += Materials.armor_piece_protect(m)",
        "\t\tp = Materials.armor_piece_protect(m)",
        "only the last piece of armour protects you"),

    # ---- degrees ----------------------------------------------------------
    (G, "\treturn maxf(0.0, Exposure.WARMTH_NEUTRAL_C - still_air_c)",
        "\treturn Exposure.WARMTH_NEUTRAL_C - still_air_c",
        "the gradient goes negative above neutral, so metal matters in summer"),
    (G, "\treturn maxf(0.0, Exposure.WARMTH_NEUTRAL_C - still_air_c)",
        "\treturn maxf(0.0, Exposure.WARMTH_LOW - still_air_c)",
        "the gradient is measured from the shivering line, not from neutral"),
    (G, "\treturn cover(worn) * (STILL_C + WIND_BREAK_C * clampf(wind, 0.0, 1.0))",
        "\treturn STILL_C + WIND_BREAK_C * clampf(wind, 0.0, 1.0)",
        "one boot breaks as much wind as a whole harness"),
    (G, "\treturn cover(worn) * (STILL_C + WIND_BREAK_C * clampf(wind, 0.0, 1.0))",
        "\treturn cover(worn) * STILL_C",
        "the windbreak does not care how hard it is blowing"),
    (G, "\tvar loss := conduct(worn) * CONDUCT_FRACTION * gradient_c(still_air_c) * cv",
        "\tvar loss := conduct(worn) * CONDUCT_FRACTION * gradient_c(still_air_c)",
        "conduction ignores how much of you is covered"),
    (G, "\treturn loss * (1.0 + (WET_CONDUCT_MULT - 1.0) * clampf(wet, 0.0, 1.0))",
        "\treturn loss",
        "soaking a harness costs nothing"),
    (G, "\treturn wind_break(worn, wind) - conduct_c(worn, still_air_c, wet)",
        "\treturn wind_break(worn, wind) + conduct_c(worn, still_air_c, wet)",
        "the conduction sign is flipped and cold iron is the warmest set there is"),
    (G, "\treturn wind_break(worn, wind) - conduct_c(worn, still_air_c, wet)",
        "\treturn wind_break(worn, wind)",
        "the whole conduction term is dropped and armour is a pure gift"),
    (G, "\tif worn.is_empty():\n\t\treturn 0.0",
        "\tif worn.is_empty():\n\t\treturn 1.0",
        "a naked man is paid a degree for it"),
    (G, "\treturn lerpf(1.0, DRY_MULT_FULL, cover(worn))", "\treturn 1.0",
        "drying does not know what you are wearing"),

    # ---- dress ------------------------------------------------------------
    (G, "\t\telif s > float(score[slot]) + TIE_EPS:",
        "\t\telif s < float(score[slot]) - TIE_EPS:",
        "dress() hands you the COLDEST thing in the pack"),
    (G, "\t\telif s >= float(score[slot]) - TIE_EPS and p > float(prot[slot]):",
        "\t\telif s >= float(score[slot]) - TIE_EPS and p < float(prot[slot]):",
        "a tie goes to the flimsier metal"),
    (G, '\t\tvar m := String(it.get("material", ""))\n\t\tif m == "" or not COVER.has(slot):',
        '\t\tvar m := String(it.get("material", ""))\n\t\tif m == "":',
        "dress() puts your sword on"),

    # ---- the reconciliation -----------------------------------------------
    (G, "\tif wind_break_c >= absf(Exposure.WIND_C):",
        "\tif wind_break_c >= 99.0:",
        "the windbreak guard can never fire"),
    (G, "\t\tif WARM_ELEMENTS.has(el) and c >= CONDUCT_BARE:",
        "\t\tif WARM_ELEMENTS.has(el) and c >= 99.0:",
        "a warm metal may be priced as cold without complaint"),
    (G, "\t\tif COLD_ELEMENTS.has(el) and c <= CONDUCT_BARE:",
        "\t\tif COLD_ELEMENTS.has(el) and c <= -99.0:",
        "a cold metal may be priced as warm without complaint"),

    # ---- Exposure: the call sites -----------------------------------------
    (E, "\tf += garment_c(e, wet_v)", "\tf += 0.0 * garment_c(e, wet_v)",
        "Exposure stops adding the garment term to what you feel"),
    (E, '\tdry *= Garments.dry_mult(e.get("worn", {}))',
        '\tdry *= 1.0',
        "Exposure stops slowing drying for a harness"),
    (E, '\treturn ambient_c(e) - wind_c(float(e.get("wind", 0.0)), is_sheltered(e))',
        '\treturn ambient_c(e) + wind_c(float(e.get("wind", 0.0)), is_sheltered(e))',
        "the still-air temperature has the wind added twice"),
    (E, '\treturn ambient_c(e) - wind_c(float(e.get("wind", 0.0)), is_sheltered(e))',
        '\treturn ambient_c(e)',
        "the harness is charged for conducting away the draught it is stopping"),
    (E, '\treturn Garments.garment_c(worn, still_air_c(e), clampf(wet_v, 0.0, 1.0), wind)',
        '\treturn Garments.garment_c(worn, still_air_c(e), 0.0, wind)',
        "Exposure never tells Garments that you are wet"),
    (E, '\tvar wind := 0.0 if sheltered else clampf(float(e.get("wind", 0.0)), 0.0, 1.0)\n\tvar worn: Dictionary = e.get("worn", {})',
        '\tvar wind := clampf(float(e.get("wind", 0.0)), 0.0, 1.0)\n\tvar worn: Dictionary = e.get("worn", {})',
        "a harness breaks wind that a roof has already stopped"),
    (E, "\tif not is_nan(local):", "\tif is_nan(local):",
        "the local season temperature is used only when it was not given"),
    (E, "\t\tc = local", "\t\tc += local",
        "the local answer is added to the shared table instead of replacing it"),
    (E, '\t"base_c": NAN,', '\t"base_c": 0.0,',
        "every environment claims a local answer of zero degrees"),

    # ---- Player: the wiring -----------------------------------------------
    (P, '\t\t"worn": worn_metals(),', '\t\t"worn": {},',
        "the player publishes an empty wardrobe, so nothing he wears matters"),
    (P, '\t\t"base_c": Seasons.base_c_at(day, global_position),',
        '\t\t"base_c": NAN,',
        "Seasons.base_c_at loses its only caller again"),
    (P, "\t_garment_note()\n\t_refresh_inventory_ui()", "\t_refresh_inventory_ui()",
        "putting a set on says nothing about what it costs tonight"),
    (P, '\t\tif m != "":\n\t\t\tw[slot] = m', '\t\tif true:\n\t\t\tw[slot] = m',
        "empty slots are published as worn"),
    (G, "gradient_c(still_air_c) <= 0.0:", "gradient_c(still_air_c) <= -99.0:",
        "the verdict oversells a summer evening it cannot affect"),
    (G, "wind_break(worn, wind), -conduct_c(worn, still_air_c, wet),",
        "wind_break(worn, wind), conduct_c(worn, still_air_c, wet),",
        "the readout prints a warm metal as a double minus"),
]


def read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def write(rel, text):
    with io.open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
        f.write(text)


def run_suite():
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", SUITE],
                       capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    return ("ALL GREEN" in out), out


def main():
    if "--list" in sys.argv:
        for i, (f, _old, _new, why) in enumerate(MUTATIONS):
            print("%2d  %-20s %s" % (i + 1, f, why))
        return 0

    originals = {}
    for rel in (G, E, P):
        originals[rel] = read(rel)

    bad_anchors = []
    for rel, old, _new, why in MUTATIONS:
        n = originals[rel].count(old)
        if n != 1:
            bad_anchors.append("%s x%d  (%s)" % (rel, n, why))
    if bad_anchors:
        print("BAD ANCHORS -- these do not match exactly once:")
        for b in bad_anchors:
            print("   " + b)
        return 2

    green, out = run_suite()
    if not green:
        print("the suite is RED before a single mutation; fix that first")
        print(out[-3000:])
        return 2
    print("baseline green")

    survivors = []
    try:
        for i, (rel, old, new, why) in enumerate(MUTATIONS):
            write(rel, originals[rel].replace(old, new))
            caught, _ = run_suite()
            caught = not caught
            write(rel, originals[rel])
            mark = "caught " if caught else "SURVIVED"
            print("%2d/%d  %s  %s" % (i + 1, len(MUTATIONS), mark, why))
            if not caught:
                survivors.append(why)
    finally:
        for rel in (G, E, P):
            write(rel, originals[rel])

    print("")
    print("%d/%d caught, %d survived, %d bad anchors"
          % (len(MUTATIONS) - len(survivors), len(MUTATIONS), len(survivors), 0))
    for s in survivors:
        print("   SURVIVED: " + s)
    return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
