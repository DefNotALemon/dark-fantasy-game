#!/usr/bin/env python3
"""
watersounds.py -- synthesise the water soundscape. No recordings, no licences.

    python3 tools/watersounds.py            # writes assets/audio/water/

Same idea as crittercalls.py (the wildlife pack): every sound is oscillators
and filtered noise, deterministic on SEED, written as 44.1 kHz mono 16-bit WAV
with a manifest.json that scripts/WaterAudio.gd reads. Loops are made
seamless by cross-fading the tail into the head.

The set:
  lake_lap        loop   slow lapping on a still shore (tannin lake, no surf)
  sea_surf        loop   the Gulf: swells every 8-12 s, hiss on the break
  underwater_bed  loop   the pressure hum you hear with your ears under
  swim_stroke_1-3 shot   one arm pulling through
  splash_in       shot   a body going in
  splash_out      shot   climbing out, dripping
  gulp            shot   drinking, three swallows
  fill_skin       shot   a waterskin filling (gurgle + rising pitch)
  bubbles         shot   a breath escaping (the Drowned's tell)
  snapper_hiss    shot   the kettle-with-legs
  drowned_rise    shot   something dead coming up under you
  drowned_grip    shot   the hand closing (wet slap + low thud)
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "water")
SR = 44100
SEED = 20260901
RNG = np.random.default_rng(SEED)


# ------------------------------------------------------------------ helpers --
def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def noise(seconds, rng=RNG):
    return rng.standard_normal(int(SR * seconds)).astype(np.float64)


def lowpass(x, cutoff, order=2):
    """Cheap one-pole IIR run `order` times (6 dB/oct each)."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = x.copy()
    for _ in range(order):
        out = np.empty_like(y)
        acc = 0.0
        b = 1.0 - a
        for i in range(len(y)):
            acc = a * acc + b * y[i]
            out[i] = acc
        y = out
    return y


def lowpass_fast(x, cutoff, order=2):
    """Vectorised one-pole via scipy if present, else the loop."""
    try:
        from scipy.signal import lfilter
        a = np.exp(-2.0 * np.pi * cutoff / SR)
        y = x
        for _ in range(order):
            y = lfilter([1.0 - a], [1.0, -a], y)
        return y
    except Exception:
        return lowpass(x, cutoff, order)


def highpass(x, cutoff, order=1):
    return x - lowpass_fast(x, cutoff, order)


def band(x, lo, hi, order=2):
    return highpass(lowpass_fast(x, hi, order), lo, order)


def env_ad(n, attack, decay, curve=2.0):
    """Attack-decay envelope in samples."""
    e = np.zeros(n)
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0.0, 1.0, a) ** (1.0 / curve)
    d = np.arange(n - a) / SR
    e[a:] = np.exp(-d / max(decay, 1e-3))
    return e


def seamless(x, fade=0.5):
    """Cross-fade the tail into the head so the loop has no seam."""
    n = int(fade * SR)
    if n * 2 >= len(x):
        return x
    ramp = np.linspace(0.0, 1.0, n)
    head = x[:n] * ramp + x[-n:] * (1.0 - ramp)
    return np.concatenate([head, x[n:-n]])


def norm(x, peak=0.85):
    m = float(np.max(np.abs(x))) or 1.0
    return x / m * peak


def write(name, x, loop, manifest):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767.0).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    manifest[name] = {"file": name + ".wav", "seconds": round(len(x) / SR, 3), "loop": loop}
    print(f"  {name:16s} {len(x) / SR:5.2f} s {'loop' if loop else ''}")


