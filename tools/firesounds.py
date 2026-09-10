#!/usr/bin/env python3
"""
firesounds.py -- synthesise the fire soundscape. No recordings, no licences.

    python3 tools/firesounds.py            # writes assets/audio/fire/

Same idea as watersounds.py (the water pack) and crittercalls.py (the wildlife
pack): every sound is oscillators and filtered noise, deterministic on SEED,
written as 44.1 kHz mono 16-bit WAV with a manifest.json that
scripts/FireAudio.gd reads. Loops are made seamless by cross-fading the tail
into the head.

A fire is three sounds stacked, and they are generated separately here because
FireAudio mixes them independently:

  the BED      the continuous roar. Filtered noise, amplitude-modulated by a
               slow LFO -- that swelling and dropping is what makes a fire
               sound like a fire and not like rain. Two sizes, because the
               difference between a hearth and a campfire is spectral, not
               just loud: the big bed is wider at BOTH ends (45-1650 Hz
               against 90-1150), swells harder and carries twice the grit.
  the CRACKLE  the transients. These are NOT baked into the bed, because the
               whole point of the round is that FireAudio fires them off the
               same flicker signal that drives the light, so the pop lands on
               the frame the flame brightens. Six of them, three sizes.
  the EMBERS   what is left at four in the morning. Almost nothing: a low hiss
               and the occasional tick of a coal settling.

The set:
  fire_bed_small  loop   a low flame, a hearth banked for the night
  fire_bed_big    loop   a fed campfire, roaring
  ember_bed       loop   coals, ticking
  crackle_1..6    shot   pops: two small, two mid, two big
  settle_1..3     shot   a log shifting and a shower of sparks
  catch           shot   the flame taking hold
  feed_log        shot   wood going on: a thud and a flare
  rain_hiss       loop   rain landing on an open flame -- the sound of your
                         fuel burning twice as fast
  douse           shot   the fire going out
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "fire")
SR = 44100
SEED = 20260910
RNG = np.random.default_rng(SEED)


# ------------------------------------------------------------------ helpers --
def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def noise(seconds, rng=RNG):
    return rng.standard_normal(int(SR * seconds)).astype(np.float64)


def lowpass(x, cutoff, order=2):
    """Cheap one-pole IIR run `order` times (6 dB/oct each)."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = x
    for _ in range(order):
        try:
            from scipy.signal import lfilter
            y = lfilter([1.0 - a], [1.0, -a], y)
        except Exception:
            out = np.empty_like(y)
            acc = 0.0
            b = 1.0 - a
            for i in range(y.size):
                acc = b * y[i] + a * acc
                out[i] = acc
            y = out
    return y


def highpass(x, cutoff, order=1):
    return x - lowpass(x, cutoff, order)


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def env_exp(n, tau):
    """Exponential decay envelope of n samples with time constant tau (s)."""
    return np.exp(-np.arange(n) / (SR * tau))


