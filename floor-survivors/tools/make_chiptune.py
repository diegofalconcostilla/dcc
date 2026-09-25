"""Renders DCC's 8-bit music: five layered loop stems plus a few one-shot stingers,
as 16-bit mono WAVs under assets/audio/. No samples, no external assets — every
sound is synthesized here (square/pulse, quantized triangle, LFSR-ish noise), so
the music is original and license-free.

Run from the game folder:  python tools/make_chiptune.py
(add `sfx` to render only the sound effects + the achievement/loot stingers).
Sound effects are short one-shots played through AudioManager.play_sfx.

All five stems share one tempo/length and are rendered so each loops seamlessly
(note tails are folded back onto the start; steady drones use whole numbers of
cycles), so the game can play them together and fade layers in/out with the
System AI's live threat. See plan.md's "Music" section.

Key: A minor, 132 BPM, 16 bars. Game-show swagger over dread.
"""
import os
import wave

import numpy as np

SR = 32000
BPM = 132
STEP = 60.0 / BPM / 4.0  # one 16th note, seconds
BARS = 16
STEPS = BARS * 16
N = int(round(STEPS * STEP * SR))  # loop length in samples
TAIL = SR * 2
rng = np.random.default_rng(1234)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def step_pos(step):
    return int(round(step * STEP * SR))


# ---------------------------------------------------------------- oscillators
def _phase(freq, n, vibrato=0.0, vib_delay=0.15):
    t = np.arange(n) / SR
    f = np.full(n, float(freq))
    if vibrato:
        f = f * (1.0 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - vib_delay) / 0.2, 0, 1))
    return np.cumsum(f) / SR


def pulse(freq, n, duty=0.5, vibrato=0.0):
    return np.where((_phase(freq, n, vibrato) % 1.0) < duty, 1.0, -1.0)


def tri(freq, n):
    x = 4.0 * np.abs((_phase(freq, n) % 1.0) - 0.5) - 1.0
    return np.round(x * 7.5) / 7.5  # NES-style 4-bit triangle


def noise(n):
    return rng.uniform(-1.0, 1.0, n)


def env(n, attack=0.004, decay=0.0, release=0.006):
    t = np.arange(n) / SR
    e = np.exp(-t * decay) if decay else np.ones(n)
    a = max(1, int(attack * SR))
    e[:a] *= np.linspace(0, 1, a)
    r = min(n, max(1, int(release * SR)))
    e[-r:] *= np.linspace(1, 0, r)
    return e


def place(buf, sig, start):
    if start >= len(buf):
        return
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start]


def fold(buf):
    """Wrap the tail past the loop end back onto the start so the loop is seamless."""
    out = buf[:N].copy()
    tail = buf[N:]
    out[: len(tail)] += tail
    return out


def normalize(x, peak=0.85):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def loop_freq(f):
    """Nudge a steady tone's frequency so a whole number of cycles fits the loop."""
    return round(f * N / SR) * SR / N


# ------------------------------------------------------------------ voices
def note_pulse(buf, step, midi, length, vol, duty=0.25, decay=6.0, vibrato=0.0):
    n = int(length * STEP * SR)
    sig = pulse(hz(midi), n, duty, vibrato) * env(n, decay=decay) * vol
    place(buf, sig, step_pos(step))


def note_tri(buf, step, midi, length, vol, decay=5.0):
    n = int(length * STEP * SR)
    sig = tri(hz(midi), n) * env(n, decay=decay) * vol
    place(buf, sig, step_pos(step))