# ------------------------------------------------------------------- sounds --
def lake_lap():
    dur = 10.0
    tt = t(dur)
    n = noise(dur)
    # a still lake: soft wash, 0.4-0.7 Hz swells, mostly 150-1800 Hz
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * 0.43 * tt) * np.sin(2 * np.pi * 0.61 * tt + 1.3)
    wash = band(n, 150.0, 1800.0) * (0.35 + 0.65 * swell ** 2)
    # little plips: droplets slapping stone, a few a second
    plips = np.zeros_like(tt)
    for _ in range(int(dur * 2.5)):
        at = int(RNG.uniform(0, dur - 0.2) * SR)
        f = RNG.uniform(900, 2600)
        ln = int(0.09 * SR)
        e = env_ad(ln, 0.002, 0.03)
        plips[at:at + ln] += np.sin(2 * np.pi * f * np.arange(ln) / SR * (1.0 - 0.4 * np.arange(ln) / ln)) * e * RNG.uniform(0.15, 0.4)
    return seamless(norm(wash * 0.7 + plips, 0.6), 0.8)


def sea_surf():
    dur = 14.0
    tt = t(dur)
    n = noise(dur)
    # swells arriving every ~9 s (two detuned so it never quite repeats)
    swell = np.clip(np.sin(2 * np.pi * tt / 9.0) * 0.6 + np.sin(2 * np.pi * tt / 11.3 + 0.7) * 0.4, 0.0, 1.0) ** 1.6
    body = band(n, 60.0, 900.0) * (0.3 + 0.7 * swell)
    hiss = band(n, 1500.0, 7000.0) * np.roll(swell, int(0.6 * SR)) ** 2 * 0.6   # the break hisses after the swell
    return seamless(norm(body + hiss, 0.75), 1.2)


def underwater_bed():
    dur = 8.0
    tt = t(dur)
    n = noise(dur)
    hum = band(n, 30.0, 220.0) * 0.7
    gurgle = (0.6 + 0.4 * np.sin(2 * np.pi * 0.17 * tt) * np.sin(2 * np.pi * 0.29 * tt + 2.0))
    thrum = np.sin(2 * np.pi * 48.0 * tt) * 0.12 * gurgle
    return seamless(norm(hum * gurgle + thrum, 0.5), 1.0)


def stroke(k):
    dur = 0.75
    n = noise(dur)
    e = env_ad(len(n), 0.03 + 0.01 * k, 0.18)
    splash = band(n, 500.0, 5000.0) * e
    whump = band(n, 60.0, 250.0) * env_ad(len(n), 0.01, 0.10) * 0.8
    return norm(splash + whump, 0.7)


def splash_in():
    dur = 1.3
    n = noise(dur)
    thud = band(n, 40.0, 200.0) * env_ad(len(n), 0.004, 0.16) * 1.2
    crown = band(n, 400.0, 6000.0) * env_ad(len(n), 0.01, 0.35)
    rain = band(noise(dur), 1500.0, 8000.0) * env_ad(len(n), 0.25, 0.4) * 0.5   # the fall-back
    return norm(thud + crown + rain, 0.9)


def splash_out():
    dur = 1.0
    n = noise(dur)
    sheet = band(n, 300.0, 4000.0) * env_ad(len(n), 0.02, 0.25) * 0.8
    drips = np.zeros_like(n)
    for _ in range(9):
        at = int(RNG.uniform(0.15, 0.85) * SR)
        f = RNG.uniform(1200, 3200)
        ln = int(0.07 * SR)
        drips[at:at + ln] += np.sin(2 * np.pi * f * np.arange(ln) / SR) * env_ad(ln, 0.002, 0.025) * 0.35
    return norm(sheet + drips, 0.7)


def gulp():
    dur = 0.9
    tt = t(dur)
    out = np.zeros_like(tt)
    for k in range(3):
        at = int((0.05 + k * 0.28) * SR)
        ln = int(0.16 * SR)
        f0 = 140.0 - 20.0 * k
        seg = np.sin(2 * np.pi * f0 * np.arange(ln) / SR * (1.0 + 0.6 * np.arange(ln) / ln)) * env_ad(ln, 0.01, 0.05)
        out[at:at + ln] += seg * 0.6
        out[at:at + ln] += band(noise(ln / SR), 200.0, 1200.0) * env_ad(ln, 0.005, 0.04) * 0.3
    return norm(out, 0.65)


