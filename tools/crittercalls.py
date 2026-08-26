#!/usr/bin/env python3
"""
crittercalls.py — procedural Maine wildlife audio for Myrkfell.

Same spirit as tools/leafgen.py and tools/barkgen.py: everything is generated,
nothing is downloaded, `--seed` makes it reproducible and diff-clean.

    python3 tools/crittercalls.py --out assets/audio/wildlife

Output: 16-bit mono PCM WAV @ 22050 Hz, one `<key>.wav` per call, plus a
`manifest.json` the Godot side reads to know what it has.

Needs only numpy + the stdlib `wave` module. No scipy, no audio libraries,
no network. Every sound below is built out of oscillators, noise and envelopes.

DESIGN NOTES (read before tuning)

  * Shape beats timbre. A loon wail is recognisable from its pitch contour
    alone; the harmonic content is decoration. Every builder therefore starts
    from a `glide()` breakpoint list, and that list is the thing worth editing.

  * Animal voices are ROUGH. A perfectly steady oscillator reads as a synth
    beep no matter how good the spectrum is. Three things fix that and they are
    used everywhere: `jitter` (pitch instability), `sub`/`chaos` (period
    doubling — the biological "creak" of a strained voice), and `formant()`
    (fixed resonant peaks, which is what makes noise read as a THROAT).

  * Beds loop by construction, not by luck. Event beds (peepers, crickets) wrap
    their events with modular indexing; the tonal bed (blackflies) uses
    modulators with an integer number of cycles per loop plus `loopify_phase()`.
    Both are sample-exact seamless, so they get no fade — a fade would put an
    audible dip at every wrap. Non-loop files all get a 5–15 ms fade.

  * Nyquist is 11025 Hz, which is low. `stack()` gates each harmonic out as it
    approaches the limit, so a 4 kHz chickadee does not alias into a whistle.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import wave
import zlib

import numpy as np

SR = 22050                 # game ambience: small files matter more than fidelity
NYQ = SR * 0.5
DEFAULT_SEED = 7717
DEFAULT_OUT = "assets/audio/wildlife"


# --------------------------------------------------------------------------
# 1. core: time bases, breakpoints, envelopes, noise
# --------------------------------------------------------------------------

def nsamp(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def taxis(dur: float) -> np.ndarray:
    return np.arange(nsamp(dur), dtype=np.float64) / SR


def _breakpoints(points, dur, log=False):
    """Piecewise interpolation over a (time, value[, curve]) breakpoint list.

    `curve` applies to the segment ARRIVING at that point: 1.0 linear,
    >1 hangs back then rushes, <1 leaps then eases. Held flat outside the
    first/last breakpoint. With log=True the interpolation happens in
    log-frequency, which is how pitch actually behaves.
    """
    t = taxis(dur)
    pts = [(float(p[0]), float(p[1]), (float(p[2]) if len(p) > 2 else 1.0)) for p in points]
    pts.sort(key=lambda p: p[0])
    out = np.empty_like(t)

    if len(pts) == 1:
        out[:] = pts[0][1]
        return out

    def enc(v):
        return math.log(max(v, 1e-9)) if log else v

    def dec(v):
        return math.exp(v) if log else v

    out[:] = enc(pts[0][1])
    # before the first point / after the last: hold
    out[t <= pts[0][0]] = enc(pts[0][1])
    out[t >= pts[-1][0]] = enc(pts[-1][1])

    for i in range(len(pts) - 1):
        t0, v0, _ = pts[i]
        t1, v1, curve = pts[i + 1]
        if t1 <= t0:
            continue
        m = (t >= t0) & (t < t1)
        if not m.any():
            continue
        u = (t[m] - t0) / (t1 - t0)
        if curve != 1.0:
            u = np.power(u, curve)
        out[m] = enc(v0) * (1.0 - u) + enc(v1) * u

    return np.exp(out) if log else out


def glide(points, dur):
    """Pitch contour in Hz from breakpoints, interpolated in log-frequency."""
    return _breakpoints(points, dur, log=True)


def env(points, dur):
    """Amplitude envelope from breakpoints (linear). ADSR is just 4 points."""
    return _breakpoints(points, dur, log=False)


def noise(dur, kind="white", rng=None):
    """White / pink / brown noise. Pink and brown are shaped in the FFT domain."""
    rng = rng or np.random.default_rng(0)
    n = nsamp(dur)
    w = rng.standard_normal(n)
    if kind == "white":
        return w
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if len(f) > 1 else 1.0
    if kind == "pink":
        spec *= 1.0 / np.sqrt(f)
    elif kind == "brown":
        spec *= 1.0 / f
    else:
        raise ValueError(f"unknown noise kind {kind!r}")
    spec[0] = 0.0
    out = np.fft.irfft(spec, n)
    return out / (np.max(np.abs(out)) + 1e-12)


def smooth_noise(n, rate_hz, rng, octaves=1):
    """Band-limited random drift, smoothstep-interpolated between control points.

    This is the workhorse behind every `jitter` / `drift` argument. C1
    continuous, so it never puts a corner (audible as a tick) into a pitch line.
    """
    out = np.zeros(n)
    amp, rate, norm = 1.0, float(rate_hz), 0.0
    for _ in range(max(1, octaves)):
        step = SR / max(rate, 0.01)
        m = int(np.ceil(n / step)) + 3
        v = rng.standard_normal(m)
        xi = np.arange(n) / step
        i0 = np.clip(np.floor(xi).astype(np.int64), 0, m - 2)
        fr = xi - i0
        s = fr * fr * (3.0 - 2.0 * fr)
        out += amp * (v[i0] * (1.0 - s) + v[i0 + 1] * s)
        norm += amp
        amp *= 0.5
        rate *= 2.0
    return out / max(norm, 1e-9)


def sample_hold(n, rate_hz, rng, streams=1):
    """Stepped random — no interpolation. Chaotic burble (turkey gobble).

    `rate_hz` may be an array, so the step rate itself can accelerate. Asking
    for several `streams` returns that many value sequences sharing the SAME
    step boundaries, which is what keeps a gobble coherent: pitch and loudness
    have to jump on the same instant or it stops sounding like one bird.
    """
    r = np.broadcast_to(np.atleast_1d(np.asarray(rate_hz, dtype=float)), (n,)) \
        if np.ndim(rate_hz) else np.full(n, float(rate_hz))
    idx = np.floor(np.cumsum(np.maximum(r, 0.01)) / SR).astype(np.int64)
    m = int(idx[-1]) + 2
    out = [rng.standard_normal(m)[np.clip(idx, 0, m - 1)] for _ in range(streams)]
    return out[0] if streams == 1 else out


# --------------------------------------------------------------------------
# 2. filters — pure numpy, FFT masks and blockwise-recursive delay lines
# --------------------------------------------------------------------------

def _fft_apply(x, mask_fn):
    n = len(x)
    if n < 8:
        return x.copy()
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec *= mask_fn(f)
    return np.fft.irfft(spec, n)


def _skirt(f, lo, hi, edge_oct):
    """Raised-cosine band mask, skirts measured in octaves (log-frequency)."""
    fs = np.maximum(f, 1e-6)
    m = np.ones_like(fs)
    if lo and lo > 0:
        lo_lo = lo * (2.0 ** -edge_oct)
        u = np.clip((np.log2(fs) - np.log2(lo_lo)) / max(edge_oct, 1e-6), 0.0, 1.0)
        m *= 0.5 - 0.5 * np.cos(np.pi * u)
    if hi and hi < NYQ:
        hi_hi = hi * (2.0 ** edge_oct)
        u = np.clip((np.log2(hi_hi) - np.log2(fs)) / max(edge_oct, 1e-6), 0.0, 1.0)
        m *= 0.5 - 0.5 * np.cos(np.pi * u)
    m[fs <= 1e-5] = 0.0
    return m


def bandpass(x, lo=0.0, hi=None, edge_oct=0.35):
    """Zero-phase band shaping via an FFT mask.

    lo=0 gives a lowpass, hi=None a highpass. Zero-phase means symmetric
    pre-ringing, which is inaudible on sustained material — so percussive hits
    (thumps, slaps, wood clicks) are synthesised pre-shaped instead of filtered.
    """
    hi = NYQ if hi is None else min(hi, NYQ)
    return _fft_apply(x, lambda f: _skirt(f, lo, hi, edge_oct))


def _reso_mag(f, fc, q, gain):
    """Magnitude of one resonant peak (the classic 1/sqrt(1+Q^2(w/w0-w0/w)^2))."""
    fs = np.maximum(f, 1e-6)
    r = fs / fc - fc / fs
    return gain / np.sqrt(1.0 + (q * r) ** 2)


def formant(x, peaks, dry=0.0):
    """A few resonant peaks in parallel. `peaks` = [(fc, Q, gain), ...].

    This is the single highest-value function in the file: fixed resonances are
    what make a noise burst read as a THROAT rather than as a hiss, and what
    separates a raven from a crow when both are the same rough source.
    """
    def mask(f):
        m = np.zeros_like(f)
        for fc, q, g in peaks:
            m += _reso_mag(f, fc, q, g)
        return m + dry
    return _fft_apply(x, mask)


def sweep_bandpass(x, fc, q=6.0, win=256, gain=1.0):
    """Time-VARYING resonant bandpass, STFT overlap-add.

    `fc` is a per-sample centre-frequency array (or a scalar). Hann analysis
    window at 50% hop is COLA-unity, so no synthesis window or normalisation
    pass is needed. Used wherever a filter has to chase a pitch line: the
    deer-snort wheeze, the fisher's rasp, the woodcock peent.
    """
    n = len(x)
    if n < win * 2:
        fcm = float(np.mean(np.atleast_1d(fc)))
        return formant(x, [(fcm, q, 1.0)]) * gain
    hop = win // 2
    w = np.hanning(win + 1)[:win]
    fa = np.atleast_1d(np.asarray(fc, dtype=float))
    if fa.size == 1:
        fc_arr = np.full(n, float(fa[0]))
    elif fa.size == n:
        fc_arr = fa
    else:
        fc_arr = np.interp(np.linspace(0.0, 1.0, n), np.linspace(0.0, 1.0, fa.size), fa)
    pad = win
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + win)])
    out = np.zeros_like(xp)
    f = np.fft.rfftfreq(win, 1.0 / SR)
    for start in range(0, len(xp) - win, hop):
        centre = start + hop - pad
        c = fc_arr[min(max(centre, 0), n - 1)]
        seg = xp[start:start + win] * w
        spec = np.fft.rfft(seg)
        spec *= _reso_mag(f, max(c, 20.0), q, 1.0)
        out[start:start + win] += np.fft.irfft(spec, win)
    return out[pad:pad + n] * gain


def _delay_feedback(x, D, g):
    """y[n] = x[n] + g*y[n-D], computed a delay-block at a time.

    Within any block of D samples the source indices are already final, so this
    is exact — and it costs len(x)/D numpy ops instead of len(x) python ones.
    """
    D = max(1, int(D))
    y = x.astype(np.float64).copy()
    n = len(y)
    i = D
    while i < n:
        j = min(i + D, n)
        y[i:j] += g * y[i - D:i - D + (j - i)]
        i = j
    return y


def _allpass(x, D, g):
    D = max(1, int(D))
    n = len(x)
    xd = np.concatenate([np.zeros(D), x])[:n]
    y = xd - g * x
    y = _delay_feedback(y, D, g)
    return y


# Comb / allpass delays in MILLISECONDS (not samples) so they mean the same
# thing at any sample rate. Ratios are near-prime to keep repeats from piling up.
_COMB_MS = (19.7, 22.3, 24.1, 26.9, 29.7, 31.9, 34.3, 37.1)
_DIFFUSE_MS = (4.7, 7.3, 10.9)
_POST_MS = (12.6, 9.7, 7.1)


def reverb(x, amount=0.25, taps=None, size=1.0, decay=0.55, damp_hz=3200,
           predelay=0.012, tail=True, tail_s=1.2):
    """Outdoor space: discrete early reflections + a diffuse tail.

    Outdoors, discrete slap-back matters more than density — a loon carries
    because you hear the far shore answer it — so `taps` is the expressive
    control and the comb tail fills the gaps behind them.

    The tail runs the source through three short allpasses BEFORE the comb
    bank. Without that pre-diffusion each comb returns its input as a clean
    delayed copy, and on percussive material that is not a reverb tail, it is a
    flam: the grouse drum came back as 48 double-hits, one echo per thump ~67 ms
    late. Smearing the impulse first is what turns echoes into a tail.
    """
    n = len(x)
    pad = nsamp(tail_s)
    xp = np.concatenate([x, np.zeros(pad)])
    wet = np.zeros_like(xp)

    pd = nsamp(predelay)
    src = np.concatenate([np.zeros(pd), xp])[:len(xp)]

    if taps:
        for dt, g in taps:
            d = nsamp(dt)
            if d >= len(xp):
                continue
            t = np.concatenate([np.zeros(d), src])[:len(xp)]
            # each bounce loses more high end than the last
            wet += g * bandpass(t, 0, max(700.0, damp_hz * (g ** 0.35)))

    if tail:
        dif = src
        for ms in _DIFFUSE_MS:
            dif = _allpass(dif, nsamp(ms * size / 1000.0), 0.7)
        acc = np.zeros_like(xp)
        for ms in _COMB_MS:
            acc += _delay_feedback(dif, nsamp(ms * size / 1000.0), decay) / len(_COMB_MS)
        for ms in _POST_MS:
            acc = _allpass(acc, nsamp(ms * size / 1000.0), 0.5)
        wet += bandpass(acc, 0, damp_hz) * 0.6

    return xp + amount * wet


def place(x, dist_m, rng=None, amount_rev=None, ref=8.0):
    """Distance model: attenuate, roll off air-absorbed highs, delay, blur.

    Attenuation is (ref/d)**0.8 rather than true 1/d — game audio needs a
    compressed range or the far end of a goose skein disappears entirely.
    """
    d = max(0.5, float(dist_m))
    g = (ref / max(ref, d)) ** 0.8
    fc = max(700.0, 10500.0 * math.exp(-d / 150.0))
    y = bandpass(x, 0, fc) * g
    if amount_rev is None:
        amount_rev = min(0.55, 0.05 + d / 320.0)
    if amount_rev > 0.01:
        y = reverb(y, amount=amount_rev, size=1.4, decay=0.6, damp_hz=2200, tail_s=0.9)
    dly = nsamp(d / 343.0)
    return np.concatenate([np.zeros(dly), y])


# --------------------------------------------------------------------------
# 3. sources — the larynx
# --------------------------------------------------------------------------

def phasor(freq, dur, rng=None, vib_hz=0.0, vib_depth=0.0, vib_delay=0.0,
           jitter=0.0, jitter_hz=9.0, drift=None):
    """Instantaneous phase + frequency for a (possibly gliding) voice."""
    n = nsamp(dur)
    t = np.arange(n) / SR
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)).astype(np.float64).copy() \
        if np.ndim(freq) else np.full(n, float(freq))
    mod = np.ones(n)
    if vib_depth > 0 and vib_hz > 0:
        ramp = np.clip((t - vib_delay) / max(vib_delay, 0.12), 0.0, 1.0) if vib_delay > 0 else 1.0
        ph0 = (rng.random() * 2 * np.pi) if rng is not None else 0.0
        mod *= 1.0 + vib_depth * ramp * np.sin(2 * np.pi * vib_hz * t + ph0)
    if jitter > 0 and rng is not None:
        mod *= 1.0 + jitter * smooth_noise(n, jitter_hz, rng, octaves=2)
    if drift is not None:
        mod *= 1.0 + drift
    inst = np.maximum(f * mod, 1.0)
    ph = 2 * np.pi * np.cumsum(inst) / SR
    return ph, inst


def stack(ph, inst, spectrum, ratios=None, rng=None):
    """Sum a harmonic series off ONE phase signal, gating anything near Nyquist.

    Sharing the phase is what lets `sub`/period-doubling sound like a voice
    cracking rather than like two unrelated oscillators.
    """
    out = np.zeros_like(ph)
    ratios = ratios if ratios is not None else [k + 1 for k in range(len(spectrum))]
    for a, r in zip(spectrum, ratios):
        if a == 0.0:
            continue
        gate = np.clip((NYQ * 0.94 - r * inst) / (0.05 * SR), 0.0, 1.0)
        if np.max(gate) <= 0.0:
            continue
        phi = (rng.random() * 2 * np.pi) if rng is not None else 0.0
        out += a * gate * np.sin(r * ph + phi)
    return out


def tone(freq, dur, spectrum=(1.0,), rng=None, vib_hz=0.0, vib_depth=0.0,
         vib_delay=0.0, jitter=0.0, jitter_hz=9.0, drift=None, ratios=None):
    """A pitched voice with vibrato, drift and a harmonic stack."""
    ph, inst = phasor(freq, dur, rng, vib_hz, vib_depth, vib_delay, jitter, jitter_hz, drift)
    return stack(ph, inst, spectrum, ratios)


def voice(freq, dur, rng, spectrum=None, jitter=0.03, jitter_hz=11.0, sub=0.0,
          chaos=0.0, chaos_hz=7.0, vib_hz=0.0, vib_depth=0.0, vib_delay=0.0,
          breath=0.0, breath_band=(400.0, 3000.0)):
    """An animal larynx: harmonics + pitch instability + period doubling + breath.

    `sub` adds a phase-locked half-frequency component — the mechanism behind a
    rough, creaky, strained voice. `chaos` makes that component flicker in and
    out, which is what a distressed animal actually does and what makes the
    fisher scream unpleasant rather than merely loud.
    """
    spectrum = spectrum if spectrum is not None else SPEC_VOICE
    ph, inst = phasor(freq, dur, rng, vib_hz, vib_depth, vib_delay, jitter, jitter_hz)
    out = stack(ph, inst, spectrum, rng=None)
    if sub > 0.0:
        g = 1.0
        if chaos > 0.0:
            n = len(ph)
            flick = smooth_noise(n, chaos_hz, rng, octaves=2)
            g = np.clip(0.5 + 1.6 * flick, 0.0, 1.0) * chaos + (1.0 - chaos)
        out += sub * g * (np.sin(0.5 * ph) + 0.45 * np.sin(1.5 * ph))
    if breath > 0.0:
        nz = noise(dur, "white", rng)
        nz = bandpass(nz, breath_band[0], breath_band[1])
        out += breath * nz * (0.6 + 0.4 * np.abs(out) / (np.max(np.abs(out)) + 1e-9))
    return out


def saw_spec(n, tilt=1.0, start=1):
    """Harmonic amplitudes ~1/k**tilt. tilt=1 sawtooth, lower = harsher/brighter."""
    return [1.0 / (k ** tilt) for k in range(start, start + n)]


SPEC_PURE = (1.0, 0.05, 0.015)
SPEC_FLUTE = (1.0, 0.16, 0.05, 0.015)
SPEC_SOFT = (1.0, 0.22, 0.07, 0.03)
SPEC_VOICE = (1.0, 0.55, 0.34, 0.22, 0.15, 0.10, 0.07, 0.05)
SPEC_HARSH = tuple(saw_spec(14, 0.72))
SPEC_NASAL = (0.55, 1.0, 0.85, 0.6, 0.45, 0.3, 0.22, 0.15, 0.1)


def damped_sine(f0, dur, decay_s, rng=None, f_end=None, spectrum=(1.0,),
                decay_scale=None):
    """A struck resonance. Percussion is built from these, never from filtering.

    Partials come off ONE phase signal so they stay exactly harmonic even while
    the pitch sweeps. Building them as separate damped_sine() calls instead lets
    their sweeps drift apart, and the drift beats: the grouse thump's 2nd
    partial swept to 93 Hz while twice the fundamental reached 89 Hz, and the
    ~29 Hz beat split every single thump into a flam.

    `decay_scale` gives each partial its own decay multiplier, which is how a
    real struck body loses its highs first — the reason the partials could not
    just share one envelope.
    """
    n = nsamp(dur)
    t = np.arange(n) / SR
    f = np.geomspace(f0, f_end, n) if f_end else np.full(n, float(f0))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.zeros(n)
    for k, a in enumerate(spectrum, start=1):
        if k * f0 > NYQ * 0.9:
            break
        ds = decay_s * (decay_scale[k - 1] if decay_scale else 1.0)
        body += a * np.sin(k * ph) * np.exp(-t / max(ds, 1e-4))
    return body


def burst(dur, rng, lo=200.0, hi=6000.0, decay_s=0.05, attack_s=0.002, kind="white"):
    """A shaped noise transient — huffs, slaps, wing clicks, snorts."""
    n = nsamp(dur)
    t = np.arange(n) / SR
    nz = bandpass(noise(dur, kind, rng), lo, hi)
    a = np.clip(t / max(attack_s, 1e-5), 0.0, 1.0)
    return nz * a * np.exp(-t / max(decay_s, 1e-4))


# --------------------------------------------------------------------------
# 4. assembly
# --------------------------------------------------------------------------

def mix_at(buf, seg, t0, gain=1.0):
    """Add `seg` into `buf` at t0 seconds, clipped to the buffer."""
    i = int(round(t0 * SR))
    if i >= len(buf):
        return buf
    if i < 0:
        seg = seg[-i:]
        i = 0
    j = min(len(buf), i + len(seg))
    if j > i:
        buf[i:j] += gain * seg[:j - i]
    return buf


def mix_wrapped(buf, seg, t0, gain=1.0):
    """Add `seg` into `buf` at t0, WRAPPING past the end.

    This is what makes an event bed a mathematically exact loop: a chirp that
    starts 40 ms before the end finishes 80 ms into the beginning, exactly as
    it would on the next pass.
    """
    n = len(buf)
    i = int(round(t0 * SR)) % n
    m = len(seg)
    if m >= n:
        seg = seg[:n]
        m = n
    end = i + m
    if end <= n:
        buf[i:end] += gain * seg
    else:
        k = n - i
        buf[i:] += gain * seg[:k]
        buf[:end - n] += gain * seg[k:]
    return buf


def pad_to(x, dur):
    n = nsamp(dur)
    if len(x) >= n:
        return x[:n].copy()
    return np.concatenate([x, np.zeros(n - len(x))])


def loopify_phase(ph, dur):
    """Nudge a phase signal so total accumulated phase is a whole number of turns.

    A sub-cent frequency change, inaudible, and it turns a tonal bed into a
    seamless loop with no crossfade at all.

    `ph` comes from 2*pi*cumsum(f)/SR, so ph[-1] is the phase accumulated over
    all n steps and the sample AFTER the buffer would sit at ph[-1] + one step.
    The loop therefore closes when ph[-1] itself is a whole number of turns —
    NOT when ph[-1]-ph[0] is. Getting that wrong leaves one sample-step of
    phase error, which at 600 Hz is ~0.17 rad and audibly clicks every loop.
    """
    n = len(ph)
    if n < 2:
        return ph
    total = float(ph[-1])
    target = round(total / (2 * np.pi)) * 2 * np.pi
    corr = (target - total) / n
    return ph + corr * (np.arange(n) + 1)


def periodic_mod(n, dur, rng, cycles=(1, 2, 3), depth=1.0):
    """A modulator built from whole cycles per loop — periodic by construction."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for c in cycles:
        ph = rng.random() * 2 * np.pi
        out += np.sin(2 * np.pi * c * t / dur + ph) / len(cycles)
    return depth * out


