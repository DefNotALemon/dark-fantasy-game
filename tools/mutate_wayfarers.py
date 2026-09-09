#!/usr/bin/env python3
# =============================================================================
# tools/mutate_wayfarers.py -- is WayfarerTests load-bearing, or merely green?
#
#   python3 tools/mutate_wayfarers.py
#
# A green suite is evidence about the suite, not only about the source. Each
# mutation below reintroduces a defect the design deliberately does not have,
# runs the suite against the damaged file, and requires it to go RED. A
# mutation that survives is either a hole in the suite or a redundancy in the
# source -- and the standing rule since 2026-09-09 is to say which, in here,
# rather than bolt on a fake assertion.
#
# Every mutation is restored before the next one runs, and the originals are
# restored on any exit path including a crash.
# =============================================================================

import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
SUITE = 'res://tests/WayfarerTests.gd'

WF = os.path.join(ROOT, 'scripts', 'Wayfarers.gd')
CH = os.path.join(ROOT, 'scripts', 'Chronicle.gd')
RF = os.path.join(ROOT, 'scripts', 'RumourFeed.gd')

# (name, file, find, replace, what the suite must notice)
MUTATIONS = [
    ('no-kind-cap', WF,
     'if int(per_kind.get(kd, 0)) >= KIND_CAP:',
     'if false:',
     'thirteen pedlars of twenty and not one pilgrim'),
    ('no-night', WF,
     'if hour < dep or hour >= halt:',
     'if false:',
     'walking through the night'),

    ('no-storm', WF,
     '\t\t3:\n\t\t\treturn 0.55\n\treturn 0.0',
     '\t\t3:\n\t\t\treturn 0.55\n\treturn 1.0',
     'a gale that does not stop anybody'),

    ('rain-is-free', WF,
     '\t\t2:\n\t\t\treturn 0.82',
     '\t\t2:\n\t\t\treturn 1.0',
     'rain that costs a walker nothing'),

    ('held-every-step', WF,
     '\t\tif not was_holding:\n\t\t\tband_held.emit(b, level)',
     '\t\tband_held.emit(b, level)',
     'announcing the storm every half hour instead of once'),

    ('linear-locate', WF,
     '\twhile lo < hi:\n\t\tvar mid := (lo + hi + 1) / 2\n\t\tlast_examined += 1\n'
     '\t\tif float((legs[mid] as Dictionary)["cum"]) <= want:\n\t\t\tlo = mid\n'
     '\t\telse:\n\t\t\thi = mid - 1',
     '\tfor mi in legs.size():\n\t\tlast_examined += 1\n'
     '\t\tif float((legs[mi] as Dictionary)["cum"]) <= want:\n\t\t\tlo = mi\n\thi = lo',
     'a linear walk wearing the index section as a disguise'),

    ('redate-on-arrival', CH,
     '\t\t"day": born,',
     '\t\t"day": days,',
     'second-hand news arriving as if it happened this morning'),

    ('deliver-home', WF,
     '\tif String(c.get("from", "")) == place:\n\t\tb["carried"] = {}\n\t\treturn',
     '\tif false:\n\t\tb["carried"] = {}\n\t\treturn',
     'carrying news back to the village it came from'),

    ('no-take', WF,
     '\tb["carried"] = r\n\tcarried_total += 1',
     '\tcarried_total += 1',
     'nobody ever picking anything up'),

    ('stale-delivery', CH,
     '\tif born < days - RUMOUR_DAYS:\n\t\treturn false',
     '\tif false:\n\t\treturn false',
     'delivering news the board would erase on its next step'),

    # Both of these were found by LOOKING at the running game, not by the
    # suite. RF = scripts/RumourFeed.gd.
    ('name-fades-early', RF,
     '_head_t = maxf(HEAD_HOLD, dwell_for(text) + LIVE_BONUS)',
     '_head_t = HEAD_HOLD',
     'a speaker whose name fades while their sentence is still on screen'),

    ('village-echoes-traveller', RF,
     '\tif not _here.is_empty():\n\t\tmark_heard(_here, text)',
     '\tif false:\n\t\tmark_heard(_here, text)',
     'the board repeating verbatim what the traveller just told you'),
    ('always-greet', WF,
     '\tif days - float(b.get("met_day", -1000.0)) < REMEET_DAYS:\n\t\treturn {}',
     '\tif false:\n\t\treturn {}',
     'a pedlar who greets you every one and a third seconds'),

    ('refusal-is-delivery', WF,
     '\tif not took:\n\t\treturn {}',
     '\tif false:\n\t\treturn {}',
     'spending the greeting behind a menu that refused it'),

    # WITHDRAWN, not fixed. Dropping the fposmod from the MID-LEG step
    # survived, and correctly: that branch only runs when the distance
    # left is LESS than the gap to the next stop mark, and the last stop
    # mark IS the whole circuit -- so along + d can never reach total there
    # and the wrap can never fire. That is a redundancy in the source, not
    # a hole in the suite, and inventing an assertion for it would buy a
    # fake one. The wrap that does real work is the one AT the stop, and
    # that is what is mutated instead.
    # The first two attempts here were WITHDRAWN rather than fixed. Leaving
    # `along` sitting on `total` at a stop is unobservable: every consumer
    # clamps (`_locate`), matches it anyway (`stop_at`), or renormalises it
    # on the next iteration. Both fposmods in `_advance_band` are defensive,
    # not load-bearing, and saying so here is more honest than manufacturing
    # an assertion that only a mutation would ever fail. The wrap that IS
    # load-bearing is the one in `_next_stop`: standing exactly on a stop
    # mark the gap to the next stop is zero, and without the wrap a band
    # never leaves the doorstep it arrived at. That is the mutation.
    ('stop-not-strictly-ahead', WF,
     '\t\tif at > along + 0.001 and at < best:',
     '\t\tif at >= along and at < best:',
     'a band that arrives somewhere and never leaves it again'),

    ('arrive-always', WF,
     '\tif String(b.get("last", "")) == place:\n\t\treturn',
     '\tif false:\n\t\treturn',
     'arriving being a state rather than an edge'),

    ('save-drops-carried', WF,
     '\t\t\t"carried": (bd.get("carried", {}) as Dictionary).duplicate(true),',
     '\t\t\t"carried": {},',
     'a save that forgets what everyone was carrying'),

    ('backwards-time', WF,
     '\tif d > 0.0:\n\t\t## Backwards time is not a season of history.',
     '\tif true:\n\t\t## Backwards time is not a season of history.',
     'a clock wound backwards counted as history'),

    ('no-handover-cap', WF,
     '\t\t_hours += minf(d, 30.0) * 24.0',
     '\t\t_hours += d * 24.0',
     'a sixty-day jump handed over in one frame'),

    ('stop-marks-departure', WF,
     '\t\tstops.append({"place": to, "at": run})',
     '\t\tstops.append({"place": from, "at": run})',
     'every stop mark naming the village behind you'),

    ('ignore-direction', WF,
     '\tif not bool(loc["fwd"]):\n\t\tt = 1.0 - t',
     '\tif false:\n\t\tt = 1.0 - t',
     'walking every second road backwards'),

    ('budget-ignored', WF,
     '\twhile _steps < want and left > 0:',
     '\twhile _steps < want:',
     'a month of sleep run entirely on one frame'),
]


