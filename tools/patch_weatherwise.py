#!/usr/bin/env python3
"""tools/patch_weatherwise.py -- wires Weatherwise into the two wildlife files.

`scripts/Weatherwise.gd`, `tests/WeatherwiseTests.gd` and `scripts/Telegraph.gd`
are landed and committed directly. `scripts/WildlifeDirector.gd` and
`scripts/Critter.gd` are NOT: both carry Lemon's own uncommitted work, so the
eleven hunks below live on disk and OUTSIDE the commit, and this file is how
they are reproducible.

Every hunk is guarded on a distinctive piece of what it WRITES, so a second run
is a clean no-op and the md5 does not move. Nothing here deletes a line: every
hunk is an insertion, or a replacement of a line by a superset of itself.

Three of the Critter hunks belong next to lines carrying an EM-DASH that this
file would rather not have to reproduce byte for byte. The ledger's own advice
for that case is to elide: anchor on the lines either side and leave the
em-dashed sentence out of the anchor entirely. That is why the _graze and
_patrol anchors start at `var pull` rather than at the function header, and
why they are told apart by `home_radius` versus `home_radius * 2.4`.

    python3 tools/patch_weatherwise.py --dry-run
    python3 tools/patch_weatherwise.py
"""
import os, sys, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WD = "scripts/WildlifeDirector.gd"
CR = "scripts/Critter.gd"
DASH = "—"

WX = '''func _wx() -> Dictionary:
	## [weather] The ONE place this Director asks what the sky is doing.
	## World owns the Weather node; a world that has none %(d)s the headless
	## suites, the old build, a test harness %(d)s gets an empty dictionary back,
	## which Weatherwise reads as a clear day. So wildlife without weather
	## behaves exactly as it did before this existed.
	var w := get_parent()
	if w == null or not w.has_method("weather"):
		return {}
	var wx = w.call("weather")
	if wx == null or not is_instance_valid(wx):
		return {}
	## `level` is where the sky is HEADED and `_from` is where it came from %(d)s
	## Weather.gd's own vocabulary. The gap between them is the front, and the
	## front is what stirs the big herbivores before the rain lands.
	return Weatherwise.env(int(wx.level), int(wx.get("_from")),
		float(wx.get("_blend")), _hour)
''' % {"d": DASH}

HOLD = ('\tif weather_cover >= COVER_HOLD:\n'
        '\t\t_steer(Vector3.ZERO, delta, 6.0)\n'
        '\t\t_call_cool = maxf(_call_cool, CALL_COOLDOWN.x * weather_cover)\n'
        '\t\treturn\n')

GRAZE_TAIL = "\tvar pull := _home - global_position\n\tpull.y = 0.0\n\tif pull.length() > home_radius:"
PATROL_TAIL = "\tvar pull := _home - global_position\n\tpull.y = 0.0\n\tif pull.length() > home_radius * 2.4:"

GRAZE_NOTE = ('\t## [weather] ...and in a downpour it has a TREE instead of a patch. This\n'
              '\t## is the behaviour half of Weatherwise: at weather_cover 0 it is exactly\n'
              '\t## the grazing this game has always had, and past COVER_HOLD the animal\n'
              '\t## stands where it is and stops calling %s which is the whole of "rain\n'
              '\t## should quiet the birds and put the deer up". The idle loop keeps\n'
              '\t## running underneath, so what you see is a deer standing under a bough\n'
              '\t## breathing, not a deer switched off.\n') % DASH

PATROL_NOTE = ('\t## [weather] The same hold, and it bites at a different sky: a fox\'s urge\n'
               '\t## barely reaches COVER_HOLD even in a storm, so foul weather keeps the\n'
               '\t## hunters ranging long after it has put everything else under a bough.\n')