def crossfade_loop(x, xfade_s=0.35):
    """Equal-power fold of the tail into the head (the generic loop fallback)."""
    nx = nsamp(xfade_s)
    if len(x) <= 2 * nx:
        return x
    body = x[:len(x) - nx].copy()
    tail = x[len(x) - nx:]
    u = np.linspace(0.0, 1.0, nx)
    body[:nx] = body[:nx] * np.sin(u * np.pi / 2) + tail * np.cos(u * np.pi / 2)
    return body


# ==========================================================================
# 5. THE CALLS — Tier A
# ==========================================================================

def c_loon_wail(rng):
    """The sound of Maine. Long mournful glissando + the far shore answering."""
    dur = 3.1
    # rise, hold, a small step up for the second note, then the long fall
    f = glide([(0.00, 372), (0.34, 628, 0.65), (0.90, 690), (1.55, 712),
               (1.72, 792, 0.5), (2.05, 770), (3.10, 428, 1.5)], dur)
    a = env([(0.00, 0.0), (0.10, 0.95), (0.55, 1.0), (1.60, 0.98),
             (1.74, 1.0), (2.10, 0.95), (2.55, 0.72), (3.10, 0.0)], dur)
    v = tone(f, dur, spectrum=(1.0, 0.26, 0.075, 0.02), rng=rng,
             vib_hz=5.4, vib_depth=0.014, vib_delay=0.45,
             jitter=0.004, jitter_hz=3.0)
    breathy = bandpass(noise(dur, "pink", rng), 500, 2600) * 0.045
    x = (v + breathy) * a
    x = formant(x, [(700, 2.2, 1.0), (1500, 3.0, 0.28)], dry=0.55)
    # across the water: two clear slaps then a soft diffuse tail
    x = reverb(x, amount=0.55, taps=[(0.33, 0.30), (0.62, 0.145), (0.95, 0.06)],
               size=1.8, decay=0.62, damp_hz=1900, tail_s=1.5)
    return x


def c_loon_tremolo(rng):
    """The 'crazy laugh' — fast AM+FM warble on a held tone."""
    dur = 1.55
    t = taxis(dur)
    base = glide([(0.0, 640), (0.25, 745), (1.05, 760), (1.55, 665)], dur)
    rate = np.interp(t, [0, 0.2, 1.2, 1.55], [9.0, 11.6, 11.9, 9.8])
    wob = np.sin(2 * np.pi * np.cumsum(rate) / SR)
    f = base * (1.0 + 0.062 * wob)
    v = tone(f, dur, spectrum=(1.0, 0.30, 0.10, 0.035), rng=rng, jitter=0.006, jitter_hz=6)
    am = 1.0 - 0.55 * (0.5 - 0.5 * np.cos(2 * np.pi * np.cumsum(rate) / SR))
    a = env([(0.0, 0.0), (0.07, 1.0), (1.15, 0.95), (1.55, 0.0)], dur)
    x = v * am * a
    x = formant(x, [(760, 2.0, 1.0), (1650, 3.0, 0.3)], dry=0.6)
    return reverb(x, amount=0.4, taps=[(0.30, 0.24), (0.58, 0.10)],
                  size=1.7, decay=0.55, damp_hz=2100, tail_s=1.1)