def kick(buf, step, vol=0.9):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    f = 42 + 130 * np.exp(-t * 32)
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 16) * vol
    sig[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
    place(buf, sig, step_pos(step))


def snare(buf, step, vol=0.6):
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    sig = (noise(n) * 0.75 + tri(190, n) * 0.4) * np.exp(-t * 24) * vol
    place(buf, sig, step_pos(step))


def hat(buf, step, vol=0.25, open_=False):
    n = int((0.2 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    x = noise(n)
    x = np.concatenate([[0], np.diff(x)])  # crude high-pass
    place(buf, x * np.exp(-t * (20 if open_ else 95)) * vol, step_pos(step))


# ------------------------------------------------------------------ the song
# Chords per bar. Bars 1-8: Am F C G x2 ; bars 9-16: Am F Dm E x2 (E has G#
# for the harmonic-minor "dread" pull back to Am).
PROG = ["Am", "F", "C", "G"] * 2 + ["Am", "F", "Dm", "E"] * 2
CHORD = {  # pad tones
    "Am": [57, 60, 64], "F": [53, 57, 60], "C": [55, 60, 64],
    "G": [55, 59, 62], "Dm": [53, 57, 62], "E": [56, 59, 64],
}
ROOT = {"Am": 45, "F": 41, "C": 48, "G": 43, "Dm": 50, "E": 40}
ARP = {"Am": [69, 72, 76, 72], "F": [65, 69, 72, 69], "Dm": [74, 77, 81, 77], "E": [76, 80, 83, 80]}

# Lead hook, bars 1-8: (step, midi, length in 16ths)
HOOK_A = [
    [(0, 69, 2), (3, 72, 1), (4, 76, 3), (8, 74, 2), (10, 72, 2), (12, 69, 4)],
    [(0, 65, 2), (3, 69, 1), (4, 72, 3), (8, 77, 2), (10, 76, 2), (12, 72, 4)],
    [(0, 72, 2), (3, 76, 1), (4, 79, 3), (8, 76, 2), (10, 74, 2), (12, 72, 4)],
    [(0, 71, 2), (3, 74, 1), (4, 79, 2), (6, 78, 2), (8, 74, 4), (12, 71, 2), (14, 67, 2)],
]
HOOK_TURN = [(0, 71, 2), (2, 74, 2), (4, 79, 4), (8, 83, 4), (12, 81, 4)]  # bar 8 variation


def render_pad():
    buf = np.zeros(N + TAIL)
    for bar, ch in enumerate(PROG):
        for m in CHORD[ch]:
            n = int(16 * STEP * SR)
            sig = pulse(hz(m), n, 0.25, vibrato=0.004) * env(n, attack=0.12, release=0.08)
            place(buf, sig * 0.11, step_pos(bar * 16))
    return normalize(fold(buf), 0.6)


def render_bass():
    buf = np.zeros(N + TAIL)
    for bar, ch in enumerate(PROG):
        r = ROOT[ch]
        b = bar * 16
        for s, m, ln in [(0, r, 2), (2, r, 1), (4, r + 12, 1), (6, r, 2), (8, r, 2), (10, r, 1), (12, r + 7, 1), (14, r + 12 if bar % 2 else r, 2)]:
            note_tri(buf, b + s, m, ln, 0.85, decay=7.0)
    return normalize(fold(buf), 0.8)


def render_drums():
    buf = np.zeros(N + TAIL)
    for bar in range(BARS):
        b = bar * 16
        for s in (0, 4, 8, 12):
            kick(buf, b + s)
        if bar % 2:
            kick(buf, b + 10, 0.7)
        for s in (4, 12):
            snare(buf, b + s)
        for s in range(0, 16, 2):
            hat(buf, b + s, 0.22 if s % 4 else 0.3, open_=(s == 14))
        hat(buf, b + 15, 0.1)
        if bar in (7, 15):  # fill
            for s in (12, 13, 14, 15):
                snare(buf, b + s, 0.45)
    return normalize(fold(buf), 0.85)


def render_lead():
    buf = np.zeros(N + TAIL)
    for bar in range(8):
        events = HOOK_TURN if bar == 7 else HOOK_A[bar % 4]
        for s, m, ln in events:
            note_pulse(buf, bar * 16 + s, m, ln, 0.3, duty=0.25, decay=4.0, vibrato=0.006 if ln >= 3 else 0.0)
    for bar in range(8, 16):
        pat = ARP[PROG[bar]]
        for i in range(16):
            note_pulse(buf, bar * 16 + i, pat[i % 4] + (12 if bar >= 14 else 0), 1, 0.2, duty=0.125, decay=16.0)
    return normalize(fold(buf), 0.7)


def render_menace():
    """Dread layer: beating minor-2nd drone, lub-dub heartbeat, tritone stabs, riser."""
    buf = np.zeros(N + TAIL)
    t = np.arange(N) / SR
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (BARS * 2) * np.arange(N) / N)  # whole cycles -> loops cleanly
    drone = np.zeros(N)
    for m, v in ((33, 0.5), (34, 0.5), (45, 0.25), (51, 0.18)):  # A1, Bb1 (clash), A2, Eb3 (tritone)
        f = loop_freq(hz(m))
        drone += np.where(((t * f) % 1.0) < 0.125, 1.0, -1.0) * v
    buf[:N] += drone * 0.22 * lfo
    for beat8 in range(STEPS // 8):  # heartbeat: lub at step 0, dub at step 3 of every half bar
        base = beat8 * 8
        for s, v in ((0, 0.9), (3, 0.6)):
            n = int(0.16 * SR)
            tt = np.arange(n) / SR
            f = 38 + 30 * np.exp(-tt * 40)
            place(buf, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 20) * v * 0.9, step_pos(base + s))
    for bar in range(0, BARS, 2):  # tritone stab on every other bar
        note_pulse(buf, bar * 16, 57, 4, 0.22, duty=0.25, decay=7.0)
        note_pulse(buf, bar * 16, 63, 4, 0.22, duty=0.25, decay=7.0)
    for bar in range(0, BARS, 4):  # 2-bar noise riser ending on each 4-bar boundary
        n = int(32 * STEP * SR)
        x = np.concatenate([[0], np.diff(noise(n))]) * (np.linspace(0, 1, n) ** 2) * 0.28
        place(buf, x, step_pos((bar + 4) * 16) - n)
    return normalize(fold(buf), 0.8)


# ------------------------------------------------------------------ stingers
def seq(events, length_s, vol=0.5):
    """events: (start_s, midi, dur_s, duty, decay). Pulse-voice one-shot."""
    n = int(length_s * SR)
    buf = np.zeros(n)
    for start, m, dur, duty, decay in events:
        k = int(dur * SR)
        place(buf, pulse(hz(m), k, duty) * env(k, decay=decay) * vol, int(start * SR))
    return normalize(buf, 0.8)


def sting_level_up():
    return seq([(i * 0.07, m, 0.12, 0.25, 8) for i, m in enumerate([69, 72, 76, 81])] + [(0.32, 88, 0.5, 0.125, 5)], 1.0)


def sting_floor_clear():
    return seq([(0.0, 72, 0.15, 0.25, 3), (0.15, 76, 0.15, 0.25, 3), (0.3, 79, 0.15, 0.25, 3), (0.45, 84, 0.9, 0.25, 2.5), (0.45, 76, 0.9, 0.5, 2.5), (0.45, 67, 0.9, 0.5, 2.5)], 1.6)


def sting_boss():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    buf = (pulse(hz(33), n, 0.5) * 0.5 + pulse(hz(39), n, 0.5) * 0.5) * np.exp(-t * 2.2)
    buf += np.concatenate([[0], np.diff(noise(n))]) * np.exp(-t * 9) * 0.5
    sweep = np.sin(2 * np.pi * np.cumsum(220 * np.exp(-t * 1.5)) / SR) * np.exp(-t * 3) * 0.5
    return normalize(buf + sweep, 0.85)


def sting_game_over():
    """Sad-trombone wah-wah-wah-waaah, in square waves."""
    n = int(2.4 * SR)
    buf = np.zeros(n)
    for start, m, dur, slide in [(0.0, 55, 0.4, 0), (0.45, 54, 0.4, 0), (0.9, 53, 0.4, 0), (1.35, 52, 1.0, -2.5)]:
        k = int(dur * SR)
        tt = np.arange(k) / SR
        f = hz(m) * 2 ** ((slide * tt / dur) / 12.0) * (1 + 0.012 * np.sin(2 * np.pi * 6 * tt))
        x = np.where((np.cumsum(f) / SR) % 1.0 < 0.5, 1.0, -1.0) * env(k, attack=0.02, decay=0.6, release=0.05) * 0.5
        place(buf, x, int(start * SR))
    return normalize(buf, 0.8)


# -------------------------------------------------------------- sound effects
def sweep(f0, f1, dur, duty=0.5, decay=6.0, vol=0.6):
    """Pulse voice gliding exponentially from f0 to f1 Hz."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur)
    ph = np.cumsum(f) / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0) * env(n, decay=decay) * vol


def noise_burst(dur, decay, vol=0.6, smooth=0):
    """Decaying noise; `smooth` (moving-average width) darkens it toward a thud."""
    n = int(dur * SR)
    x = noise(n)
    if smooth > 1:
        x = np.convolve(x, np.ones(smooth) / smooth, mode="same") * np.sqrt(smooth)
    return x * env(n, decay=decay) * vol


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def sfx_hit():
    return normalize(mix(sweep(1100, 420, 0.06, 0.25, 30, 0.7), noise_burst(0.04, 60, 0.25)), 0.55)


def sfx_kill():
    return normalize(mix(sweep(520, 110, 0.16, 0.5, 11, 0.6), noise_burst(0.12, 22, 0.45, 3)), 0.7)


def sfx_hurt():
    return normalize(mix(sweep(240, 80, 0.24, 0.5, 7, 0.7), noise_burst(0.18, 14, 0.4, 2)), 0.8)


def sfx_pickup():
    a = sweep(1046, 1046, 0.035, 0.25, 20, 0.6)
    b = sweep(1568, 1568, 0.07, 0.25, 22, 0.6)
    out = np.zeros(int(0.12 * SR))
    place(out, a, 0)
    place(out, b, int(0.035 * SR))
    return normalize(out, 0.5)


def sfx_bomb_throw():
    return normalize(sweep(260, 760, 0.14, 0.25, 9, 0.6), 0.6)


def sfx_bomb_boom():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(130 * np.exp(-t * 5) + 30) / SR) * np.exp(-t * 5) * 0.9
    return normalize(mix(thump, noise_burst(0.7, 6, 0.8, 5)), 0.9)


def sfx_laser():
    return normalize(mix(sweep(2000, 260, 0.18, 0.125, 9, 0.6), sweep(1000, 130, 0.18, 0.5, 9, 0.35)), 0.7)


def sfx_dodge():
    n = int(0.16 * SR)
    hiss = np.concatenate([[0], np.diff(noise(n))]) * np.sin(np.pi * np.arange(n) / n) * 0.7
    return normalize(hiss, 0.45)


def sfx_ui_move():
    return normalize(sweep(1300, 1300, 0.03, 0.25, 40, 0.5), 0.4)


def sfx_ui_click():
    out = np.zeros(int(0.09 * SR))
    place(out, sweep(760, 760, 0.04, 0.25, 25, 0.6), 0)
    place(out, sweep(1140, 1140, 0.05, 0.25, 25, 0.6), int(0.04 * SR))
    return normalize(out, 0.55)


def sting_achievement():
    """Bright rising game-show 'ding-ding-ding-DING'."""
    notes = [(0.0, 76), (0.09, 79), (0.18, 83), (0.27, 88)]
    ev = [(t0, m, 0.14, 0.25, 7) for t0, m in notes] + [(0.4, 95, 0.75, 0.125, 3.5), (0.4, 88, 0.75, 0.5, 3.5), (0.4, 83, 0.75, 0.5, 3.5)]
    return seq(ev, 1.3)


def sting_loot():
    """Coin-chime plus a falling sparkle — the loot box popping open."""
    ev = [(0.0, 83, 0.07, 0.5, 8), (0.075, 88, 0.55, 0.5, 4)]
    ev += [(0.3 + i * 0.06, m, 0.12, 0.125, 9) for i, m in enumerate([100, 96, 93, 91, 88])]
    return seq(ev, 1.0, 0.45)



def write_wav(name, x):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print("wrote %-22s %5.1fs  peak %.2f" % (name, len(x) / SR, np.max(np.abs(x))))


if __name__ == "__main__":
    import sys

    sfx_only = "sfx" in sys.argv[1:]
    print("loop = %d bars, %.2fs (%d samples @ %d Hz)" % (BARS, N / SR, N, SR))
    if not sfx_only:
        for name, fn in [("music_pad", render_pad), ("music_bass", render_bass), ("music_drums", render_drums),
                         ("music_lead", render_lead), ("music_menace", render_menace)]:
            write_wav(name + ".wav", fn())
        for name, fn in [("sting_level_up", sting_level_up), ("sting_floor_clear", sting_floor_clear),
                         ("sting_boss", sting_boss), ("sting_game_over", sting_game_over)]:
            write_wav(name + ".wav", fn())
    for name, fn in [("sting_achievement", sting_achievement), ("sting_loot", sting_loot),
                     ("sfx_hit", sfx_hit), ("sfx_kill", sfx_kill), ("sfx_hurt", sfx_hurt), ("sfx_pickup", sfx_pickup),
                     ("sfx_bomb_throw", sfx_bomb_throw), ("sfx_bomb_boom", sfx_bomb_boom), ("sfx_laser", sfx_laser),
                     ("sfx_dodge", sfx_dodge), ("sfx_ui_move", sfx_ui_move), ("sfx_ui_click", sfx_ui_click)]:
        write_wav(name + ".wav", fn())
