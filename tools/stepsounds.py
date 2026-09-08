#!/usr/bin/env python3
"""
stepsounds.py -- synthesise the footstep + foley pack. No recordings, no licences.

    python3 tools/stepsounds.py            # writes assets/audio/footsteps/

Same shape as tools/watersounds.py and tools/crittercalls.py: every sound is
filtered noise and oscillators, deterministic on SEED, written as 44.1 kHz mono
16-bit WAV with a manifest.json that scripts/StepAudio.gd reads.

NINE surface families, each with three step variants and one landing:

  grass   soft brush, no body          lush_meadow / dry_grass / barrens
  dirt    packed thump, low body       patchy / dirt
  mud     wet squelch with a suck tail mud / moss_bog
  leaf    dry litter crackle           forest_floor
  gravel  loose grains + rattle        gravel / scree
  sand    pure hiss, no click          sand / beach
  snow    granular crunch + compress   snow_dusted
  wood    resonant knock (180/430/900) built pieces, fallen trunks, docks
  stone   hard click + small tail      cave floor, keep flagstone

plus foley that rides the same footfall under the step:

  cloth_1..3   the pack and sleeves shifting
  mail_1..2    mail links, only while wearing metal armour
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "footsteps")
SR = 44100
SEED = 20260905
RNG = np.random.default_rng(SEED)

FAMILIES = ["grass", "dirt", "mud", "leaf", "gravel", "sand", "snow", "wood", "stone"]
VARIANTS = 3


# ------------------------------------------------------------------ helpers --
def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def noise(seconds):
    return RNG.standard_normal(int(SR * seconds)).astype(np.float64)


def lowpass(x, cutoff, order=2):
    from scipy.signal import lfilter
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


def thump(dur, f0, decay, bend=0.55):
    """A body thump: a sine that falls in pitch as it dies."""
    tt = t(dur)
    f = f0 * (bend + (1.0 - bend) * np.exp(-tt / max(decay, 1e-3)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_ad(len(tt), 0.002, decay)


def grains(dur, n_grains, lo, hi, spread, glen=(0.004, 0.014), amp=1.0):
    """A cluster of tiny impulses -- gravel, leaf litter, snow crust."""
    out = np.zeros(int(SR * dur))
    for _ in range(n_grains):
        at = int(abs(RNG.normal(0.0, spread)) * SR)
        ln = int(RNG.uniform(*glen) * SR)
        if at + ln >= len(out):
            continue
        g = band(RNG.standard_normal(ln), lo, hi)
        out[at:at + ln] += g * env_ad(ln, 0.001, RNG.uniform(0.002, 0.008)) \
            * RNG.uniform(0.3, 1.0) * amp
    return out


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
    print("  %-16s %5.2f s" % (name + ".wav", len(x) / SR))


# ------------------------------------------------------------------- voices --
# Each takes `hard` in 0..1 -- 0 is a crouched creep, 1 is a sprint or a
# landing. Harder means louder, brighter, and a deeper body.

def v_grass(dur, hard):
    n = noise(dur)
    brush = band(n, 600.0, 3600.0 + 1600.0 * hard) * env_ad(len(n), 0.006, 0.055 + 0.03 * hard)
    body = thump(dur, 150.0, 0.045) * 0.18 * hard
    return norm(brush + body, 0.55 + 0.3 * hard)


def v_dirt(dur, hard):
    n = noise(dur)
    scuff = band(n, 200.0, 2400.0) * env_ad(len(n), 0.003, 0.05 + 0.03 * hard)
    body = thump(dur, 88.0, 0.075 + 0.03 * hard) * (0.55 + 0.35 * hard)
    return norm(scuff * 0.8 + body, 0.6 + 0.28 * hard)


def v_mud(dur, hard):
    tt = t(dur)
    n = noise(dur)
    # the squelch: a resonant band that falls in pitch as the foot sinks
    f = 900.0 * np.exp(-tt / 0.10) + 180.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    squelch = np.sin(ph) * env_ad(len(tt), 0.010, 0.10) * 0.5
    wet = band(n, 250.0, 1700.0) * env_ad(len(n), 0.004, 0.085)
    # the suck as it comes back out, a beat later
    suck = np.zeros_like(tt)
    at = int(0.11 * SR)
    ln = len(tt) - at
    if ln > 0:
        fs = 260.0 * (1.0 + 1.6 * np.arange(ln) / ln)
        suck[at:] = np.sin(2 * np.pi * np.cumsum(fs) / SR) \
            * env_ad(ln, 0.02, 0.06) * 0.35 * (0.5 + 0.5 * hard)
    body = thump(dur, 75.0, 0.06) * 0.4 * hard
    return norm(squelch + wet + suck + body, 0.6 + 0.25 * hard)


def v_leaf(dur, hard):
    crackle = grains(dur, int(26 + 34 * hard), 1800.0, 9000.0, 0.045)
    bed = band(noise(dur), 1200.0, 7000.0) * env_ad(int(SR * dur), 0.004, 0.05) * 0.35
    body = thump(dur, 130.0, 0.04) * 0.14 * hard
    return norm(crackle + bed + body, 0.5 + 0.35 * hard)


def v_gravel(dur, hard):
    rattle = grains(dur, int(12 + 16 * hard), 900.0, 5800.0, 0.055, (0.005, 0.020))
    crush = band(noise(dur), 450.0, 3400.0) * env_ad(int(SR * dur), 0.002, 0.04)
    body = thump(dur, 105.0, 0.05) * 0.3 * hard
    return norm(rattle + crush * 0.7 + body, 0.6 + 0.28 * hard)


def v_sand(dur, hard):
    hiss = band(noise(dur), 2600.0, 9500.0) * env_ad(int(SR * dur), 0.012, 0.075 + 0.03 * hard)
    body = thump(dur, 70.0, 0.05) * 0.22 * hard
    return norm(hiss + body, 0.45 + 0.3 * hard)


def v_snow(dur, hard):
    crust = grains(dur, int(22 + 28 * hard), 1100.0, 5600.0, 0.028, (0.003, 0.010))
    compress = band(noise(dur), 300.0, 2200.0) * env_ad(int(SR * dur), 0.010, 0.075)
    body = thump(dur, 120.0, 0.055) * 0.3 * hard
    return norm(crust * 0.9 + compress * 0.6 + body, 0.55 + 0.3 * hard)


def v_wood(dur, hard):
    tt = t(dur)
    knock = np.zeros_like(tt)
    for f, a, d in ((178.0, 1.0, 0.12), (431.0, 0.55, 0.085), (905.0, 0.3, 0.05)):
        knock += np.sin(2 * np.pi * f * tt) * env_ad(len(tt), 0.0015, d) * a
    click = band(noise(dur), 1200.0, 5200.0) * env_ad(len(tt), 0.001, 0.018) * 0.5
    return norm(knock * (0.6 + 0.4 * hard) + click, 0.6 + 0.28 * hard)


def v_stone(dur, hard):
    tt = t(dur)
    click = band(noise(dur), 2200.0, 9500.0) * env_ad(len(tt), 0.0008, 0.016 + 0.01 * hard)
    body = np.sin(2 * np.pi * 245.0 * tt) * env_ad(len(tt), 0.001, 0.035) * 0.45
    tail = band(noise(dur), 900.0, 4200.0) * env_ad(len(tt), 0.020, 0.085) * 0.12 * hard
    return norm(click + body + tail, 0.55 + 0.32 * hard)


VOICES = {"grass": v_grass, "dirt": v_dirt, "mud": v_mud, "leaf": v_leaf,
          "gravel": v_gravel, "sand": v_sand, "snow": v_snow,
          "wood": v_wood, "stone": v_stone}
DUR = {"grass": 0.26, "dirt": 0.26, "mud": 0.34, "leaf": 0.28, "gravel": 0.30,
       "sand": 0.26, "snow": 0.28, "wood": 0.30, "stone": 0.26}


# -------------------------------------------------------------------- foley --
def cloth(k):
    dur = 0.16 + 0.03 * k
    n = noise(dur)
    w = band(n, 350.0, 3200.0) * env_ad(len(n), 0.018 + 0.006 * k, 0.045)
    return norm(w, 0.45)


def mail(k):
    dur = 0.22
    tt = t(dur)
    out = np.zeros_like(tt)
    for _ in range(9 + 4 * k):
        at = int(abs(RNG.normal(0.0, 0.030)) * SR)
        ln = int(RNG.uniform(0.006, 0.018) * SR)
        if at + ln >= len(out):
            continue
        f = RNG.uniform(3200.0, 7400.0)
        ring = np.sin(2 * np.pi * f * np.arange(ln) / SR)
        out[at:at + ln] += ring * env_ad(ln, 0.0006, 0.006) * RNG.uniform(0.3, 1.0)
    out += band(noise(dur), 1800.0, 6000.0) * env_ad(len(tt), 0.002, 0.030) * 0.3
    return norm(out, 0.5)


# --------------------------------------------------------------------- main --
def main():
    manifest = {}
    print("footsteps ->", os.path.normpath(OUT))
    for fam in FAMILIES:
        v, d = VOICES[fam], DUR[fam]
        for i in range(VARIANTS):
            hard = 0.32 + 0.16 * i           # three weights of the same foot
            write("%s_%d" % (fam, i + 1), v(d, hard), manifest)
        write("%s_land" % fam, v(d * 1.35, 1.0), manifest)
    for k in range(3):
        write("cloth_%d" % (k + 1), cloth(k), manifest)
    for k in range(2):
        write("mail_%d" % (k + 1), mail(k), manifest)
    json.dump({"generator": "tools/stepsounds.py", "version": 1, "seed": SEED,
               "sample_rate": SR, "families": FAMILIES, "variants": VARIANTS,
               "sounds": manifest},
              open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
    print("  manifest.json (%d sounds)" % len(manifest))


if __name__ == "__main__":
    main()