def fade(x, ms=6.0):
    """Kill the click at both ends of a one-shot."""
    k = max(2, int(SR * ms / 1000.0))
    k = min(k, x.size // 2)
    w = np.linspace(0.0, 1.0, k)
    x[:k] *= w
    x[-k:] *= w[::-1]
    return x


def loopify(x, cross=0.35):
    """Cross-fade the tail into the head so the loop point is inaudible."""
    k = int(SR * cross)
    if k * 2 >= x.size:
        return x
    head = x[:k].copy()
    tail = x[-k:].copy()
    w = np.linspace(0.0, 1.0, k)
    x = x[:-k]
    x[:k] = tail * (1.0 - w) + head * w
    return x


def norm(x, peak=0.92):
    m = float(np.max(np.abs(x))) if x.size else 0.0
    if m < 1e-9:
        return x
    return x * (peak / m)


def write_wav(name, x, seconds, loop):
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return {"file": name + ".wav", "seconds": round(seconds, 2), "loop": bool(loop)}


# -------------------------------------------------------------------- beds --
def fire_bed(seconds, low_cut, hi_cut, swell_hz, swell_depth, grit, rng):
    """A fire's roar: filtered noise breathing on a slow LFO, plus a scatter of
    small transients so the bed is never a flat wash."""
    n = int(SR * seconds)
    base = bandpass(noise(seconds, rng), low_cut, hi_cut, 3)
    base = norm(base, 1.0)
    # A little air on top so the roar is not a pillow. Kept quiet on purpose:
    # a fire is a low sound with sparkle in it, not a hiss with a rumble under.
    base += norm(bandpass(noise(seconds, rng), 3000.0, 8000.0, 2), 1.0) * 0.10

    # The breath. Three incommensurate LFOs so it never obviously repeats.
    tt = t(seconds)
    lfo = (
        0.55 * np.sin(2 * np.pi * swell_hz * tt)
        + 0.30 * np.sin(2 * np.pi * swell_hz * 1.71 * tt + 1.1)
        + 0.15 * np.sin(2 * np.pi * swell_hz * 0.43 * tt + 2.7)
    )
    base *= 1.0 - swell_depth + swell_depth * (0.5 + 0.5 * lfo)

    # The grit: little bursts riding inside the bed. Not the crackles proper --
    # those are fired by the game -- just enough texture that a still fire
    # is not silence with a hiss on top.
    for _ in range(grit):
        at = int(rng.integers(0, max(1, n - SR // 4)))
        dur = int(SR * float(rng.uniform(0.01, 0.05)))
        burst = bandpass(noise(dur / SR, rng), 900.0, 5200.0, 1)
        burst *= env_exp(burst.size, float(rng.uniform(0.004, 0.02)))
        g = float(rng.uniform(0.05, 0.22))
        base[at:at + burst.size] += burst[: max(0, n - at)] * g

    return norm(base, 0.86)


def ember_bed(seconds, rng):
    n = int(SR * seconds)
    base = lowpass(noise(seconds, rng), 300.0, 3)
    base = norm(base, 0.30)
    tt = t(seconds)
    base *= 0.72 + 0.28 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * tt))
    for _ in range(26):
        at = int(rng.integers(0, max(1, n - SR // 8)))
        dur = int(SR * float(rng.uniform(0.004, 0.016)))
        tick = bandpass(noise(dur / SR, rng), 1400.0, 6000.0, 1)
        tick *= env_exp(tick.size, 0.0035)
        base[at:at + tick.size] += tick[: max(0, n - at)] * float(rng.uniform(0.04, 0.16))
    return norm(base, 0.55)


# ---------------------------------------------------------------- crackles --
def crackle(size, rng):
    """A pop. `size` 0..2 -- a spit, a snap, a bang."""
    tau = [0.006, 0.014, 0.030][size]
    lo = [1600.0, 900.0, 420.0][size]
    hi = [7500.0, 5200.0, 3200.0][size]
    dur = [0.07, 0.14, 0.26][size]
    x = bandpass(noise(dur, rng), lo, hi, 2)
    x *= env_exp(x.size, tau)
    # The click at the front: a single half-cycle of a resonant tone. This is
    # what makes a pop read as WOOD rather than as a puff of static.
    tone_f = float(rng.uniform(180.0, 520.0)) * (1.0 + 0.6 * (2 - size))
    tone = np.sin(2 * np.pi * tone_f * t(dur)) * env_exp(x.size, tau * 0.7)
    x = x + tone * [0.18, 0.30, 0.45][size]
    # A big pop throws a couple of sparks after it.
    if size >= 1:
        for _ in range(int(rng.integers(1, 4))):
            at = int(SR * float(rng.uniform(0.02, dur * 0.7)))
            sp = bandpass(noise(0.012, rng), 2600.0, 9000.0, 1)
            sp *= env_exp(sp.size, 0.003)
            end = min(x.size, at + sp.size)
            x[at:end] += sp[: end - at] * float(rng.uniform(0.10, 0.30))
    # Fade FIRST, then normalise: a pop's peak lives in its first
    # millisecond, so normalising before the fade throws the attack away.
    return norm(fade(x, 0.8), 0.88), dur


def settle(rng):
    """A log shifting: two or three knocks and a shower of small stuff."""
    dur = float(rng.uniform(0.55, 0.9))
    x = np.zeros(int(SR * dur))
    for _ in range(int(rng.integers(2, 4))):
        at = int(SR * float(rng.uniform(0.0, dur * 0.5)))
        f0 = float(rng.uniform(150.0, 330.0))
        n = int(SR * 0.22)
        knock = np.sin(2 * np.pi * f0 * t(0.22)) * env_exp(n, 0.022)
        knock += np.sin(2 * np.pi * f0 * 2.7 * t(0.22)) * env_exp(n, 0.010) * 0.4
        end = min(x.size, at + n)
        x[at:end] += knock[: end - at] * float(rng.uniform(0.4, 0.8))
    for _ in range(int(rng.integers(6, 14))):
        at = int(SR * float(rng.uniform(0.0, dur * 0.92)))
        sp = bandpass(noise(0.02, rng), 1800.0, 8000.0, 1)
        sp *= env_exp(sp.size, 0.005)
        end = min(x.size, at + sp.size)
        x[at:end] += sp[: end - at] * float(rng.uniform(0.08, 0.28))
    return norm(fade(x, 1.5), 0.88), dur


# ------------------------------------------------------------- the one-offs --
def catch_sound(rng):
    """The flame taking hold: a rising whoosh that turns into a fire."""
    dur = 1.5
    n = int(SR * dur)
    tt = t(dur)
    x = np.zeros(n)
    # The whoosh: noise swept up through a filter by mixing two filtered copies.
    dark = lowpass(noise(dur, rng), 700.0, 2)
    bright = bandpass(noise(dur, rng), 900.0, 4800.0, 2)
    ramp = np.clip(tt / 0.55, 0.0, 1.0)
    x += norm(dark, 1.0) * (1.0 - ramp) * 0.7
    x += norm(bright, 1.0) * ramp * 0.9
    x *= np.clip(tt / 0.08, 0.0, 1.0) * (0.35 + 0.65 * np.exp(-np.maximum(0.0, tt - 0.6) / 0.7))
    for _ in range(9):
        at = int(SR * float(rng.uniform(0.15, dur * 0.9)))
        c, _d = crackle(int(rng.integers(0, 2)), rng)
        end = min(n, at + c.size)
        x[at:end] += c[: end - at] * float(rng.uniform(0.25, 0.6))
    return norm(fade(x, 8.0), 0.90), dur


def feed_log(rng):
    """Wood going on: the thud into the coals, then the flare."""
    dur = 1.1
    n = int(SR * dur)
    x = np.zeros(n)
    thud = np.sin(2 * np.pi * 96.0 * t(0.3)) * env_exp(int(SR * 0.3), 0.045)
    thud += np.sin(2 * np.pi * 152.0 * t(0.3)) * env_exp(int(SR * 0.3), 0.020) * 0.5
    thud += lowpass(noise(0.3, rng), 600.0, 1) * env_exp(int(SR * 0.3), 0.03) * 0.5
    x[: thud.size] += norm(thud, 0.9)
    flare = bandpass(noise(dur, rng), 500.0, 5000.0, 2)
    tt = t(dur)
    flare *= np.clip((tt - 0.12) / 0.18, 0.0, 1.0) * np.exp(-np.maximum(0.0, tt - 0.35) / 0.4)
    x += norm(flare, 0.55)
    for _ in range(6):
        at = int(SR * float(rng.uniform(0.2, 0.95)))
        c, _d = crackle(int(rng.integers(1, 3)), rng)
        end = min(n, at + c.size)
        x[at:end] += c[: end - at] * float(rng.uniform(0.3, 0.7))
    return norm(fade(x, 2.0), 0.92), dur


def rain_hiss(seconds, rng):
    """Rain landing on an open flame. This is the sound of RAIN_BURN_MULT: if
    you can hear it, your wood is going twice as fast and a roof is the fix."""
    x = bandpass(noise(seconds, rng), 2200.0, 9000.0, 2)
    x = norm(x, 0.45)
    n = x.size
    for _ in range(int(seconds * 26)):
        at = int(rng.integers(0, max(1, n - SR // 20)))
        dur = float(rng.uniform(0.008, 0.03))
        spit = bandpass(noise(dur, rng), 1200.0, 7000.0, 1)
        spit *= env_exp(spit.size, float(rng.uniform(0.002, 0.008)))
        end = min(n, at + spit.size)
        x[at:end] += spit[: end - at] * float(rng.uniform(0.15, 0.5))
    return norm(x, 0.8)


def douse(rng):
    """Out. A big hiss with the top falling off it."""
    dur = 1.8
    n = int(SR * dur)
    tt = t(dur)
    bright = bandpass(noise(dur, rng), 1800.0, 9500.0, 2)
    dark = lowpass(noise(dur, rng), 900.0, 2)
    ramp = np.clip(tt / 1.1, 0.0, 1.0)
    x = norm(bright, 1.0) * (1.0 - ramp) + norm(dark, 1.0) * ramp * 0.6
    x *= np.clip(tt / 0.03, 0.0, 1.0) * np.exp(-tt / 0.75)
    return norm(fade(x, 6.0), 0.88), dur


# --------------------------------------------------------------------- main --
def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)
    sounds = {}

    small_s, big_s, ember_s, rain_s = 6.5, 8.5, 7.0, 5.5
    small = loopify(fire_bed(small_s, 90.0, 1150.0, 0.31, 0.34, 40, rng))
    sounds["fire_bed_small"] = write_wav("fire_bed_small", small, small.size / SR, True)

    big = loopify(fire_bed(big_s, 45.0, 1650.0, 0.24, 0.42, 95, rng))
    sounds["fire_bed_big"] = write_wav("fire_bed_big", big, big.size / SR, True)

    emb = loopify(ember_bed(ember_s, rng))
    sounds["ember_bed"] = write_wav("ember_bed", emb, emb.size / SR, True)

    hiss = loopify(rain_hiss(rain_s, rng))
    sounds["rain_hiss"] = write_wav("rain_hiss", hiss, hiss.size / SR, True)

    for i in range(6):
        x, d = crackle(i // 2, rng)
        sounds["crackle_%d" % (i + 1)] = write_wav("crackle_%d" % (i + 1), x, d, False)

    for i in range(3):
        x, d = settle(rng)
        sounds["settle_%d" % (i + 1)] = write_wav("settle_%d" % (i + 1), x, d, False)

    x, d = catch_sound(rng)
    sounds["catch"] = write_wav("catch", x, d, False)
    x, d = feed_log(rng)
    sounds["feed_log"] = write_wav("feed_log", x, d, False)
    x, d = douse(rng)
    sounds["douse"] = write_wav("douse", x, d, False)

    manifest = {
        "generator": "tools/firesounds.py",
        "version": 1,
        "seed": SEED,
        "sample_rate": SR,
        "sounds": sounds,
    }
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)

    total = sum(os.path.getsize(os.path.join(OUT, s["file"])) for s in sounds.values())
    print("firesounds: %d files, %.0f KB -> %s" % (len(sounds), total / 1024.0, OUT))
    for k in sorted(sounds):
        s = sounds[k]
        print("  %-16s %5.2fs %s" % (k, s["seconds"], "loop" if s["loop"] else ""))


if __name__ == "__main__":
    main()