def c_loon_yodel(rng):
    """Territorial: a rising note that breaks into a repeating jagged undulation."""
    dur = 3.0
    t = taxis(dur)
    rise = glide([(0.0, 360), (0.20, 640, 0.7), (0.70, 905)], dur)
    # the undulation: fast up, slower down, repeated ~4.6/s — a jagged sawtooth
    rate = 4.6
    ph = (np.cumsum(np.full(len(t), rate)) / SR) % 1.0
    jag = np.where(ph < 0.28, ph / 0.28, 1.0 - (ph - 0.28) / 0.72)
    jag = jag ** 0.8
    on = np.clip((t - 0.70) / 0.14, 0.0, 1.0)
    f = rise * (1.0 + on * 0.30 * (jag - 0.35))
    f *= np.interp(t, [0, 0.7, 2.4, 3.0], [1.0, 1.0, 1.0, 0.90])
    v = voice(f, dur, rng, spectrum=(1.0, 0.62, 0.38, 0.20, 0.11, 0.06),
              jitter=0.010, jitter_hz=14, sub=0.10, chaos=0.5, breath=0.05,
              breath_band=(700, 4200))
    a = env([(0.0, 0.0), (0.09, 0.85), (0.72, 1.0), (2.45, 0.95), (3.0, 0.0)], dur)
    x = v * a
    x = formant(x, [(950, 2.2, 1.0), (2100, 3.2, 0.42), (3400, 4.0, 0.16)], dry=0.45)
    x = 0.85 * np.tanh(1.5 * x)  # strained, not clean
    return reverb(x, amount=0.42, taps=[(0.31, 0.26), (0.60, 0.11)],
                  size=1.8, decay=0.6, damp_hz=2000, tail_s=1.3)


def _owl_hoot(dur, f_pts, rng, breath=0.10, spec=(1.0, 0.14, 0.035),
              a_pts=None, jitter=0.006):
    f = glide(f_pts, dur)
    v = tone(f, dur, spectrum=spec, rng=rng, jitter=jitter, jitter_hz=7,
             vib_hz=6.0, vib_depth=0.006, vib_delay=0.08)
    br = bandpass(noise(dur, "pink", rng), 300, 1800) * breath
    a = env(a_pts or [(0.0, 0.0), (0.035, 1.0), (dur * 0.65, 0.9), (dur, 0.0)], dur)
    x = (v + br) * a
    return formant(x, [(420, 2.4, 1.0), (950, 3.0, 0.22)], dry=0.5)


def c_barred_owl(rng):
    """'Who-cooks-for-you, who-cooks-for-YOU-ALL'. The rhythm IS the bird."""
    dur = 3.55
    out = np.zeros(nsamp(dur))
    base = 396.0

    def syl(t0, d, f0, f1, amp, tail=False):
        if tail:  # the drawn-out final syllable, sagging in pitch
            pts = [(0.0, f0 * 0.94), (0.05, f0), (d * 0.42, f0 * 1.01),
                   (d * 0.70, f0 * 0.86), (d, f1)]
            a_pts = [(0.0, 0.0), (0.05, 1.0), (d * 0.45, 0.95), (d * 0.7, 0.72), (d, 0.0)]
        else:
            pts = [(0.0, f0 * 0.93), (0.045, f0 * 1.02), (d * 0.6, f0), (d, f1)]
            a_pts = [(0.0, 0.0), (0.03, 1.0), (d * 0.65, 0.88), (d, 0.0)]
        s = _owl_hoot(d, pts, rng, breath=0.11, a_pts=a_pts)
        mix_at(out, s, t0, amp)

    # phrase 1: who / cooks / for / you
    syl(0.00, 0.17, base * 0.98, base * 0.93, 0.80)
    syl(0.21, 0.19, base * 1.03, base * 0.97, 0.92)
    syl(0.60, 0.17, base * 1.00, base * 0.95, 0.86)
    syl(0.81, 0.42, base * 1.02, base * 0.80, 1.00, tail=True)
    # phrase 2: same, but the last one is the drawl
    p2 = 1.62
    syl(p2 + 0.00, 0.17, base * 0.97, base * 0.92, 0.78)
    syl(p2 + 0.21, 0.19, base * 1.02, base * 0.96, 0.90)
    syl(p2 + 0.59, 0.17, base * 0.99, base * 0.94, 0.84)
    syl(p2 + 0.80, 0.72, base * 1.01, base * 0.66, 1.00, tail=True)

    return reverb(out, amount=0.34, taps=[(0.086, 0.26), (0.161, 0.15), (0.244, 0.08)],
                  size=1.2, decay=0.5, damp_hz=1500, tail_s=1.0)


def c_great_horned_owl(rng):
    """Five deep soft hoots, low and even, with the classic stutter in the middle."""
    dur = 2.9
    out = np.zeros(nsamp(dur))
    base = 246.0
    pattern = [(0.00, 0.30, 1.00, 0.92), (0.62, 0.16, 0.99, 0.74),
               (0.85, 0.20, 1.01, 0.80), (1.36, 0.28, 0.98, 0.88),
               (1.86, 0.34, 0.95, 0.82)]
    for t0, d, mult, amp in pattern:
        f0 = base * mult
        s = _owl_hoot(d, [(0.0, f0 * 0.96), (0.06, f0), (d * 0.7, f0 * 0.985), (d, f0 * 0.93)],
                      rng, breath=0.07, spec=(1.0, 0.10, 0.02),
                      a_pts=[(0.0, 0.0), (0.055, 1.0), (d * 0.7, 0.88), (d, 0.0)])
        s = bandpass(s, 0, 1400)   # muffled
        mix_at(out, s, t0, amp)
    return reverb(out, amount=0.42, taps=[(0.10, 0.22), (0.19, 0.12), (0.30, 0.06)],
                  size=1.5, decay=0.58, damp_hz=1100, tail_s=1.3)


def _coyote_voice(rng, f_scale=1.0, yips=True, dur=2.55):
    """One coyote: rising howl, a pitch break, then yips."""
    out = np.zeros(nsamp(dur))
    hd = 1.30
    f = glide([(0.00, 300 * f_scale), (0.13, 610 * f_scale, 0.6),
               (0.55, 690 * f_scale), (1.02, 735 * f_scale),
               (1.14, 935 * f_scale, 0.5), (1.30, 880 * f_scale)], hd)
    v = voice(f, hd, rng, spectrum=(1.0, 0.52, 0.36, 0.21, 0.13, 0.08, 0.05),
              jitter=0.012, jitter_hz=13, sub=0.07, chaos=0.4,
              vib_hz=5.2, vib_depth=0.016, vib_delay=0.30, breath=0.06,
              breath_band=(600, 4500))
    a = env([(0.0, 0.0), (0.07, 0.9), (0.35, 1.0), (1.05, 0.95), (1.16, 1.0), (1.30, 0.25)], hd)
    h = v * a
    h = formant(h, [(820 * f_scale, 2.4, 1.0), (1650 * f_scale, 3.0, 0.45),
                    (3100, 4.0, 0.13)], dry=0.4)
    mix_at(out, h, 0.0, 1.0)

    if yips:
        t = 1.34
        n_yip = int(rng.integers(4, 7))
        amp = 0.95
        for _ in range(n_yip):
            yd = float(rng.uniform(0.06, 0.115))
            top = float(rng.uniform(1000, 1350)) * f_scale
            yf = glide([(0.0, top * 0.82), (yd * 0.22, top), (yd, top * 0.62)], yd)
            yv = voice(yf, yd, rng, spectrum=(1.0, 0.6, 0.35, 0.2, 0.12),
                       jitter=0.02, jitter_hz=30, sub=0.10, chaos=0.6)
            ya = env([(0.0, 0.0), (0.008, 1.0), (yd * 0.55, 0.8), (yd, 0.0)], yd)
            yv = formant(yv * ya, [(1300, 2.5, 1.0), (2600, 3.5, 0.4)], dry=0.4)
            mix_at(out, yv, t, amp)
            t += float(rng.uniform(0.115, 0.20))
            amp *= float(rng.uniform(0.80, 0.97))
            if t > dur - 0.15:
                break
    return out


def c_coyote_howl(rng):
    x = _coyote_voice(rng, 1.0, yips=True, dur=2.55)
    return reverb(x, amount=0.32, taps=[(0.14, 0.22), (0.27, 0.12), (0.44, 0.06)],
                  size=1.6, decay=0.55, damp_hz=2400, tail_s=1.2)


def c_coyote_chorus(rng):
    """The pack: detuned, time-offset, at different distances. Deliberately chaotic."""
    dur = 6.2
    out = np.zeros(nsamp(dur))
    voices = [(0.00, 1.00, 14.0), (0.42, 0.86, 30.0), (0.95, 1.17, 22.0),
              (1.35, 0.93, 55.0), (2.05, 1.28, 40.0)]
    for t0, scale, dist in voices:
        sub_rng = np.random.default_rng(rng.integers(0, 2 ** 31))
        v = _coyote_voice(sub_rng, scale, yips=True,
                          dur=float(sub_rng.uniform(2.2, 2.9)))
        v = place(v, dist, amount_rev=0.25 + dist / 260.0)
        mix_at(out, v, t0, 1.0 / (1.0 + 0.10 * dist ** 0.5))
    return reverb(out, amount=0.30, taps=[(0.17, 0.20), (0.33, 0.11), (0.52, 0.055)],
                  size=1.9, decay=0.62, damp_hz=2000, tail_s=1.6)


def c_grouse_drum(rng):
    """Ruffed grouse drumming — an engine trying to start.

    NOTE ON BEAT COUNT: the brief said ~15 thumps, but 15 beats cannot both fill
    8 s and reach a blur — those two constraints contradict each other. The
    acoustic character was the stated priority, so this uses ~48 beats, which is
    also what the real bird does (40–50). The interval curve is the whole point:
    0.42 s down to 0.038 s on a power curve, so the last second is a whir.
    """
    dur = 8.9
    out = np.zeros(nsamp(dur))
    n_beats = 48
    span = 8.05
    u = np.linspace(0.0, 1.0, n_beats)
    iv = 0.038 + (0.42 - 0.038) * (1.0 - u) ** 1.65
    iv *= 1.0 + 0.035 * smooth_noise(n_beats, 6.0, rng)   # not a machine
    onsets = np.concatenate([[0.0], np.cumsum(iv)[:-1]])
    onsets *= span / max(onsets[-1], 1e-6)

    for i, t0 in enumerate(onsets):
        p = i / (n_beats - 1)
        # thumps shorten and soften as they blur together
        dec = 0.115 * (1.0 - 0.55 * p)
        f0 = 62.0 - 16.0 * p
        d = min(0.34, dec * 3.2)
        # 2nd + 3rd partial so it still reads on a laptop speaker. Phase-locked
        # to the fundamental (one damped_sine, not three) or they beat and every
        # thump becomes a double-hit.
        body = damped_sine(f0, d, dec, f_end=f0 * 0.72,
                           spectrum=(1.0, 0.42, 0.14), decay_scale=(1.0, 0.7, 0.45))
        air = burst(d, rng, 90, 900, decay_s=dec * 0.35, attack_s=0.004) * 0.30
        amp = (0.55 + 0.45 * p ** 0.6) * float(rng.uniform(0.93, 1.07))
        mix_at(out, (body + air), t0, amp)

    return reverb(out, amount=0.26, taps=[(0.055, 0.16), (0.108, 0.075)],
                  size=0.85, decay=0.5, damp_hz=900, tail_s=0.8)


def c_peepers(rng):
    """Spring peeper wall-of-sound. Seamless 8 s bed, events wrap the boundary."""
    dur = 8.0
    n = nsamp(dur)
    out = np.zeros(n)
    n_voices = 34
    for vi in range(n_voices):
        f0 = float(rng.uniform(2350, 3550))
        period = float(rng.uniform(0.78, 1.32))
        phase = float(rng.uniform(0.0, period))
        dist = float(rng.uniform(4.0, 70.0))
        gain = (6.0 / max(6.0, dist)) ** 0.75
        cd = float(rng.uniform(0.10, 0.17))
        # one chirp, reused across this voice's whole train
        cf = glide([(0.0, f0 * 0.90), (cd * 0.35, f0), (cd, f0 * 1.06)], cd)
        chirp = tone(cf, cd, spectrum=(1.0, 0.13, 0.03), rng=rng, jitter=0.004, jitter_hz=20)
        ca = env([(0.0, 0.0), (0.008, 1.0), (cd * 0.55, 0.85), (cd, 0.0)], cd)
        chirp = chirp * ca
        if dist > 18.0:
            chirp = bandpass(chirp, 0, max(3200.0, 9000.0 * math.exp(-dist / 90.0)))
        t = phase
        while t < dur:
            jit = float(rng.uniform(-0.035, 0.035))
            amp = gain * float(rng.uniform(0.72, 1.0))
            mix_wrapped(out, chirp, t + jit, amp)
            t += period * float(rng.uniform(0.93, 1.07))
    # far wall: a dense high wash. Generated LONGER than the loop and folded
    # back, so the overlap blends two independent stretches of noise — reusing
    # the head as the tail would just re-add the same samples at 1.41x gain.
    wash = bandpass(noise(dur + 0.4, "white", rng), 2200, 4200)
    wash = pad_to(crossfade_loop(wash, 0.4), dur)
    mod = 1.0 + 0.35 * periodic_mod(n, dur, rng, cycles=(7, 11, 17))
    out += 0.09 * wash * mod
    return out