def run_suite():
    p = subprocess.run([GODOT, '--headless', '--path', ROOT, '--script', SUITE],
                       capture_output=True, text=True, timeout=600)
    return p.returncode, (p.stdout or '') + (p.stderr or '')


def main():
    if not os.path.exists(GODOT):
        print('no Godot at %s' % GODOT)
        return 2
    backups = {}
    for path in {m[1] for m in MUTATIONS}:
        fd, tmp = tempfile.mkstemp(suffix='.bak')
        os.close(fd)
        shutil.copy2(path, tmp)
        backups[path] = tmp
    try:
        rc, out = run_suite()
        if rc != 0:
            print('BASELINE IS ALREADY RED -- fix that first')
            print(out[-2000:])
            return 1
        print('baseline green')
        caught, survived, broken = 0, [], []
        for name, path, find, repl, why in MUTATIONS:
            src = open(path, encoding='utf-8').read()
            n = src.count(find)
            if n != 1:
                broken.append('%s (anchor matched %d times)' % (name, n))
                print('  ??  %-22s ANCHOR MATCHED %d TIMES' % (name, n))
                continue
            open(path, 'w', encoding='utf-8').write(src.replace(find, repl))
            rc, out = run_suite()
            open(path, 'w', encoding='utf-8').write(src)
            if rc == 0:
                survived.append('%s -- %s' % (name, why))
                print('  !!  %-22s SURVIVED  (%s)' % (name, why))
            else:
                fails = [l for l in out.splitlines() if 'FAIL' in l]
                caught += 1
                print('  ok  %-22s caught by %d assertion(s)' % (name, len(fails)))
        print('')
        print('%d of %d mutations caught' % (caught, len(MUTATIONS)))
        for s in survived:
            print('  SURVIVED: %s' % s)
        for b in broken:
            print('  BROKEN ANCHOR: %s' % b)
        return 0 if (caught == len(MUTATIONS)) else 1
    finally:
        for path, tmp in backups.items():
            shutil.copy2(tmp, path)
            os.remove(tmp)
        print('originals restored')


if __name__ == '__main__':
    sys.exit(main())