def fill_skin():
    dur = 1.8
    tt = t(dur)
    f = 260.0 + 340.0 * (tt / dur) ** 1.5          # the pitch climbs as it fills
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25
    glug = band(noise(dur), 150.0, 900.0) * (0.5 + 0.5 * np.sin(2 * np.pi * 7.0 * tt)) * 0.7
    e = env_ad(len(tt), 0.05, 1.2)
    return norm((tone + glug) * e, 0.6)


def bubbles():
    dur = 1.4
    tt = t(dur)
    out = np.zeros_like(tt)
    for _ in range(14):
        at = int(RNG.uniform(0.0, dur - 0.12) * SR)
        ln = int(RNG.uniform(0.04, 0.11) * SR)
        f0 = RNG.uniform(300, 900)
        ph = 2 * np.pi * np.cumsum(f0 * (1.0 + 1.2 * np.arange(ln) / ln)) / SR
        out[at:at + ln] += np.sin(ph) * env_ad(ln, 0.003, 0.03) * RNG.uniform(0.2, 0.5)
    return norm(out, 0.55)


def snapper_hiss():
    dur = 1.0
    n = noise(dur)
    e = env_ad(len(n), 0.08, 0.45)
    return norm(band(n, 1800.0, 6500.0) * e, 0.6)


def drowned_rise():
    dur = 2.8
    tt = t(dur)
    # a groan: three detuned lows, swelling, with a slow wobble
    groan = sum(np.sin(2 * np.pi * f * tt + p) for f, p in ((58.0, 0.0), (61.5, 1.1), (87.0, 2.3))) / 3.0
    groan *= (0.4 + 0.6 * np.sin(2 * np.pi * 1.7 * tt) ** 2) * env_ad(len(tt), 1.1, 1.0)
    # water folding over it
    swell = band(noise(dur), 120.0, 1200.0) * env_ad(len(tt), 0.9, 0.9) * 0.7
    # bubbles escaping ahead of it
    bub = np.zeros_like(tt)
    for _ in range(16):
        at = int(RNG.uniform(0.0, 1.6) * SR)
        ln = int(RNG.uniform(0.04, 0.09) * SR)
        f0 = RNG.uniform(250, 700)
        ph = 2 * np.pi * np.cumsum(f0 * (1.0 + 1.0 * np.arange(ln) / ln)) / SR
        bub[at:at + ln] += np.sin(ph) * env_ad(ln, 0.003, 0.03) * 0.35
    return norm(groan * 0.9 + swell + bub, 0.85)


def drowned_grip():
    dur = 0.7
    n = noise(dur)
    slap = band(n, 300.0, 3000.0) * env_ad(len(n), 0.003, 0.08)
    thud = band(n, 40.0, 160.0) * env_ad(len(n), 0.006, 0.25) * 1.3
    return norm(slap + thud, 0.85)


# --------------------------------------------------------------------- main --
def main():
    manifest = {}
    print("water sounds ->", os.path.normpath(OUT))
    write("lake_lap", lake_lap(), True, manifest)
    write("sea_surf", sea_surf(), True, manifest)
    write("underwater_bed", underwater_bed(), True, manifest)
    for k in range(3):
        write(f"swim_stroke_{k + 1}", stroke(k), False, manifest)
    write("splash_in", splash_in(), False, manifest)
    write("splash_out", splash_out(), False, manifest)
    write("gulp", gulp(), False, manifest)
    write("fill_skin", fill_skin(), False, manifest)
    write("bubbles", bubbles(), False, manifest)
    write("snapper_hiss", snapper_hiss(), False, manifest)
    write("drowned_rise", drowned_rise(), False, manifest)
    write("drowned_grip", drowned_grip(), False, manifest)
    json.dump({"generator": "tools/watersounds.py", "version": 1, "seed": SEED,
               "sample_rate": SR, "sounds": manifest},
              open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
    print(f"  manifest.json ({len(manifest)} sounds)")


if __name__ == "__main__":
    main()