def c_raven_kraa(rng):
    """Two-and-a-bit harsh rasping croaks. Noise-heavy with a hard formant."""
    dur = 1.45
    out = np.zeros(nsamp(dur))
    croaks = [(0.00, 0.30, 344, 288, 1.00), (0.46, 0.28, 322, 274, 0.94),
              (0.88, 0.33, 302, 246, 0.80)]
    for t0, d, f0, f1, amp in croaks:
        f = glide([(0.0, f0 * 1.04), (0.03, f0), (d, f1)], d)
        v = voice(f, d, rng, spectrum=SPEC_HARSH, jitter=0.045, jitter_hz=26,
                  sub=0.34, chaos=0.75, chaos_hz=16, breath=0.22,
                  breath_band=(600, 5000))
        a = env([(0.0, 0.0), (0.016, 1.0), (d * 0.55, 0.9), (d * 0.8, 0.6), (d, 0.0)], d)
        x = v * a
        x = formant(x, [(600, 5.0, 1.0), (1300, 7.0, 0.75), (2450, 5.5, 0.42),
                        (3900, 6.0, 0.14)], dry=0.10)
        x = 0.9 * np.tanh(1.9 * x)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.30, taps=[(0.10, 0.22), (0.20, 0.11), (0.33, 0.055)],
                  size=1.5, decay=0.52, damp_hz=2200, tail_s=1.1)


# ==========================================================================
# 6. THE CALLS — Tier B
# ==========================================================================

def c_moose_bellow(rng):
    """Long low groaning bellow, dropping, breathy and rough."""
    dur = 2.6
    f = glide([(0.00, 108), (0.28, 152, 0.7), (0.85, 141), (1.9, 116), (2.6, 92, 1.3)], dur)
    v = voice(f, dur, rng, spectrum=saw_spec(18, 0.82), jitter=0.030, jitter_hz=9,
              sub=0.26, chaos=0.55, chaos_hz=5, breath=0.30, breath_band=(280, 2400))
    a = env([(0.0, 0.0), (0.16, 0.85), (0.5, 1.0), (1.9, 0.9), (2.25, 0.7), (2.6, 0.0)], dur)
    x = v * a
    x = formant(x, [(320, 3.2, 1.0), (760, 4.0, 0.6), (1750, 4.5, 0.22),
                    (2900, 5.0, 0.07)], dry=0.28)
    x = 0.9 * np.tanh(1.6 * x)
    return reverb(x, amount=0.36, taps=[(0.15, 0.22), (0.29, 0.11), (0.47, 0.055)],
                  size=1.8, decay=0.6, damp_hz=1400, tail_s=1.4)


def c_moose_cow_call(rng):
    """The rising, whining, nasal moan. Weak fundamental, all formant."""
    dur = 2.1
    f = glide([(0.00, 176), (0.35, 232, 0.8), (1.35, 302), (1.75, 316), (2.10, 268, 1.4)], dur)
    v = voice(f, dur, rng, spectrum=SPEC_NASAL, jitter=0.022, jitter_hz=8,
              sub=0.12, chaos=0.4, vib_hz=4.6, vib_depth=0.012, vib_delay=0.5,
              breath=0.20, breath_band=(500, 3500))
    a = env([(0.0, 0.0), (0.14, 0.7), (0.9, 1.0), (1.7, 0.95), (2.1, 0.0)], dur)
    x = v * a
    x = formant(x, [(700, 4.5, 1.0), (1250, 5.5, 0.85), (2400, 5.0, 0.3)], dry=0.10)
    return reverb(x, amount=0.34, taps=[(0.14, 0.20), (0.28, 0.10)],
                  size=1.7, decay=0.55, damp_hz=2000, tail_s=1.2)


def c_bear_huff(rng):
    """Three explosive breathy huffs and a jaw pop. Dry and close — it's a warning."""
    dur = 1.35
    out = np.zeros(nsamp(dur))
    for t0, amp, lo in [(0.00, 1.00, 220), (0.30, 0.92, 200), (0.585, 0.86, 240)]:
        d = 0.16
        h = burst(d, rng, lo, 3200, decay_s=0.052, attack_s=0.0025)
        h = formant(h, [(480, 3.0, 1.0), (1150, 3.5, 0.5), (2200, 4.0, 0.2)], dry=0.35)
        h += 0.5 * damped_sine(118, d, 0.045, f_end=92) * 0.8
        mix_at(out, h, t0 + float(rng.uniform(-0.01, 0.01)), amp)
    # jaw pop: a very short, very high-Q wooden click
    pd = 0.05
    pop = damped_sine(1420, pd, 0.0045, spectrum=(1.0, 0.5, 0.22))
    pop += 0.7 * damped_sine(720, pd, 0.008)
    pop += 0.55 * burst(pd, rng, 900, 8000, decay_s=0.0035, attack_s=0.0004)
    mix_at(out, pop, 0.96, 1.0)
    return reverb(out, amount=0.16, taps=[(0.055, 0.18), (0.11, 0.08)],
                  size=1.0, decay=0.4, damp_hz=1800, tail_s=0.6)


def c_bear_growl(rng):
    """Low rumbling. Heavy roughness, chaotic subharmonics, a noise floor that moves."""
    dur = 2.2
    n = nsamp(dur)
    f = glide([(0.0, 88), (0.6, 78), (1.5, 82), (2.2, 68)], dur)
    v = voice(f, dur, rng, spectrum=saw_spec(20, 0.9), jitter=0.070, jitter_hz=13,
              sub=0.40, chaos=0.8, chaos_hz=9, breath=0.14, breath_band=(150, 1600))
    rumble = bandpass(noise(dur, "brown", rng), 60, 700)
    rumble *= 0.6 + 0.8 * np.abs(smooth_noise(n, 11.0, rng, octaves=3))
    a = env([(0.0, 0.0), (0.22, 0.85), (0.8, 1.0), (1.7, 0.92), (2.2, 0.0)], dur)
    x = (v + 0.55 * rumble) * a
    x = formant(x, [(280, 3.5, 1.0), (680, 4.0, 0.55), (1450, 4.5, 0.2)], dry=0.22)
    x = 0.9 * np.tanh(2.1 * x)
    return reverb(x, amount=0.22, taps=[(0.09, 0.18), (0.18, 0.08)],
                  size=1.2, decay=0.45, damp_hz=1200, tail_s=0.8)


def c_deer_snort(rng):
    """The alarm: explosive burst, then a descending whistle-wheeze."""
    dur = 1.15
    out = np.zeros(nsamp(dur))

    def snort(d_all, scale):
        n = nsamp(d_all)
        t = np.arange(n) / SR
        # (a) the explosion
        ex = burst(d_all, rng, 400 * scale, 8000, decay_s=0.020, attack_s=0.0008)
        # (b) the wheeze: narrow noise band chasing a falling contour
        wf = glide([(0.0, 2600 * scale), (0.10, 2050 * scale), (d_all, 900 * scale)], d_all)
        wz = sweep_bandpass(noise(d_all, "white", rng), wf, q=9.0, win=256)
        wz *= np.exp(-t / 0.20) * np.clip(t / 0.012, 0, 1)
        wz /= (np.max(np.abs(wz)) + 1e-9)
        # (c) a thin tonal whistle riding the same contour — this is what "reads"
        wt = tone(wf, d_all, spectrum=(1.0, 0.12), rng=rng, jitter=0.03, jitter_hz=40)
        wt *= np.exp(-t / 0.16) * np.clip(t / 0.018, 0, 1)
        s = 1.0 * ex + 0.75 * wz + 0.22 * wt
        return formant(s, [(1500, 2.0, 1.0), (3400, 2.5, 0.45)], dry=0.6)

    mix_at(out, snort(0.55, 1.00), 0.0, 1.00)
    mix_at(out, snort(0.38, 0.93), 0.62, 0.55)
    return reverb(out, amount=0.24, taps=[(0.075, 0.20), (0.15, 0.09)],
                  size=1.2, decay=0.45, damp_hz=3000, tail_s=0.7)


def c_beaver_slap(rng):
    """One sharp water slap: crack, low displacement boom, spray, rising bubbles."""
    dur = 0.72
    n = nsamp(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # crack
    out += 1.0 * burst(dur, rng, 700, 10000, decay_s=0.011, attack_s=0.0004)
    # low body — the water actually moving
    out += 0.95 * damped_sine(126, dur, 0.085, f_end=88, spectrum=(1.0, 0.35, 0.1))
    out += 0.4 * damped_sine(62, dur, 0.11, f_end=48)
    # spray
    spray = bandpass(noise(dur, "white", rng), 900, 7000)
    spray *= np.exp(-t / 0.10) * np.clip(t / 0.004, 0, 1)
    out += 0.55 * spray
    # settling water
    tail = bandpass(noise(dur, "pink", rng), 300, 3500)
    tail *= np.exp(-t / 0.22) * np.clip(t / 0.03, 0, 1) * 0.22
    out += tail
    # bubbles rise in pitch
    for _ in range(int(rng.integers(4, 8))):
        bt = float(rng.uniform(0.08, 0.42))
        bd = float(rng.uniform(0.014, 0.03))
        f0 = float(rng.uniform(380, 700))
        b = damped_sine(f0, bd, bd * 0.5, f_end=f0 * 2.1)
        b *= np.clip(np.arange(nsamp(bd)) / max(nsamp(0.002), 1), 0, 1)
        mix_at(out, b, bt, float(rng.uniform(0.05, 0.15)))
    return reverb(out, amount=0.30, taps=[(0.14, 0.26), (0.27, 0.13), (0.44, 0.06)],
                  size=1.05, decay=0.5, damp_hz=1600, tail_s=1.0)


def c_red_squirrel_scold(rng):
    """Machine-gun chatter. Three sharp intro chips, then a long rattling trill."""
    dur = 2.6
    out = np.zeros(nsamp(dur))

    def chip(d, f0, buzz_hz, harsh=1.0):
        cf = glide([(0.0, f0 * 0.72), (d * 0.25, f0 * 1.12), (d, f0 * 0.86)], d)
        v = tone(cf, d, spectrum=(1.0, 0.55, 0.3, 0.15), rng=rng, jitter=0.02, jitter_hz=60)
        nb = bandpass(noise(d, "white", rng), f0 * 0.8, min(NYQ * 0.95, f0 * 2.6))
        s = v + 0.45 * harsh * nb
        tt = np.arange(nsamp(d)) / SR
        s *= 1.0 - 0.45 * (0.5 - 0.5 * np.cos(2 * np.pi * buzz_hz * tt))
        a = env([(0.0, 0.0), (0.004, 1.0), (d * 0.5, 0.8), (d, 0.0)], d)
        return s * a

    for i, t0 in enumerate((0.00, 0.135, 0.27)):
        mix_at(out, chip(0.055, 2450, 190), t0, 1.0 - 0.06 * i)

    t = 0.44
    i = 0
    while t < dur - 0.06:
        rate_scale = 1.0 + 0.10 * math.sin(i * 0.35)
        d = 0.032 * rate_scale
        f0 = 2150 * float(rng.uniform(0.94, 1.08))
        amp = 0.62 + 0.38 * math.sin(math.pi * min(1.0, (t - 0.44) / (dur - 0.6)))
        mix_at(out, chip(d, f0, 210), t, amp * float(rng.uniform(0.85, 1.0)))
        t += 0.058 * rate_scale * float(rng.uniform(0.94, 1.06))
        i += 1

    out = formant(out, [(2400, 3.0, 1.0), (4200, 3.5, 0.5), (6200, 4.0, 0.18)], dry=0.45)
    return reverb(out, amount=0.20, taps=[(0.06, 0.18), (0.13, 0.08)],
                  size=1.1, decay=0.42, damp_hz=4000, tail_s=0.6)


def c_blue_jay_scream(rng):
    """Two harsh descending screeches."""
    dur = 1.05
    out = np.zeros(nsamp(dur))
    for t0, amp, sc in [(0.0, 1.0, 1.0), (0.52, 0.90, 0.96)]:
        d = 0.36
        f = glide([(0.0, 2050 * sc), (0.035, 2750 * sc, 0.5), (0.12, 2350 * sc),
                   (d, 1380 * sc, 1.25)], d)
        v = voice(f, d, rng, spectrum=(1.0, 0.7, 0.42, 0.22, 0.12),
                  jitter=0.024, jitter_hz=40, sub=0.20, chaos=0.6, chaos_hz=30,
                  breath=0.18, breath_band=(1500, 8000))
        tt = np.arange(nsamp(d)) / SR
        v *= 1.0 - 0.28 * (0.5 - 0.5 * np.cos(2 * np.pi * 95 * tt))   # rasp
        a = env([(0.0, 0.0), (0.012, 1.0), (d * 0.45, 0.9), (d, 0.0)], d)
        x = v * a
        x = formant(x, [(2100, 3.0, 1.0), (3600, 3.5, 0.55), (5600, 4.0, 0.2)], dry=0.3)
        x = 0.9 * np.tanh(1.7 * x)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.24, taps=[(0.07, 0.20), (0.15, 0.09)],
                  size=1.2, decay=0.45, damp_hz=3600, tail_s=0.7)


