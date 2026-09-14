#!/usr/bin/env python3
"""
woodsounds.py -- synthesise the TIMBER pack: iron meeting wood, and a tree
coming down. No recordings, no licences.

    python3 tools/woodsounds.py            # writes assets/audio/wood/

Same shape as tools/stepsounds.py: filtered noise and oscillators,
deterministic on SEED, 44.1 kHz mono 16-bit WAV plus a manifest.json that
scripts/WoodAudio.gd reads.

EVERY TOOL SOUNDS LIKE ITSELF ON A TRUNK (Lemon 2026-09-14: "different tools
should have different sounds"):

  axe_1..3     the bite: a hard edge-click, a deep CHOCK as the head buries,
               and a spray of chip-cracks a few ms behind it
  sword_1..3   a blade in a tree: thin, bright, a slap with a steel ring on
               the tail and hardly any body -- it went in a finger's width
  pick_1..3    a spike of iron: dull, low, a THUNK with almost no top end and
               one small crack as the point splits a fibre
  arrow_1..2   the THOCK of a broadhead, then the shaft quivering (a fast
               tremolo dying over a tenth of a second)

and the felling itself:

  creak_1..2   the hinge letting go: 2 s of stick-slip groan, rising, torn
               through by fibre-cracks that pile up toward the end
  crash_1..2   the crown meeting the ground: a 50 Hz body slam, a mess of
               branch snaps, and a wash of leaves that hangs a second after
  thud_1..2    a bucked log rolling onto the dirt: the same 180/430/900 wood
               modes the footstep pack uses for planks, hit hard
  limb_1..2    one limb coming off: a single sharp crack and a short hollow tail
"""
import json
import os
import wave

import numpy as np
from scipy.signal import lfilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "wood")
SR = 44100
SEED = 20260914
RNG = np.random.default_rng(SEED)


# ------------------------------------------------------------------ helpers --
def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def noise(seconds):
    return RNG.standard_normal(int(SR * seconds)).astype(np.float64)


def lowpass(x, cutoff, order=2):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = x
    for _ in range(order):
        y = lfilter([1.0 - a], [1.0, -a], y)
    return y


def highpass(x, cutoff, order=1):
    return x - lowpass(x, cutoff, order)