HUNKS = [
    (WD, "func _wx",
     "## ================================ Clock ===================================",
     "## ================================= Sky ====================================\n\n\n" + WX + "\n## ================================ Clock ==================================="),

    (WD, "Weatherwise.cover_urge",
     "\tfor c in live:\n\t\tif is_instance_valid(c):\n\t\t\tc.set_clock(_hour, _phase)",
     "\tvar wx := _wx()\n\tfor c in live:\n\t\tif is_instance_valid(c):\n\t\t\tc.set_clock(_hour, _phase)\n\t\t\t## [weather] ...and how badly it wants to be under something.\n\t\t\tc.weather_cover = Weatherwise.cover_urge(c.species, wx)"),

    (WD, "\tvar wx := _wx()\n\tvar pool: Array = []\n\tvar total := 0.0",
     "\tvar pool: Array = []\n\tvar total := 0.0",
     "\tvar wx := _wx()\n\tvar pool: Array = []\n\tvar total := 0.0"),

    (WD, "w *= Weatherwise.out_mult",
     "\t\t\tw *= 1.8 if dusk else 0.45\n\t\tpool.append({\"key\": k, \"w\": w})",
     "\t\t\tw *= 1.8 if dusk else 0.45\n\t\t## [weather] What the SKY does to this animal " + DASH + " the same shape as the\n\t\t## dusk term directly above it, and deliberately in the same place: an\n\t\t## OFFSET through the multiplier chain that was already here, never a\n\t\t## replacement for the roll. It is also the only gate that can return\n\t\t## zero, which is how `rain_only` finally means something: the Red Eft\n\t\t## is not rare on a dry day, it is absent.\n\t\tw *= Weatherwise.out_mult(k, wx)\n\t\tif w <= 0.0:\n\t\t\tcontinue\n\t\tpool.append({\"key\": k, \"w\": w})"),

    (WD, "\tvar zone := _zone_at(at)\n\tvar wx := _wx()",
     "\tvar zone := _zone_at(at)\n\tvar pool: Array = []\n\tfor e in CritterDex.species_for_zone(zone):",
     "\tvar zone := _zone_at(at)\n\tvar wx := _wx()\n\tvar pool: Array = []\n\tfor e in CritterDex.species_for_zone(zone):"),

    (WD, "only relief from them in this game",
     "\t\tif not CritterDex.is_awake(k, _hour, _phase):\n\t\t\tcontinue\n\t\tpool.append(k)",
     "\t\tif not CritterDex.is_awake(k, _hour, _phase):\n\t\t\tcontinue\n\t\t## [weather] Swarms come through their OWN door and their own budget,\n\t\t## so the weight term above cannot reach them and this is the second\n\t\t## call site rather than a duplicate of the first. Rain knocks insects\n\t\t## out of the air: in a full storm the blackflies are simply gone,\n\t\t## which is the only relief from them in this game that is not smoke.\n\t\tif _rng.randf() > Weatherwise.out_mult(k, wx):\n\t\t\tcontinue\n\t\tpool.append(k)"),

    (WD, "Weatherwise.legend_allows",
     "func _legend_gate(key: String, condition: bool, chance: float, at_range: float) -> void:\n\tvar placed: Variant = legends_placed.get(key, null)",
     "func _legend_gate(key: String, condition: bool, chance: float, at_range: float) -> void:\n\t## [weather] `fog_only` is the project's other never-read weather flag, and\n\t## this is where it finally decides something: the Specter Moose wants the\n\t## soft grey band, not a clear night and not the inside of a thunderstorm.\n\t## Folded into `condition` rather than bolted on, so the retirement branch\n\t## below sends one home when the sky clears, exactly as it does at dawn.\n\tcondition = condition and Weatherwise.legend_allows(key, _wx())\n\tvar placed: Variant = legends_placed.get(key, null)"),

    (WD, "_tele.weather = _wx()",
     "\tif _tele != null and is_instance_valid(_tele) and player.has_method(\"get\") :",
     "\t## [weather] The bus carries the sky, so that both halves of the alarm\n\t## network " + DASH + " the player's own noise going out, and the relay carrying the\n\t## word on " + DASH + " know what the weather is doing to hearing.\n\tif _tele != null and is_instance_valid(_tele):\n\t\t_tele.weather = _wx()\n\tif _tele != null and is_instance_valid(_tele) and player.has_method(\"get\") :"),

    (CR, "var weather_cover := 0.0",
     "var home_radius := 30.0",
     "var home_radius := 30.0\n## [weather] 0..1, handed over by WildlifeDirector.set_clock out of\n## Weatherwise.cover_urge(): how badly this animal wants to be under\n## something right now. Zero on a clear day, always, for every species.\nvar weather_cover := 0.0\n## Past this much urge an animal stops working its patch and stands. Below it\n## the weather is something it notices; above it, something it shelters from.\nconst COVER_HOLD := 0.55"),

    (CR, "should quiet the birds and put the deer up",
     GRAZE_TAIL,
     GRAZE_NOTE + HOLD + GRAZE_TAIL),

    (CR, "hunters ranging long after",
     PATROL_TAIL,
     PATROL_NOTE + HOLD + PATROL_TAIL),
]


def main():
    dry = "--dry-run" in sys.argv
    files = {}
    for path, _, _, _ in HUNKS:
        if path not in files:
            with open(os.path.join(ROOT, path), "r") as fh:
                files[path] = fh.read()
    before = {p: hashlib.md5(s.encode()).hexdigest() for p, s in files.items()}

    applied = skipped = 0
    for i, (path, guard, old, new) in enumerate(HUNKS):
        src = files[path]
        if guard in src:
            print("  skip   %2d  %-24s already wired" % (i, os.path.basename(path)))
            skipped += 1
            continue
        n = src.count(old)
        if n != 1:
            print("  ERROR  %2d  %-24s anchor matches %d times" % (i, os.path.basename(path), n))
            return 1
        files[path] = src.replace(old, new, 1)
        applied += 1
        print("  apply  %2d  %-24s +%d lines" % (i, os.path.basename(path),
                                                new.count("\n") - old.count("\n")))

    if not dry:
        for p, s in files.items():
            with open(os.path.join(ROOT, p), "w") as fh:
                fh.write(s)
    after = {p: hashlib.md5(s.encode()).hexdigest() for p, s in files.items()}
    print("\n%d applied, %d already present%s" % (applied, skipped, "  (dry run)" if dry else ""))
    for p in sorted(files):
        print("  %-30s %s -> %s" % (p, before[p][:8], after[p][:8]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