def c_crow_caw(rng):
    """Three harsh mid-frequency caws."""
    dur = 1.45
    out = np.zeros(nsamp(dur))
    for t0, d, f0, f1, amp in [(0.00, 0.27, 520, 400, 1.0), (0.45, 0.26, 505, 392, 0.95),
                               (0.88, 0.31, 480, 360, 0.85)]:
        f = glide([(0.0, f0 * 1.08), (0.028, f0), (d * 0.6, f0 * 0.94), (d, f1)], d)
        v = voice(f, d, rng, spectrum=SPEC_HARSH, jitter=0.038, jitter_hz=30,
                  sub=0.22, chaos=0.65, chaos_hz=22, breath=0.24, breath_band=(800, 7000))
        a = env([(0.0, 0.0), (0.012, 1.0), (d * 0.5, 0.92), (d * 0.82, 0.55), (d, 0.0)], d)
        x = v * a
        x = formant(x, [(900, 4.0, 1.0), (1800, 5.0, 0.7), (3100, 4.5, 0.35),
                        (5000, 5.0, 0.12)], dry=0.15)
        x = 0.9 * np.tanh(1.8 * x)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.26, taps=[(0.085, 0.20), (0.17, 0.10), (0.28, 0.05)],
                  size=1.3, decay=0.48, damp_hz=2800, tail_s=0.8)


def c_chickadee_dee(rng):
    """'chicka-dee-dee-dee' — two clear intro notes, then four buzzy descending dees."""
    dur = 0.92
    out = np.zeros(nsamp(dur))

    # "chick" and "a": short, high, clear
    for t0, d, f0, f1, amp in [(0.00, 0.055, 4300, 3950, 0.85), (0.078, 0.042, 3700, 3400, 0.72)]:
        f = glide([(0.0, f0), (d, f1)], d)
        v = tone(f, d, spectrum=(1.0, 0.06), rng=rng, jitter=0.006, jitter_hz=50)
        a = env([(0.0, 0.0), (0.005, 1.0), (d * 0.6, 0.8), (d, 0.0)], d)
        mix_at(out, v * a, t0, amp)

    # the dees: harmonically dense, formant descending across the series
    for i, t0 in enumerate((0.165, 0.305, 0.445, 0.585)):
        d = 0.115
        f0 = 880 - 40 * i
        f = glide([(0.0, f0 * 1.05), (d, f0 * 0.88)], d)
        v = tone(f, d, spectrum=saw_spec(11, 0.55), rng=rng, jitter=0.010, jitter_hz=45)
        nb = bandpass(noise(d, "white", rng), 1800, 5200) * 0.18
        fc = np.linspace(3300 - 220 * i, 2500 - 220 * i, nsamp(d))
        s = sweep_bandpass(v + nb, fc, q=3.2, win=128)
        a = env([(0.0, 0.0), (0.008, 1.0), (d * 0.7, 0.85), (d, 0.0)], d)
        mix_at(out, s * a, t0, 1.0 - 0.05 * i)

    return reverb(out, amount=0.18, taps=[(0.05, 0.16), (0.11, 0.07)],
                  size=1.0, decay=0.4, damp_hz=5000, tail_s=0.5)


def c_chickadee_song(rng):
    """'fee-bee' — a clear whistle and one a whole step below it."""
    dur = 1.05
    out = np.zeros(nsamp(dur))
    fee_f, bee_f = 4320.0, 4320.0 / 1.1225      # a whole step down
    for t0, d, f0, f1, amp, wob in [(0.00, 0.33, fee_f, fee_f * 0.985, 1.0, 0.0),
                                    (0.40, 0.44, bee_f * 1.02, bee_f * 0.985, 0.92, 1.0)]:
        f = glide([(0.0, f0 * 0.99), (0.03, f0), (d, f1)], d)
        v = tone(f, d, spectrum=(1.0, 0.045), rng=rng, jitter=0.003, jitter_hz=25,
                 vib_hz=13.0, vib_depth=0.004 * wob, vib_delay=0.02)
        br = bandpass(noise(d, "white", rng), 3000, 7000) * 0.035
        a = env([(0.0, 0.0), (0.018, 1.0), (d * 0.75, 0.92), (d, 0.0)], d)
        mix_at(out, (v + br) * a, t0, amp)
    return reverb(out, amount=0.22, taps=[(0.055, 0.18), (0.12, 0.08)],
                  size=1.1, decay=0.42, damp_hz=5200, tail_s=0.6)


def c_turkey_gobble(rng):
    """The burbling cascade — chaotic sample-and-hold FM and AM, ~22 Hz."""
    dur = 1.3
    n = nsamp(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)

    # the introductory note
    d0 = 0.11
    f0c = glide([(0.0, 380), (0.03, 470), (d0, 430)], d0)
    intro = voice(f0c, d0, rng, spectrum=SPEC_HARSH, jitter=0.03, jitter_hz=40,
                  sub=0.2, chaos=0.5)
    intro *= env([(0.0, 0.0), (0.008, 1.0), (d0, 0.0)], d0)
    mix_at(out, formant(intro, [(850, 3.5, 1.0), (1700, 4.0, 0.5)], dry=0.3), 0.0, 0.85)

    # the gobble proper
    gd = 1.10
    ng = nsamp(gd)
    tg = np.arange(ng) / SR
    # pitch and loudness jump together on the same stepped clock
    rate = np.interp(tg, [0, 0.15, 0.9, gd], [17.0, 24.0, 23.0, 19.0])
    chaos_f, chaos_a = sample_hold(ng, rate, rng, streams=2)
    base = np.interp(tg, [0, 0.5, gd], [520, 470, 420])
    f = base * (1.0 + 0.32 * chaos_f)
    v = voice(f, gd, rng, spectrum=SPEC_HARSH, jitter=0.05, jitter_hz=55,
              sub=0.28, chaos=0.7, chaos_hz=30, breath=0.16, breath_band=(700, 6000))
    am = 0.45 + 0.55 * np.clip(0.5 + 0.6 * chaos_a, 0.05, 1.0)
    am *= 1.0 - 0.2 * (0.5 - 0.5 * np.cos(2 * np.pi * 62 * tg))
    a = env([(0.0, 0.0), (0.01, 1.0), (0.85, 0.9), (gd, 0.0)], gd)
    g = v * am * a
    g = formant(g, [(820, 3.5, 1.0), (1650, 4.0, 0.65), (2900, 4.5, 0.28)], dry=0.2)
    g = 0.9 * np.tanh(1.9 * g)
    mix_at(out, g, 0.145, 1.0)

    return reverb(out, amount=0.22, taps=[(0.08, 0.18), (0.16, 0.08)],
                  size=1.3, decay=0.45, damp_hz=3000, tail_s=0.7)


def c_woodcock_peent(rng):
    """One buzzy nasal 'peent'."""
    dur = 0.5
    d = 0.36
    f = glide([(0.0, 320), (0.05, 372), (d * 0.7, 360), (d, 336)], d)
    v = voice(f, d, rng, spectrum=saw_spec(20, 0.62), jitter=0.018, jitter_hz=35,
              sub=0.14, chaos=0.4, breath=0.10, breath_band=(1200, 6000))
    fc = np.linspace(2250, 1900, nsamp(d))
    v = sweep_bandpass(v, fc, q=2.6, win=128) + 0.25 * v
    a = env([(0.0, 0.0), (0.022, 1.0), (d * 0.75, 0.92), (d * 0.92, 0.6), (d, 0.0)], d)
    x = v * a
    x = formant(x, [(2100, 3.5, 1.0), (3600, 4.0, 0.35)], dry=0.35)
    x = pad_to(x, dur)
    return reverb(x, amount=0.20, taps=[(0.07, 0.16), (0.14, 0.07)],
                  size=1.2, decay=0.42, damp_hz=3500, tail_s=0.6)


def c_woodcock_twitter(rng):
    """Wing-feather twittering on the sky dance — three wavering voices, descending."""
    dur = 3.1
    n = nsamp(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for vi in range(3):
        warble = float(rng.uniform(9.0, 14.5))
        base = np.interp(t, [0, 1.8, 2.5, dur], [2950, 2850, 2600, 2150]) * float(rng.uniform(0.9, 1.12))
        wob = np.sin(2 * np.pi * warble * t + rng.random() * 6.28)
        drift = smooth_noise(n, 3.0, rng, octaves=2)
        f = base * (1.0 + 0.20 * wob + 0.05 * drift)
        v = tone(f, dur, spectrum=(1.0, 0.10, 0.03), rng=rng, jitter=0.008, jitter_hz=18)
        chirp_hz = warble * float(rng.uniform(0.9, 1.1))
        pulse = 0.5 - 0.5 * np.cos(2 * np.pi * chirp_hz * t + rng.random() * 6.28)
        v *= 0.25 + 0.75 * pulse ** 1.7
        out += v * float(rng.uniform(0.6, 1.0))
    air = bandpass(noise(dur, "white", rng), 2200, 6000) * 0.05
    a = env([(0.0, 0.0), (0.12, 0.8), (0.7, 1.0), (2.4, 0.85), (3.1, 0.0)], dur)
    x = (out / 3.0 + air) * a
    return reverb(x, amount=0.32, taps=[(0.12, 0.20), (0.24, 0.10)],
                  size=1.6, decay=0.5, damp_hz=4500, tail_s=1.0)


def c_heron_croak(rng):
    """One harsh prehistoric 'FRAHNK'."""
    dur = 0.9
    d = 0.62
    f = glide([(0.0, 268), (0.04, 244), (0.3, 216), (d, 176, 1.2)], d)
    v = voice(f, d, rng, spectrum=SPEC_HARSH, jitter=0.055, jitter_hz=24,
              sub=0.40, chaos=0.8, chaos_hz=13, breath=0.28, breath_band=(500, 6000))
    a = env([(0.0, 0.0), (0.014, 1.0), (0.30, 0.85), (0.48, 0.5), (d, 0.0)], d)
    x = v * a
    x = formant(x, [(520, 4.5, 1.0), (1150, 5.5, 0.7), (2250, 5.0, 0.4),
                    (3800, 5.5, 0.15)], dry=0.12)
    x = 0.9 * np.tanh(2.0 * x)
    x = pad_to(x, dur)
    return reverb(x, amount=0.34, taps=[(0.11, 0.24), (0.22, 0.12), (0.36, 0.06)],
                  size=1.7, decay=0.55, damp_hz=2000, tail_s=1.1)


def _goose_honk(rng, scale=1.0):
    """One 'ah-HONK' — a short low note then the rising nasal one."""
    dur = 0.68
    out = np.zeros(nsamp(dur))
    # "ah"
    d1 = 0.16
    f1 = glide([(0.0, 372 * scale), (0.03, 408 * scale), (d1, 392 * scale)], d1)
    v1 = voice(f1, d1, rng, spectrum=SPEC_NASAL, jitter=0.025, jitter_hz=30,
               sub=0.16, chaos=0.5, breath=0.16, breath_band=(700, 5000))
    v1 *= env([(0.0, 0.0), (0.012, 1.0), (d1 * 0.7, 0.85), (d1, 0.0)], d1)
    mix_at(out, v1, 0.0, 0.78)
    # "HONK"
    d2 = 0.30
    f2 = glide([(0.0, 330 * scale), (0.06, 452 * scale, 0.6), (0.17, 470 * scale),
                (d2, 398 * scale, 1.3)], d2)
    v2 = voice(f2, d2, rng, spectrum=SPEC_NASAL, jitter=0.022, jitter_hz=26,
               sub=0.18, chaos=0.55, breath=0.18, breath_band=(700, 6000))
    v2 *= env([(0.0, 0.0), (0.016, 1.0), (d2 * 0.6, 0.92), (d2, 0.0)], d2)
    mix_at(out, v2, 0.255, 1.0)
    out = formant(out, [(1000, 4.0, 1.0), (2050, 4.5, 0.75), (3300, 5.0, 0.28)], dry=0.15)
    return 0.9 * np.tanh(1.6 * out)


def c_goose_honk(rng):
    x = _goose_honk(rng, 1.0)
    return reverb(x, amount=0.26, taps=[(0.09, 0.20), (0.18, 0.10)],
                  size=1.4, decay=0.5, damp_hz=2600, tail_s=0.9)


def c_goose_skein(rng):
    """A V going over: eight birds, different distances, different times."""
    dur = 6.0
    out = np.zeros(nsamp(dur))
    for _ in range(8):
        sub_rng = np.random.default_rng(rng.integers(0, 2 ** 31))
        h = _goose_honk(sub_rng, float(sub_rng.uniform(0.88, 1.16)))
        dist = float(sub_rng.uniform(25.0, 240.0))
        h = place(h, dist, amount_rev=0.18 + dist / 400.0)
        mix_at(out, h, float(sub_rng.uniform(0.0, dur - 0.9)), 1.0)
    air = bandpass(noise(dur, "pink", rng), 200, 1400) * 0.03
    out += air * env([(0.0, 0.0), (0.4, 1.0), (dur - 0.4, 1.0), (dur, 0.0)], dur)
    return reverb(out, amount=0.28, taps=[(0.15, 0.18), (0.30, 0.09)],
                  size=1.9, decay=0.6, damp_hz=1800, tail_s=1.3)


def c_loon_chick(rng):
    """Soft short peeps. Quiet, round, a little breathy."""
    dur = 1.6
    out = np.zeros(nsamp(dur))
    t = 0.05
    for i in range(5):
        d = float(rng.uniform(0.075, 0.11))
        f0 = float(rng.uniform(1120, 1480))
        f = glide([(0.0, f0 * 0.86), (d * 0.35, f0), (d, f0 * 0.82)], d)
        v = tone(f, d, spectrum=(1.0, 0.18, 0.05), rng=rng, jitter=0.010, jitter_hz=30)
        br = bandpass(noise(d, "white", rng), 1200, 5000) * 0.09
        a = env([(0.0, 0.0), (0.012, 1.0), (d * 0.6, 0.8), (d, 0.0)], d)
        mix_at(out, (v + br) * a, t, float(rng.uniform(0.7, 1.0)))
        t += float(rng.uniform(0.19, 0.32))
    out = formant(out, [(1350, 2.5, 1.0), (2700, 3.0, 0.3)], dry=0.5)
    return reverb(out, amount=0.28, taps=[(0.10, 0.18), (0.21, 0.08)],
                  size=1.4, decay=0.48, damp_hz=3200, tail_s=0.8)


def c_fisher_scream(rng):
    """The scream in the dark.

    Everything here is aimed at unease rather than volume: an accelerating rise
    (so it never resolves), flickering period-doubling (a voice losing control),
    a second voice detuned 0.7% so the two beat against each other, and a hard
    break at the end instead of a decay.
    """
    dur = 1.75
    d = 1.45
    n = nsamp(d)
    t = np.arange(n) / SR
    f = glide([(0.00, 470), (0.20, 620), (0.60, 880, 0.85), (1.05, 1290, 0.8),
               (1.22, 1400), (1.31, 980, 0.4), (d, 760, 1.4)], d)
    v1 = voice(f, d, rng, spectrum=saw_spec(13, 0.62), jitter=0.055, jitter_hz=21,
               sub=0.32, chaos=0.85, chaos_hz=11, breath=0.26, breath_band=(1200, 9000))
    v2 = voice(f * 1.007, d, rng, spectrum=saw_spec(11, 0.7), jitter=0.06, jitter_hz=17,
               sub=0.26, chaos=0.8, chaos_hz=9)
    tremor = 1.0 - 0.22 * (0.5 - 0.5 * np.cos(2 * np.pi * 26 * t))
    rasp = sweep_bandpass(noise(d, "white", rng), f * 2.0, q=4.0, win=256)
    rasp /= (np.max(np.abs(rasp)) + 1e-9)
    a = env([(0.0, 0.0), (0.05, 0.55), (0.55, 0.85), (1.10, 1.0), (1.24, 1.0),
             (1.33, 0.55), (d, 0.0)], d)
    x = (v1 + 0.55 * v2 + 0.30 * rasp) * tremor * a
    x = formant(x, [(1100, 3.2, 1.0), (2450, 3.8, 0.7), (3900, 4.2, 0.35),
                    (6000, 5.0, 0.12)], dry=0.18)
    x = 0.9 * np.tanh(2.2 * x)
    x = pad_to(x, dur)
    return reverb(x, amount=0.26, taps=[(0.10, 0.20), (0.21, 0.10), (0.35, 0.05)],
                  size=1.5, decay=0.5, damp_hz=3200, tail_s=1.0)


def c_fox_scream(rng):
    """A sharp shrieking bark, then a shorter second one. Strangled, not smooth."""
    dur = 1.25
    out = np.zeros(nsamp(dur))
    for t0, d, sc, amp in [(0.0, 0.52, 1.0, 1.0), (0.68, 0.34, 0.94, 0.82)]:
        f = glide([(0.0, 640 * sc), (0.045, 1080 * sc, 0.55), (d * 0.45, 1010 * sc),
                   (d * 0.8, 880 * sc), (d, 700 * sc, 1.3)], d)
        v = voice(f, d, rng, spectrum=saw_spec(12, 0.66), jitter=0.050, jitter_hz=28,
                  sub=0.30, chaos=0.8, chaos_hz=20, breath=0.28, breath_band=(1200, 8000))
        a = env([(0.0, 0.0), (0.012, 1.0), (d * 0.5, 0.88), (d * 0.8, 0.55), (d, 0.0)], d)
        x = v * a
        x = formant(x, [(1150, 3.0, 1.0), (2500, 3.5, 0.65), (4200, 4.0, 0.25)], dry=0.2)
        x = 0.9 * np.tanh(2.0 * x)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.26, taps=[(0.09, 0.20), (0.19, 0.10)],
                  size=1.4, decay=0.48, damp_hz=3400, tail_s=0.9)