def band(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def env_ad(n, attack, decay, curve=2.0):
    e = np.zeros(n)
    a = max(1, int(attack * SR))
    a = min(a, n - 1)
    e[:a] = np.linspace(0.0, 1.0, a) ** (1.0 / curve)
    d = np.arange(n - a) / SR
    e[a:] = np.exp(-d / max(decay, 1e-3))
    return e


def thump(dur, f0, decay, bend=0.55, amp=1.0):
    """A body thump: a sine that falls in pitch as it dies."""
    tt = t(dur)
    f = f0 * (bend + (1.0 - bend) * np.exp(-tt / max(decay, 1e-3)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_ad(len(tt), 0.002, decay) * amp


def mode(dur, f, decay, amp=1.0, phase=None):
    """One resonant mode of a struck body."""
    tt = t(dur)
    if phase is None:
        phase = RNG.uniform(0.0, 2 * np.pi)
    return np.sin(2 * np.pi * f * tt + phase) * np.exp(-tt / decay) * amp


def wood_modes(dur, base=180.0, decay=0.09, amp=1.0):
    """The 180/430/900 knock the footstep pack gives planks, so a log on the
    ground and a boot on a dock agree about what wood sounds like."""
    r = base / 180.0
    return (mode(dur, 180.0 * r, decay, 1.0)
            + mode(dur, 430.0 * r, decay * 0.7, 0.55)
            + mode(dur, 900.0 * r, decay * 0.45, 0.30)) * amp


def cracks(dur, n, lo, hi, spread, glen=(0.002, 0.009), amp=1.0, start=0.0):
    """A cluster of tiny splintering impulses."""
    out = np.zeros(int(SR * dur))
    for _ in range(n):
        at = int((start + abs(RNG.normal(0.0, spread))) * SR)
        ln = int(RNG.uniform(*glen) * SR)
        if at + ln >= len(out):
            continue
        g = band(RNG.standard_normal(ln), lo, hi)
        out[at:at + ln] += g * env_ad(ln, 0.0005, RNG.uniform(0.0015, 0.006)) \
            * RNG.uniform(0.3, 1.0) * amp
    return out


def click(dur, lo, hi, decay, amp=1.0):
    n = noise(dur)
    return band(n, lo, hi) * env_ad(len(n), 0.0006, decay) * amp


def fit(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(fit(p, n) for p in parts)


def norm(x, peak=0.85):
    m = float(np.max(np.abs(x))) or 1.0
    return x / m * peak


def write(name, x, manifest, loop=False):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    pcm = np.clip(x, -1.0, 1.0)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((pcm * 32767.0).astype("<i2").tobytes())
    manifest[name] = {"file": name + ".wav",
                      "seconds": round(len(x) / SR, 3), "loop": loop}
    print("  %-14s %5.2f s" % (name + ".wav", len(x) / SR))


# ------------------------------------------------------------------- strikes --
# `k` is the variant, 0..2: the swing landed a little differently each time.

def axe(k):
    d = 0.42
    w = 0.9 + 0.1 * k
    edge = click(d, 1200.0, 5200.0, 0.009, 0.5)                 # the edge going in
    chock = thump(d, 150.0 * w, 0.085, 0.45, 1.4)                # the head burying
    body = wood_modes(d, 150.0 * w, 0.075, 0.7)
    chips = cracks(d, 14 + 3 * k, 1200.0, 6000.0, 0.030, amp=0.35, start=0.006)
    return norm(mix(edge, chock, body, chips), 0.88)


def sword(k):
    d = 0.34
    slap = click(d, 2600.0, 9000.0, 0.008, 0.9)                  # thin and bright
    body = thump(d, 260.0, 0.030, 0.6, 0.35)                     # barely any body
    ring = (mode(d, 2950.0 + 140.0 * k, 0.11, 0.28)
            + mode(d, 4420.0 + 90.0 * k, 0.07, 0.14))            # steel on the tail
    chips = cracks(d, 5, 2000.0, 8000.0, 0.015, amp=0.3, start=0.004)
    return norm(mix(slap, body, ring, chips), 0.80)


def pick(k):
    d = 0.40
    thunk = thump(d, 95.0 + 8.0 * k, 0.10, 0.5, 1.0)             # dull and low
    knock = lowpass(click(d, 300.0, 1400.0, 0.025, 0.7), 1200.0)  # no top end
    split = cracks(d, 2, 900.0, 4000.0, 0.012, glen=(0.004, 0.010), amp=0.45, start=0.010)
    return norm(mix(thunk, knock, split), 0.86)


def arrow(k):
    d = 0.30
    thock = click(d, 500.0, 2600.0, 0.014, 0.9) + thump(d, 380.0, 0.028, 0.6, 0.6)
    # the shaft quivering: a fast tremolo that dies out
    tt = t(d)
    quiver = np.sin(2 * np.pi * (72.0 + 6.0 * k) * tt) * np.exp(-tt / 0.09)
    quiver *= (0.5 + 0.5 * np.sin(2 * np.pi * 900.0 * tt)) * 0.35
    quiver = band(quiver, 300.0, 3000.0)
    return norm(mix(thock, quiver), 0.78)


# ------------------------------------------------------------------- felling --

def creak(k):
    d = 2.1
    tt = t(d)
    # stick-slip: a low sawtooth whose pitch wanders and climbs as the hinge
    # takes more load, gated by a slow tremor so it groans rather than hums
    f = 62.0 + 10.0 * k + 34.0 * (tt / d) ** 1.6 \
        + 6.0 * np.sin(2 * np.pi * 3.1 * tt) + 3.0 * lowpass(noise(d), 4.0)[:len(tt)] * 8.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    tremor = 0.55 + 0.45 * np.clip(np.sin(2 * np.pi * (7.0 + 2.0 * k) * tt
                                           + 3.0 * np.sin(2 * np.pi * 1.3 * tt)), 0.0, 1.0)
    groan = band(saw, 70.0, 1800.0) * tremor
    swell = np.clip(tt / 0.25, 0.0, 1.0) * (0.55 + 0.45 * (tt / d)) \
        * np.exp(-np.clip(tt - 1.85, 0.0, None) / 0.10)
    groan *= swell
    # fibres letting go: sparse at first, piling up toward the break
    pops = np.zeros(len(tt))
    for i in range(38 + 8 * k):
        u = RNG.uniform(0.0, 1.0) ** 0.45            # skewed late
        at = int(u * (d - 0.15) * SR)
        ln = int(RNG.uniform(0.004, 0.018) * SR)
        g = band(RNG.standard_normal(ln), 600.0, 5000.0) * env_ad(ln, 0.0005, 0.004)
        pops[at:at + ln] += g * RNG.uniform(0.25, 1.0) * (0.4 + 0.6 * u)
    # the hinge finally SNAPS at the end
    snap_at = int((d - 0.22) * SR)
    snap = np.zeros(len(tt))
    s = mix(click(0.20, 400.0, 6000.0, 0.030, 1.0), thump(0.20, 120.0, 0.08, 0.5, 0.9),
            cracks(0.20, 10, 800.0, 6000.0, 0.02, amp=0.6))
    snap[snap_at:snap_at + len(s)] += s[:len(tt) - snap_at]
    return norm(mix(groan * 0.9, pops * 0.6, snap), 0.86)


def crash(k):
    d = 1.6
    tt = t(d)
    slam = thump(d, 48.0 + 4.0 * k, 0.32, 0.55, 1.6) + thump(d, 95.0, 0.14, 0.5, 0.8)
    body = wood_modes(d, 120.0, 0.16, 0.35)
    snaps = cracks(d, 46, 400.0, 4500.0, 0.16, glen=(0.004, 0.016), amp=0.55)
    # leaves and small stuff coming down for a second after
    wash = band(noise(d), 1800.0, 7000.0) * (env_ad(len(tt), 0.02, 0.45) * 0.5
                                              + env_ad(len(tt), 0.30, 0.25) * 0.3)
    wash *= 0.6 + 0.4 * np.abs(lowpass(noise(d), 18.0)[:len(tt)]) * 6.0
    dust = band(noise(d), 200.0, 900.0) * env_ad(len(tt), 0.01, 0.22) * 0.35
    return norm(mix(slam, body, snaps, wash * 0.22, dust), 0.9)


def thud(k):
    d = 0.36
    body = thump(d, 78.0 + 6.0 * k, 0.09, 0.5, 0.9)
    knock = wood_modes(d, 165.0 + 12.0 * k, 0.10, 0.7)
    scuff = band(noise(d), 300.0, 2500.0) * env_ad(int(d * SR), 0.004, 0.05) * 0.4
    return norm(mix(body, knock, scuff), 0.84)


def limb(k):
    d = 0.32
    crack = click(d, 700.0, 6500.0, 0.018, 1.0)
    split = cracks(d, 8, 900.0, 6000.0, 0.03, amp=0.6, start=0.004)
    tail = wood_modes(d, 240.0 + 20.0 * k, 0.07, 0.4)
    return norm(mix(crack, split, tail), 0.82)


def main():
    manifest = {}
    print("timber ->", os.path.normpath(OUT))
    for k in range(3):
        write("axe_%d" % (k + 1), axe(k), manifest)
        write("sword_%d" % (k + 1), sword(k), manifest)
        write("pick_%d" % (k + 1), pick(k), manifest)
    for k in range(2):
        write("arrow_%d" % (k + 1), arrow(k), manifest)
        write("creak_%d" % (k + 1), creak(k), manifest)
        write("crash_%d" % (k + 1), crash(k), manifest)
        write("thud_%d" % (k + 1), thud(k), manifest)
        write("limb_%d" % (k + 1), limb(k), manifest)
    json.dump({"generator": "tools/woodsounds.py", "version": 1, "seed": SEED,
               "sample_rate": SR,
               "tools": {"axe": 3, "sword": 3, "pick": 3, "arrow": 2},
               "sounds": manifest},
              open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
    print("  manifest.json (%d sounds)" % len(manifest))


if __name__ == "__main__":
    main()
