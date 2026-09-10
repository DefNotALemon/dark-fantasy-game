#!/usr/bin/env python3
"""
mutate_fireaudio.py -- prove FireAudioTests can actually fail.

    python3 tools/mutate_fireaudio.py            # all mutations
    python3 tools/mutate_fireaudio.py --only 7   # just one, for debugging

A green suite is evidence about the SUITE, not only about the source. Each
mutation below reintroduces a specific defect the round would ship if nobody
were looking; the suite is then run and is expected to go RED. A mutation that
SURVIVES is a finding: either an assertion that cannot fail (a constant
compared with itself), a test that was never written, or dead code -- and the
honest response to each of those three is different (2026-09-07, 2026-09-09,
2026-09-10 03:00).

Nine of the forty-eight mutations in the exposure round survived the first
sweep and every one of them was the same defect: an assertion stated against
the very constant it existed to guard. Every margin in FireAudioTests is
therefore stated as a LITERAL -- "a fed fire pops at least four times as often
as a dying one", "at least 150 pops in a minute" -- which is the only form of
the assertion that can fail.

Six of these mutate scripts/Firepit.gd rather than scripts/FireAudio.gd. That
is deliberate: this round adds no public method to Firepit's burning model and
rests entirely on it, and a stub answering the same six names would let the
whole suite pass while the real class rotted.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
SUITE = "res://tests/FireAudioTests.gd"

FA = "scripts/FireAudio.gd"
FP = "scripts/Firepit.gd"

# (label, file, old, new)
MUTATIONS = [
    # ---- the bed -----------------------------------------------------------
    ("every fire gets the big bed", FA,
     "const BIG_FUEL := 300.0", "const BIG_FUEL := 0.0"),
    ("no fire ever does", FA,
     "const BIG_FUEL := 300.0", "const BIG_FUEL := 99999.0"),
    ("coals get a quiet flame instead of a coal bed", FA,
     'return "ember_bed"', 'return "fire_bed_small"'),
    ("a dead pit still sounds", FA,
     '\tif state == Firepit.State.EMBERS:\n\t\treturn "ember_bed"\n\treturn ""',
     '\tif state == Firepit.State.EMBERS:\n\t\treturn "ember_bed"\n\treturn "ember_bed"'),
    ("coals are as loud as a flame", FA,
     "const EMBER_DB := -21.0", "const EMBER_DB := -7.0"),

    # ---- the crackle -------------------------------------------------------
    ("the crackle rate stops scaling with fuel", FA,
     "const POP_HZ_MAX := 3.30", "const POP_HZ_MAX := 0.55"),
    ("a dying fire pops like a fed one", FA,
     "const POP_HZ_MIN := 0.55", "const POP_HZ_MIN := 3.30"),
    ("the flicker stops moving the rate", FA,
     "const POP_WARP := 0.56", "const POP_WARP := 0.0"),
    ("f01 is no longer clamped", FA,
     "(POP_HZ_MAX - POP_HZ_MIN) * clampf(f01, 0.0, 1.0)",
     "(POP_HZ_MAX - POP_HZ_MIN) * f01"),
    ("the signal is no longer clamped", FA,
     "POP_WARP * clampf(sig, 0.0, 1.0)", "POP_WARP * sig"),
    ("logs shift twice as often", FA,
     "const SETTLE_EVERY := 11", "const SETTLE_EVERY := 5"),
    ("the very first pop is a settle", FA,
     "if n > 0 and n % SETTLE_EVERY == 0:", "if n % SETTLE_EVERY == 0:"),
    ("only three of the six crackles are ever used", FA,
     'return "crackle_%d" % (1 + (n % POP_KINDS))',
     'return "crackle_%d" % (1 + (n % SETTLE_KINDS))'),
    ("a pop names a sound that is not in the pack", FA,
     'return "crackle_%d" % (1 + (n % POP_KINDS))',
     'return "crackle_%d" % (1 + n)'),

    # ---- rain --------------------------------------------------------------
    ("it hisses in the dry", FA,
     "if burn_rate <= 1.0001:", "if burn_rate <= 0.0:"),
    ("it never hisses at all", FA,
     "if burn_rate <= 1.0001:", "if burn_rate <= 99.0:"),

    # ---- the ranking -------------------------------------------------------
    ("dead pits are audible", FA,
     '\t\tif int(d.get("state", Firepit.State.OUT)) == Firepit.State.OUT:\n\t\t\tcontinue',
     '\t\tif int(d.get("state", Firepit.State.OUT)) == 99:\n\t\t\tcontinue'),
    ("you can hear a fire from anywhere", FA,
     "if dist > hear_r:", "if dist > hear_r * 1000.0:"),
    ("the ranking is backwards", FA,
     'live.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))',
     'live.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))'),

    # ---- the beds ----------------------------------------------------------
    ("the slot assignment loses its stability", FA,
     "\t\tif not prev.has(id):\n\t\t\tcontinue", "\t\tif true:\n\t\t\tcontinue"),
    ("a stale slot outside the budget is honoured", FA,
     "if slot >= 0 and slot < budget and not used.has(slot):",
     "if slot >= 0 and not used.has(slot):"),
    ("more fires are seated than there are beds", FA,
     "var keep: Array = ranked.slice(0, budget)",
     "var keep: Array = ranked.slice(0, budget + 3)"),
    ("only one fire is ever seated", FA,
     "var keep: Array = ranked.slice(0, budget)",
     "var keep: Array = ranked.slice(0, 1)"),

    # ---- the fades ---------------------------------------------------------
    ("a fire fades out as fast as it comes in", FA,
     "var span := FADE_IN if want > now else FADE_OUT", "var span := FADE_IN"),
    ("a bed snaps to its target", FA,
     "return clampf(now + clampf(want - now, -step, step), 0.0, 1.0)",
     "return clampf(want, 0.0, 1.0)"),
    ("silence is not silent", FA,
     "\tif gain <= 0.001:\n\t\treturn SILENT_DB", "\tif gain <= -1.0:\n\t\treturn SILENT_DB"),

    # ---- the flame signal (Firepit.gd) -------------------------------------
    ("the fast gutter is gone", FP,
     "return clampf(0.5 + 0.30 * sin(t * FLICKER_A) + 0.20 * sin(t * FLICKER_B), 0.0, 1.0)",
     "return clampf(0.5 + 0.00 * sin(t * FLICKER_A) + 0.20 * sin(t * FLICKER_B), 0.0, 1.0)"),
    ("the signal no longer IS the old flicker", FP,
     "return clampf(0.5 + 0.30 * sin(t * FLICKER_A) + 0.20 * sin(t * FLICKER_B), 0.0, 1.0)",
     "return clampf(0.5 + 0.40 * sin(t * FLICKER_A) + 0.20 * sin(t * FLICKER_B), 0.0, 1.0)"),
    ("the gutter slows to the breath", FP,
     "const FLICKER_A := 11.3", "const FLICKER_A := 4.1"),
    ("coals gutter like a flame", FP,
     "const EMBER_BREATH := 0.22", "const EMBER_BREATH := 1.0"),
    ("a flame is at full size on a minute of fuel", FP,
     "return clampf(fuel / FUEL_BRIGHT, 0.0, 1.0)", "return clampf(fuel / 60.0, 0.0, 1.0)"),
    ("coals burn as hard as a flame", FP,
     "return clampf(ember_t / EMBER_SECONDS, 0.0, 1.0) * EMBER_HEAT_MULT",
     "return clampf(ember_t / EMBER_SECONDS, 0.0, 1.0)"),

    # ---- the light spill (Firepit.gd) --------------------------------------
    ("a cold pit takes the shadows", FP,
     '\t\tif int(d.get("state", State.OUT)) == State.OUT:\n\t\t\tcontinue',
     '\t\tif int(d.get("state", State.OUT)) == 99:\n\t\t\tcontinue'),
    ("shadows carry to the horizon", FP,
     "\t\tif dist > range_m:\n\t\t\tcontinue", "\t\tif dist > range_m * 1000.0:\n\t\t\tcontinue"),
    ("the FURTHEST fire casts", FP,
     "\t\tif dist < best_d:", "\t\tif dist > best_d or best == -1:"),
    ("every fire in the county casts shadows", FP,
     "fp2.set_shadow(int(fp2.get_instance_id()) == pick)", "fp2.set_shadow(true)"),
    ("nothing ever casts", FP,
     "\t_light.shadow_enabled = on", "\t_light.shadow_enabled = false"),
    ("a fed flame is the same colour as a starved one", FP,
     "return COLOR_LOW.lerp(COLOR_HOT, clampf(f01, 0.0, 1.0))", "return COLOR_LOW"),
    ("coals glow yellow", FP,
     "\tif st == State.EMBERS:\n\t\treturn COLOR_EMBER", "\tif st == State.EMBERS:\n\t\treturn COLOR_HOT"),

    # ---- the wiring (Firepit.gd) -------------------------------------------
    ("the light stops reading the shared signal", FP,
     "(1.1 + 1.4 * f01) * (0.90 + 0.20 * flame_signal(_flicker))", "(1.1 + 1.4 * f01)"),
    ("the LIT colour stops moving", FP,
     "\t\t\t_light.light_color = light_color(State.LIT, f01)\n", "\n"),
    ("the coal bed stops breathing", FP,
     "_set_ember_glow((0.35 + 0.9 * e01) * (0.86 + 0.28 * esig))",
     "_set_ember_glow(0.35 + 0.9 * e01)"),
    ("coals freeze again -- the clock stops advancing in EMBERS", FP,
     "\t_flicker += delta\n\tif state == State.EMBERS:", "\tif state == State.EMBERS:"),
    ("the light and flame01() disagree about how big a flame is", FP,
     "var f01 := clampf(fuel / FUEL_BRIGHT, 0.0, 1.0)",
     "var f01 := clampf(fuel / 300.0, 0.0, 1.0)"),
    # ---- the looping fix (found by the LIVE pass, 2026-09-10 06:00) --------
    ("the bed loops nowhere -- the zero-length loop, which is the live defect", FA,
     "return maxi(0, int(round(length_s * float(mix_rate))) - 1)", "return 0"),
    ("the loop point comes back from the COMPRESSED byte count", FA,
     "w.loop_end = wav_loop_end(w.get_length(), w.mix_rate)",
     "w.loop_end = wav_loop_end(float(w.data.size()) / float(w.mix_rate) / 2.0, w.mix_rate)"),
    ("a bed that stopped while it was wanted is never restarted", FA,
     'if _bed_want[s] > 0.0 and _bed_key[s] != "" and p.stream != null and not p.playing:',
     "if false:"),
]


def run_suite():
    p = subprocess.run(
        [GODOT, "--headless", "--path", ROOT, "--script", SUITE],
        capture_output=True, text=True, cwd=ROOT, timeout=180,
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    only = None
    if "--only" in sys.argv:
        only = int(sys.argv[sys.argv.index("--only") + 1])

    # Baseline first: a sweep against an already-red suite proves nothing.
    rc, out = run_suite()
    if rc != 0:
        print("BASELINE IS RED -- fix the suite before sweeping.")
        print(out[-2000:])
        return 2
    print("baseline green.\n")

    caught, survived, bad = 0, [], []
    for i, (label, rel, old, new) in enumerate(MUTATIONS):
        if only is not None and i != only:
            continue
        path = os.path.join(ROOT, rel)
        src = open(path).read()
        n = src.count(old)
        if n != 1:
            print("%2d  BAD ANCHOR (%d matches)  %s" % (i, n, label))
            bad.append((i, label))
            continue
        shutil.copy2(path, path + ".mutbak")
        try:
            open(path, "w").write(src.replace(old, new, 1))
            rc, out = run_suite()
        finally:
            shutil.move(path + ".mutbak", path)
        if rc != 0:
            caught += 1
            print("%2d  caught     %s" % (i, label))
        else:
            survived.append((i, label))
            print("%2d  SURVIVED   %s" % (i, label))

    total = caught + len(survived)
    print("\n--- %d/%d caught, %d survived, %d bad anchors ---"
          % (caught, total, len(survived), len(bad)))
    for i, label in survived:
        print("  SURVIVED %2d  %s" % (i, label))
    for i, label in bad:
        print("  BAD ANCHOR %2d  %s" % (i, label))

    # And the suite must be green again afterwards, or a restore failed.
    rc, _ = run_suite()
    print("restored suite: %s" % ("green" if rc == 0 else "RED -- RESTORE FAILED"))
    return 0 if (not survived and not bad and rc == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