def c_lynx_caterwaul(rng):
    """A long wavering yowl that sags into a growl. Very formant-driven — cats are."""
    dur = 2.7
    d = 2.45
    n = nsamp(d)
    t = np.arange(n) / SR
    f = glide([(0.00, 330), (0.30, 480, 0.75), (0.90, 545), (1.50, 520),
               (2.00, 430), (d, 300, 1.3)], d)
    v = voice(f, d, rng, spectrum=(1.0, 0.62, 0.40, 0.26, 0.17, 0.11, 0.07, 0.04),
              jitter=0.030, jitter_hz=10, sub=0.22, chaos=0.6, chaos_hz=6,
              vib_hz=4.3, vib_depth=0.055, vib_delay=0.35,
              breath=0.16, breath_band=(600, 5000))
    growl = bandpass(noise(d, "brown", rng), 70, 900)
    growl *= np.clip((t - 1.5) / 0.6, 0, 1) * (0.5 + 0.6 * np.abs(smooth_noise(n, 14.0, rng, 2)))
    a = env([(0.0, 0.0), (0.12, 0.7), (0.8, 1.0), (1.8, 0.95), (2.2, 0.7), (d, 0.0)], d)
    x = (v + 0.40 * growl) * a
    x = formant(x, [(720, 3.5, 1.0), (1320, 4.5, 0.8), (2650, 4.5, 0.35),
                    (4200, 5.0, 0.12)], dry=0.16)
    x = 0.9 * np.tanh(1.7 * x)
    x = pad_to(x, dur)
    return reverb(x, amount=0.30, taps=[(0.11, 0.20), (0.23, 0.10), (0.38, 0.05)],
                  size=1.5, decay=0.52, damp_hz=2600, tail_s=1.0)


def c_bullfrog(rng):
    """'Jug-o-rum' — three low pulsed notes, hollow and round."""
    dur = 1.55
    out = np.zeros(nsamp(dur))
    notes = [(0.00, 0.28, 186, 172, 26.0, 0.9),    # jug
             (0.36, 0.19, 214, 205, 22.0, 0.72),   # o
             (0.60, 0.62, 152, 132, 31.0, 1.0)]    # rum
    for t0, d, f0, f1, pulse_hz, amp in notes:
        n = nsamp(d)
        t = np.arange(n) / SR
        f = glide([(0.0, f0 * 1.05), (0.05, f0), (d, f1)], d)
        v = voice(f, d, rng, spectrum=(1.0, 0.85, 0.62, 0.4, 0.26, 0.16, 0.09, 0.05),
                  jitter=0.014, jitter_hz=12, sub=0.14, chaos=0.35, breath=0.05,
                  breath_band=(300, 2000))
        v *= 1.0 - 0.42 * (0.5 - 0.5 * np.cos(2 * np.pi * pulse_hz * t))
        a = env([(0.0, 0.0), (0.03, 1.0), (d * 0.65, 0.9), (d, 0.0)], d)
        x = v * a
        x = formant(x, [(390, 4.5, 1.0), (930, 5.0, 0.5), (1700, 5.0, 0.15)], dry=0.1)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.30, taps=[(0.13, 0.20), (0.26, 0.10)],
                  size=1.6, decay=0.5, damp_hz=1400, tail_s=1.0)


def c_wood_thrush(rng):
    """Two syrinxes at once — that harmony is the whole bird. Then the flute trill."""
    dur = 1.85
    out = np.zeros(nsamp(dur))

    # quiet introductory note
    d0 = 0.10
    fi = glide([(0.0, 1180), (d0, 1240)], d0)
    intro = tone(fi, d0, spectrum=SPEC_FLUTE, rng=rng, jitter=0.004, jitter_hz=20)
    intro *= env([(0.0, 0.0), (0.02, 1.0), (d0, 0.0)], d0)
    mix_at(out, intro, 0.02, 0.30)

    # the phrase: two voices spiralling up, a fifth apart, contours not identical
    d = 0.70
    n = nsamp(d)
    t = np.arange(n) / SR
    spiral = np.sin(2 * np.pi * 4.2 * t)
    fa = glide([(0.0, 1760), (0.22, 2180), (0.48, 2400), (d, 2620)], d) * (1 + 0.045 * spiral)
    fb = glide([(0.0, 1760 * 1.485), (0.26, 2050 * 1.485), (0.52, 2270 * 1.485),
                (d, 2400 * 1.485)], d) * (1 + 0.038 * np.sin(2 * np.pi * 4.2 * t + 1.1))
    va = tone(fa, d, spectrum=SPEC_FLUTE, rng=rng, jitter=0.004, jitter_hz=14)
    vb = tone(fb, d, spectrum=(1.0, 0.10, 0.03), rng=rng, jitter=0.005, jitter_hz=16)
    a = env([(0.0, 0.0), (0.05, 0.9), (0.3, 1.0), (0.6, 0.9), (d, 0.0)], d)
    mix_at(out, (va + 0.62 * vb) * a, 0.22, 1.0)

    # the closing trill
    dt = 0.42
    nt = nsamp(dt)
    tt = np.arange(nt) / SR
    ft = 2500 * (1.0 + 0.16 * np.sin(2 * np.pi * 32 * tt))
    vt = tone(ft, dt, spectrum=SPEC_FLUTE, rng=rng, jitter=0.005, jitter_hz=20)
    vt += 0.5 * tone(ft * 1.5, dt, spectrum=(1.0, 0.08), rng=rng)
    vt *= (0.45 + 0.55 * (0.5 - 0.5 * np.cos(2 * np.pi * 32 * tt)))
    vt *= env([(0.0, 0.0), (0.03, 1.0), (dt * 0.6, 0.8), (dt, 0.0)], dt)
    mix_at(out, vt, 0.98, 0.75)

    # deep-woods space is half the magic
    return reverb(out, amount=0.48, taps=[(0.07, 0.24), (0.15, 0.14), (0.26, 0.08),
                                          (0.40, 0.04)],
                  size=1.6, decay=0.62, damp_hz=3800, tail_s=1.4)


def c_pileated_drum(rng):
    """Fast even roll on a hollow tree. Loud, then it falls off a cliff."""
    dur = 1.9
    out = np.zeros(nsamp(dur))
    n_hits = 21
    u = np.linspace(0, 1, n_hits)
    iv = 0.042 + 0.030 * u ** 2.2            # even, then a slight slowing at the end
    onsets = np.concatenate([[0.0], np.cumsum(iv)[:-1]])
    for i, t0 in enumerate(onsets):
        p = i / (n_hits - 1)
        hd = 0.075
        hit = burst(hd, rng, 900, 9000, decay_s=0.0042, attack_s=0.0004) * 1.0
        hit += 0.85 * damped_sine(680, hd, 0.020, f_end=560, spectrum=(1.0, 0.4, 0.15))
        hit += 0.55 * damped_sine(1620, hd, 0.011)
        hit += 0.60 * damped_sine(185, hd, 0.035, f_end=150)
        amp = (1.0 - 0.55 * p ** 2.5) * float(rng.uniform(0.93, 1.05))
        mix_at(out, hit, t0, amp)
    # a woodpecker drum carries because the forest answers it
    return reverb(out, amount=0.34, taps=[(0.075, 0.26), (0.148, 0.14), (0.235, 0.075),
                                          (0.36, 0.035)],
                  size=1.0, decay=0.55, damp_hz=2600, tail_s=1.2)


def c_pileated_call(rng):
    """The maniacal laugh — an irregular 'kuk-kuk-kuk' cascade that swells and dies."""
    dur = 2.3
    out = np.zeros(nsamp(dur))
    t = 0.02
    i = 0
    n_est = 17
    while t < dur - 0.12 and i < 26:
        p = min(1.0, i / n_est)
        d = float(rng.uniform(0.050, 0.075))
        f0 = (1780 - 330 * p) * float(rng.uniform(0.95, 1.06))
        f = glide([(0.0, f0 * 1.14), (d * 0.28, f0), (d, f0 * 0.78)], d)
        v = voice(f, d, rng, spectrum=(1.0, 0.62, 0.36, 0.2, 0.11),
                  jitter=0.022, jitter_hz=45, sub=0.16, chaos=0.55, chaos_hz=35,
                  breath=0.14, breath_band=(1500, 8000))
        a = env([(0.0, 0.0), (0.006, 1.0), (d * 0.5, 0.82), (d, 0.0)], d)
        x = formant(v * a, [(1700, 3.0, 1.0), (3200, 3.5, 0.5), (5200, 4.0, 0.18)], dry=0.3)
        amp = (0.55 + 0.45 * math.sin(math.pi * min(1.0, p * 1.05))) * float(rng.uniform(0.85, 1.0))
        mix_at(out, x, t, amp)
        t += float(rng.uniform(0.105, 0.145)) * (1.0 + 0.25 * p)
        i += 1
    return reverb(out, amount=0.34, taps=[(0.08, 0.24), (0.17, 0.12), (0.28, 0.06)],
                  size=1.5, decay=0.55, damp_hz=3200, tail_s=1.1)


def c_eagle_cry(rng):
    """The REAL bald eagle: a thin descending chitter, not the movie hawk scream."""
    dur = 1.75
    out = np.zeros(nsamp(dur))
    notes = [(0.00, 0.16, 2500, 2650, 0.85), (0.24, 0.14, 2620, 2400, 1.0)]
    t = 0.44
    f_cur = 2380.0
    for _ in range(7):
        notes.append((t, float(rng.uniform(0.045, 0.075)), f_cur, f_cur * 0.90,
                      float(rng.uniform(0.6, 0.95))))
        t += float(rng.uniform(0.085, 0.125))
        f_cur *= float(rng.uniform(0.90, 0.965))
    for t0, d, f0, f1, amp in notes:
        f = glide([(0.0, f0 * 0.94), (d * 0.25, f0), (d, f1)], d)
        v = tone(f, d, spectrum=(1.0, 0.22, 0.07), rng=rng, jitter=0.014, jitter_hz=55)
        nb = bandpass(noise(d, "white", rng), 2000, 7000) * 0.16
        a = env([(0.0, 0.0), (0.008, 1.0), (d * 0.6, 0.82), (d, 0.0)], d)
        x = (v + nb) * a
        x = formant(x, [(2600, 3.0, 1.0), (4600, 3.5, 0.35)], dry=0.4)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.30, taps=[(0.10, 0.20), (0.21, 0.10)],
                  size=1.6, decay=0.52, damp_hz=4200, tail_s=1.0)


def c_osprey_whistle(rng):
    """A series of clear plaintive whistles, the series rising then falling."""
    dur = 1.85
    out = np.zeros(nsamp(dur))
    t = 0.02
    arc = [0.94, 1.0, 1.06, 1.09, 1.04, 0.96]
    for i, m in enumerate(arc):
        d = 0.135
        f0 = 1980 * m
        f = glide([(0.0, f0 * 0.80), (d * 0.30, f0 * 1.10), (d * 0.55, f0 * 1.06),
                   (d, f0 * 0.88)], d)
        v = tone(f, d, spectrum=(1.0, 0.14, 0.04), rng=rng, jitter=0.006, jitter_hz=30)
        nb = bandpass(noise(d, "white", rng), 1800, 5500) * 0.05
        a = env([(0.0, 0.0), (0.014, 1.0), (d * 0.65, 0.88), (d, 0.0)], d)
        x = formant((v + nb) * a, [(2200, 3.0, 1.0), (4000, 3.5, 0.28)], dry=0.45)
        mix_at(out, x, t, 0.75 + 0.25 * math.sin(math.pi * i / max(len(arc) - 1, 1)))
        t += 0.245 - 0.012 * i
    return reverb(out, amount=0.34, taps=[(0.12, 0.22), (0.25, 0.11)],
                  size=1.7, decay=0.55, damp_hz=3800, tail_s=1.1)


def c_snowy_owl_hoot(rng):
    """Two deep booming hoots. Almost pure fundamental, big open space."""
    dur = 2.2
    out = np.zeros(nsamp(dur))
    for t0, amp, m in [(0.05, 1.0, 1.0), (0.92, 0.90, 0.975)]:
        d = 0.46
        f0 = 202 * m
        f = glide([(0.0, f0 * 0.95), (0.09, f0), (d * 0.75, f0 * 0.99), (d, f0 * 0.94)], d)
        v = tone(f, d, spectrum=(1.0, 0.07, 0.018), rng=rng, jitter=0.005, jitter_hz=6,
                 vib_hz=5.0, vib_depth=0.004, vib_delay=0.1)
        br = bandpass(noise(d, "pink", rng), 180, 900) * 0.07
        a = env([(0.0, 0.0), (0.055, 1.0), (d * 0.7, 0.85), (d, 0.0)], d)
        x = (v + br) * a
        x = formant(x, [(230, 3.0, 1.0), (620, 3.5, 0.18)], dry=0.45)
        x = bandpass(x, 0, 1200)
        mix_at(out, x, t0, amp)
    return reverb(out, amount=0.48, taps=[(0.16, 0.24), (0.31, 0.13), (0.50, 0.07)],
                  size=2.0, decay=0.66, damp_hz=900, tail_s=1.6)


def c_porcupine_moan(rng):
    """They really do sound like this: a rising nasal whine that breaks into a grunt."""
    dur = 1.7
    out = np.zeros(nsamp(dur))
    # the whine
    d1 = 1.10
    f1 = glide([(0.0, 252), (0.25, 330, 0.8), (0.75, 440), (d1, 492)], d1)
    v1 = voice(f1, d1, rng, spectrum=SPEC_NASAL, jitter=0.035, jitter_hz=15,
               sub=0.18, chaos=0.55, chaos_hz=8, vib_hz=6.5, vib_depth=0.030,
               vib_delay=0.25, breath=0.18, breath_band=(600, 4500))
    a1 = env([(0.0, 0.0), (0.10, 0.7), (0.55, 1.0), (0.95, 0.9), (d1, 0.25)], d1)
    x1 = formant(v1 * a1, [(900, 4.5, 1.0), (1800, 5.0, 0.8), (3100, 5.0, 0.25)], dry=0.12)
    mix_at(out, x1, 0.0, 1.0)
    # the grunt it collapses into
    d2 = 0.42
    f2 = glide([(0.0, 168), (0.08, 148), (d2, 118)], d2)
    v2 = voice(f2, d2, rng, spectrum=saw_spec(14, 0.8), jitter=0.06, jitter_hz=20,
               sub=0.38, chaos=0.8, chaos_hz=14, breath=0.24, breath_band=(300, 2600))
    a2 = env([(0.0, 0.0), (0.02, 1.0), (d2 * 0.55, 0.8), (d2, 0.0)], d2)
    x2 = formant(v2 * a2, [(420, 4.0, 1.0), (980, 4.5, 0.55), (1900, 5.0, 0.18)], dry=0.15)
    mix_at(out, 0.9 * np.tanh(1.8 * x2), 1.12, 0.85)
    return reverb(out, amount=0.26, taps=[(0.09, 0.18), (0.19, 0.09)],
                  size=1.3, decay=0.48, damp_hz=2600, tail_s=0.9)


def c_otter_chirp(rng):
    """Quick high chirping whistles. Playful — irregular spacing does that."""
    dur = 1.45
    out = np.zeros(nsamp(dur))
    t = 0.03
    while t < dur - 0.12:
        d = float(rng.uniform(0.045, 0.085))
        f0 = float(rng.uniform(2250, 3350))
        up = rng.random() < 0.65
        if up:
            f = glide([(0.0, f0 * 0.78), (d * 0.4, f0), (d, f0 * 1.10)], d)
        else:
            f = glide([(0.0, f0 * 0.92), (d * 0.3, f0 * 1.12), (d, f0 * 0.86)], d)
        v = tone(f, d, spectrum=(1.0, 0.16, 0.05), rng=rng, jitter=0.008, jitter_hz=45)
        nb = bandpass(noise(d, "white", rng), 2200, 7000) * 0.07
        a = env([(0.0, 0.0), (0.007, 1.0), (d * 0.6, 0.85), (d, 0.0)], d)
        x = formant((v + nb) * a, [(2900, 2.8, 1.0), (5200, 3.2, 0.3)], dry=0.45)
        mix_at(out, x, t, float(rng.uniform(0.65, 1.0)))
        t += float(rng.uniform(0.085, 0.21))
    return reverb(out, amount=0.26, taps=[(0.09, 0.18), (0.19, 0.09)],
                  size=1.4, decay=0.46, damp_hz=4500, tail_s=0.8)


def c_crickets(rng):
    """Night bed. Short buzzy ~4 kHz pulse groups on a steady rhythm, 8 s seamless."""
    dur = 8.0
    n = nsamp(dur)
    out = np.zeros(n)
    n_voices = 26
    for _ in range(n_voices):
        f0 = float(rng.uniform(3650, 4600))
        # loosely synchronised, as real crickets are
        period = 0.40 * float(rng.uniform(0.92, 1.08))
        phase = float(rng.uniform(0.0, period))
        dist = float(rng.uniform(3.0, 55.0))
        gain = (5.0 / max(5.0, dist)) ** 0.8
        n_pulse = int(rng.integers(3, 5))
        pd, gap = 0.014, 0.009
        cd = n_pulse * (pd + gap)
        chirp = np.zeros(nsamp(cd))
        for k in range(n_pulse):
            p = tone(f0, pd, spectrum=(1.0, 0.30, 0.10), rng=rng, jitter=0.006, jitter_hz=80)
            pa = env([(0.0, 0.0), (0.0015, 1.0), (pd * 0.6, 0.7), (pd, 0.0)], pd)
            mix_at(chirp, p * pa, k * (pd + gap), 1.0 - 0.06 * k)
        if dist > 14.0:
            chirp = bandpass(chirp, 0, max(4200.0, 11000.0 * math.exp(-dist / 70.0)))
        t = phase
        while t < dur:
            mix_wrapped(out, chirp, t + float(rng.uniform(-0.02, 0.02)),
                        gain * float(rng.uniform(0.8, 1.0)))
            t += period * float(rng.uniform(0.96, 1.04))
    # the far field, as a wash
    wash = bandpass(noise(dur + 0.4, "white", rng), 3400, 5600)
    wash = crossfade_loop(wash, 0.4)
    wash = pad_to(wash, dur)
    mod = 1.0 + 0.30 * periodic_mod(n, dur, rng, cycles=(5, 9, 13))
    out += 0.07 * wash * mod
    return out


def c_blackflies(rng):
    """The nagging one. Detuned ~600 Hz buzzes, doppler drift, two close passes.

    Perfectly periodic by construction: every modulator has a whole number of
    cycles per loop and every carrier phase is loopified, so this needs no
    crossfade at all.
    """
    dur = 6.0
    n = nsamp(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)

    for vi in range(6):
        base = float(rng.uniform(545, 690))
        # doppler-ish drift + a slow amplitude approach/recede, both loop-periodic
        drift = periodic_mod(n, dur, rng, cycles=(1, 2, 3), depth=0.075)
        f = base * (1.0 + drift)
        ph, inst = phasor(f, dur, rng)
        # A constant offset AFTER loopify keeps the loop exact (it shifts every
        # sample equally) but stops all six voices crossing zero together at the
        # seam, which would put one audible phase-pinch per loop into the bed.
        ph = loopify_phase(ph, dur) + rng.random() * 2 * np.pi
        spec = saw_spec(7, 0.85)
        v = stack(ph, inst, spec)
        amp = 0.35 + 0.65 * (0.5 + 0.5 * periodic_mod(n, dur, rng, cycles=(1, 3), depth=1.0))
        wob = 1.0 + 0.22 * periodic_mod(n, dur, rng, cycles=(11, 17, 23), depth=1.0)
        out += v * amp * wob * float(rng.uniform(0.55, 1.0))

    # two close passes: loud, pitch swelling up then down, wrapped in time
    for cyc, centre in ((1, 0.30), (1, 0.74)):
        pass_f = 640.0 * (1.0 + 0.14 * np.cos(2 * np.pi * (t / dur - centre)))
        ph, inst = phasor(pass_f, dur, rng)
        ph = loopify_phase(ph, dur) + rng.random() * 2 * np.pi
        v = stack(ph, inst, saw_spec(6, 0.8))
        # a narrow gaussian bump in loop-space, so it wraps cleanly
        dphase = np.abs(((t / dur - centre + 0.5) % 1.0) - 0.5)
        gate = np.exp(-(dphase / 0.055) ** 2)
        out += 0.9 * v * gate

    out = formant(out, [(620, 2.5, 1.0), (1250, 3.0, 0.55), (2400, 3.5, 0.25),
                        (4200, 4.0, 0.08)], dry=0.30)
    out = bandpass(out, 240, 6500)
    return out


# ==========================================================================
# 7. registry
# ==========================================================================
# key, builder, category, loop, one-line note for the manifest

REGISTRY = [
    # --- Tier A: the audio landmarks -------------------------------------
    ("loon_wail", c_loon_wail, "call", False,
     "Long mournful rising-then-falling glissando with a far-shore echo. THE sound of Maine."),
    ("loon_tremolo", c_loon_tremolo, "call", False,
     "The 'crazy laugh' — fast amplitude and pitch warble on a held tone."),
    ("loon_yodel", c_loon_yodel, "call", False,
     "Territorial: a rising note breaking into a repeating jagged undulation."),
    ("barred_owl", c_barred_owl, "call", False,
     "'Who-cooks-for-you, who-cooks-for-you-ALL' — 8 hoots in two phrases, last one drawn out."),
    ("great_horned_owl", c_great_horned_owl, "call", False,
     "Five deep soft muffled hoots around 250 Hz with the classic middle stutter."),
    ("coyote_howl", c_coyote_howl, "call", False,
     "A rising howl that breaks into yips."),
    ("coyote_chorus", c_coyote_chorus, "call", False,
     "The pack: five detuned, time-offset howls at different distances."),
    ("grouse_drum", c_grouse_drum, "call", False,
     "Ruffed grouse wing-drumming: 48 deep thumps accelerating from 0.42 s to a blur."),
    ("peepers", c_peepers, "bed", True,
     "Spring peeper chorus — 34 overlapping voices, 8 s seamless loop."),
    ("raven_kraa", c_raven_kraa, "call", False,
     "Three harsh low rasping croaks, noise-heavy with hard formants."),

    # --- Tier B ----------------------------------------------------------
    ("moose_bellow", c_moose_bellow, "call", False,
     "Long low groaning bellow, pitch dropping, breathy and rough."),
    ("moose_cow_call", c_moose_cow_call, "call", False,
     "The rising, whining, nasal cow moan."),
    ("bear_huff", c_bear_huff, "call", False,
     "Three explosive breathy huffs plus a jaw-pop click."),
    ("bear_growl", c_bear_growl, "call", False,
     "Low rumbling growl with chaotic subharmonics."),
    ("deer_snort", c_deer_snort, "call", False,
     "The alarm: explosive noise burst then a descending whistle-wheeze."),
    ("beaver_slap", c_beaver_slap, "call", False,
     "One sharp tail slap: crack, low water body, spray and rising bubbles."),
    ("red_squirrel_scold", c_red_squirrel_scold, "call", False,
     "Machine-gun chatter — three intro chips then a long rattling trill."),
    ("blue_jay_scream", c_blue_jay_scream, "call", False,
     "Two harsh descending screeches."),
    ("crow_caw", c_crow_caw, "call", False,
     "Three harsh mid-frequency caws."),
    ("chickadee_dee", c_chickadee_dee, "call", False,
     "'Chicka-dee-dee-dee' — two clear intro notes then four buzzy descending dees."),
    ("chickadee_song", c_chickadee_song, "call", False,
     "The whistled 'fee-bee' — a clear note and one a whole step down."),
    ("turkey_gobble", c_turkey_gobble, "call", False,
     "Rapid burbling cascade driven by chaotic sample-and-hold FM/AM."),
    ("woodcock_peent", c_woodcock_peent, "call", False,
     "A single buzzy nasal 'peent'."),
    ("woodcock_twitter", c_woodcock_twitter, "call", False,
     "High wavering wing-feather twittering from the sky dance."),
    ("heron_croak", c_heron_croak, "call", False,
     "One harsh prehistoric 'frahnk'."),
    ("goose_honk", c_goose_honk, "call", False,
     "Two nasal honks — the short 'ah' and the rising 'HONK'."),
    ("goose_skein", c_goose_skein, "call", False,
     "A V passing over: eight honks at varying distance, farther = quieter and duller."),
    ("loon_chick", c_loon_chick, "call", False,
     "Soft short peeps."),
    ("fisher_scream", c_fisher_scream, "call", False,
     "The scream in the dark: accelerating rise, flickering period-doubling, hard break."),
    ("fox_scream", c_fox_scream, "call", False,
     "A sharp strangled shrieking bark, then a shorter second one."),
    ("lynx_caterwaul", c_lynx_caterwaul, "call", False,
     "A long wavering yowl sagging into a growl."),
    ("bullfrog", c_bullfrog, "call", False,
     "'Jug-o-rum' — three low pulsed notes."),
    ("wood_thrush", c_wood_thrush, "call", False,
     "Flutey rising spiral sung by two syrinxes at once, then a trill."),
    ("pileated_drum", c_pileated_drum, "call", False,
     "Fast hard even roll on hollow wood, 21 hits, with forest slap-back."),
    ("pileated_call", c_pileated_call, "call", False,
     "The maniacal laughing 'kuk-kuk-kuk' cascade."),
    ("eagle_cry", c_eagle_cry, "call", False,
     "Thin descending chittering whistles — the real eagle, not the movie hawk."),
    ("osprey_whistle", c_osprey_whistle, "call", False,
     "A series of clear whistles, the series rising then falling."),
    ("snowy_owl_hoot", c_snowy_owl_hoot, "call", False,
     "Two deep booming hoots in a big open space."),
    ("porcupine_moan", c_porcupine_moan, "call", False,
     "A weird rising nasal whine that collapses into a grunt."),
    ("otter_chirp", c_otter_chirp, "call", False,
     "Quick high playful chirping whistles."),
    ("crickets", c_crickets, "bed", True,
     "Night bed — dense buzzy 4 kHz pulse groups on a steady rhythm, 8 s seamless loop."),
    ("blackflies", c_blackflies, "bed", True,
     "Nagging insect whine bed — detuned 600 Hz buzz, doppler drift, 6 s seamless loop."),
]


# ==========================================================================
# 8. post-processing, writing, CLI
# ==========================================================================

def softclip(x, ceiling=0.92):
    """Smooth tanh limiter: transparent well below the ceiling, never above it."""
    return ceiling * np.tanh(x / ceiling)


def trim_tail(x, floor_db=-62.0, keep_ms=45.0):
    """Cut the inaudible end off a reverb tail.

    Every call is rendered with room for its tail to ring out; most of that is
    below hearing by the end. Trimming keeps durations honest and the whole set
    a couple of MB smaller.
    """
    peak = float(np.max(np.abs(x)))
    if peak < 1e-9:
        return x
    thr = peak * (10.0 ** (floor_db / 20.0))
    above = np.nonzero(np.abs(x) > thr)[0]
    if len(above) == 0:
        return x
    end = min(len(x), int(above[-1]) + nsamp(keep_ms / 1000.0))
    return x[:end]


def finish(x, loop=False, bed=False, fade_ms=9.0, lead_ms=6.0,
           target_peak=0.89, target_rms=0.145):
    """Normalise, soft-clip, fade. Nothing leaves here clipped or inaudible."""
    x = np.asarray(x, dtype=np.float64)
    if not np.all(np.isfinite(x)):
        x = np.nan_to_num(x, nan=0.0, posinf=0.0, neginf=0.0)

    # DC / subsonic guard. bandpass() is an FFT mask, so it is CIRCULAR: on a
    # one-shot that wraps the attack transient around onto the tail (the beaver
    # slap was leaving -30 dB of its own crack in its last 250 ms). Pad it out
    # for non-loop files and use a gentle skirt, which also shortens the
    # filter's ringing. Loops WANT the circular behaviour — that is what keeps
    # them seamless — so they are filtered as-is.
    if loop:
        x = bandpass(x, 22.0, None, edge_oct=1.0)
    else:
        g = nsamp(0.25)
        x = bandpass(np.concatenate([np.zeros(g), x, np.zeros(g)]),
                     22.0, None, edge_oct=1.0)[g:g + len(x)]

    if not loop:
        x = trim_tail(x)
        # A few ms of leading silence so the fade-in ramps over nothing. Without
        # it a 9 ms fade flattens the attack of anything that starts on a
        # transient — the beaver slap and the bear jaw-pop lose 2-3 dB of crack.
        x = np.concatenate([np.zeros(nsamp(lead_ms / 1000.0)), x])

    peak = float(np.max(np.abs(x)))
    if peak < 1e-9:
        return np.zeros_like(x)

    if bed:
        # beds normalise by RMS — one loud chirp must not drag the whole bed down
        rms = float(np.sqrt(np.mean(x * x)))
        x = x * (target_rms / max(rms, 1e-9))
        x = softclip(x, 0.90)
        p = float(np.max(np.abs(x)))
        if p > 0.95:
            x *= 0.95 / p
    else:
        x = x / peak * 0.95
        x = softclip(x, 0.92)
        p = float(np.max(np.abs(x)))
        x = x / max(p, 1e-9) * target_peak

    if not loop:
        # 5–15 ms cosine fades. Loops get none: they are seamless by
        # construction, and a fade would put a dip at every wrap point.
        nf = min(nsamp(fade_ms / 1000.0), len(x) // 2)
        if nf > 1:
            w = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, nf))
            x[:nf] *= w
            x[-nf:] *= w[::-1]
    return x


def write_wav(path, x):
    data = np.clip(x, -1.0, 1.0)
    pcm = np.round(data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return len(pcm)


def call_rng(master_seed, key):
    """Per-call RNG derived from the master seed.

    crc32 (not hash()) because python randomises string hashing per process —
    this has to give the same bytes on every run and every machine. Changing
    one call cannot reshuffle any other file.
    """
    h = zlib.crc32(key.encode("utf-8")) & 0xFFFFFFFF
    return np.random.default_rng((int(master_seed) * 1000003 + h) & 0xFFFFFFFF)


def db(v):
    return -99.0 if v <= 1e-9 else 20.0 * math.log10(v)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Synthesise Maine wildlife calls as 16-bit mono WAVs (numpy only).")
    ap.add_argument("--out", default=DEFAULT_OUT, help=f"output directory (default {DEFAULT_OUT})")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED,
                    help=f"master seed (default {DEFAULT_SEED})")
    ap.add_argument("--only", default=None,
                    help="comma-separated keys to render (default: all)")
    ap.add_argument("--list", action="store_true", help="list keys and exit")
    ap.add_argument("--quiet", action="store_true", help="suppress the summary table")
    args = ap.parse_args(argv)

    if args.list:
        for key, _, cat, loop, note in REGISTRY:
            print(f"{key:22s} {cat:5s} {'loop' if loop else '    '}  {note}")
        return 0

    wanted = None
    if args.only:
        wanted = {k.strip() for k in args.only.split(",") if k.strip()}
        known = {k for k, *_ in REGISTRY}
        for k in sorted(wanted - known):
            print(f"warning: unknown key {k!r}", file=sys.stderr)

    os.makedirs(args.out, exist_ok=True)

    manifest = {}
    rows = []
    total_bytes = 0
    total_secs = 0.0

    for key, builder, category, loop, note in REGISTRY:
        if wanted is not None and key not in wanted:
            continue
        rng = call_rng(args.seed, key)
        x = builder(rng)
        x = finish(x, loop=loop, bed=(category == "bed"))

        path = os.path.join(args.out, f"{key}.wav")
        n = write_wav(path, x)
        nbytes = os.path.getsize(path)
        secs = n / SR
        rms = float(np.sqrt(np.mean(x * x))) if n else 0.0
        peak = float(np.max(np.abs(x))) if n else 0.0
        # Proof that a loop actually loops, via the SECOND difference across the
        # seam. A raw |x[0]-x[-1]| step says nothing — a seam can legitimately
        # land on the steepest part of a waveform — but a genuine discontinuity
        # of size D always shows up as a ~2D spike in curvature. Normalised
        # against the file's own d2, so ~1 is indistinguishable from anywhere
        # else in the signal and >5 is an audible click.
        wrap = 0.0
        if loop and n > 8:
            d2 = np.diff(x, 2)
            ref = float(np.sqrt(np.mean(d2 * d2)))
            seam = np.abs(np.diff(np.concatenate([x[-2:], x[:2]]), 2))
            wrap = float(np.max(seam)) / max(ref, 1e-12)

        manifest[key] = {
            "file": f"{key}.wav",
            "seconds": round(secs, 3),
            "bytes": nbytes,
            "loop": bool(loop),
            "category": category,
            "note": note,
        }
        rows.append((key, secs, nbytes, category, loop, db(rms), db(peak), wrap))
        total_bytes += nbytes
        total_secs += secs

    mpath = os.path.join(args.out, "manifest.json")
    with open(mpath, "w", encoding="utf-8") as fh:
        # no timestamp on purpose: same seed must give byte-identical output
        json.dump({
            "version": 1,
            "generator": "tools/crittercalls.py",
            "sample_rate": SR,
            "channels": 1,
            "bit_depth": 16,
            "seed": args.seed,
            "calls": manifest,
        }, fh, indent=2, sort_keys=True)
        fh.write("\n")

    if not args.quiet:
        print()
        print(f"crittercalls — seed {args.seed} → {args.out}")
        print("-" * 88)
        print(f"{'key':<22}{'sec':>7}{'KB':>8}  {'cat':<5}{'loop':<6}"
              f"{'rms dB':>9}{'peak dB':>9}{'seam':>8}")
        print("-" * 88)
        for key, secs, nbytes, cat, loop, rdb, pdb, wrap in rows:
            print(f"{key:<22}{secs:>7.2f}{nbytes / 1024.0:>8.1f}  {cat:<5}"
                  f"{('yes' if loop else '-'):<6}{rdb:>9.1f}{pdb:>9.1f}"
                  f"{(f'{wrap:.2f}x' if loop else '-'):>8}")
        print("-" * 88)
        print("seam = curvature spike across the loop point / the file's own "
              "rms curvature; <=1 inaudible, >5 clicks")
        print(f"{len(rows)} files  {total_secs:.1f} s  "
              f"{total_bytes / 1048576.0:.2f} MB  (+ manifest.json)")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
