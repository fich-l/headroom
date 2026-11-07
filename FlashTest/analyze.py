#!/usr/bin/env python3
"""Analyse XDR Flash Test recordings (frames.csv) → markdown report.

Per mode:
  - steady boost  = mean luminance at rest / OFF at rest (Original should be ~2× in linear light)
  - look vs. Original = mean |log ratio| of the 32×20 luminance grid at rest vs. ORIGINAL at rest
  - per phase (R1 = first visit to Space 2, L1/R2/L2 = later switches, MC = Mission Control):
      white     = frames whose near-white area exceeds OFF's maximum for that phase by > 5 % of the screen
      unboosted = frames whose brightness / OFF (same phase, same time offset) < √(Original's boost)
Pass = 0 white and 0 unboosted frames in every phase.
Usage: analyze.py frames.csv [report.md]
"""
import bisect
import math
import sys

PHASES = ["R1", "L1", "R2", "L2", "MC"]


def load(path):
    frames, events = [], []
    for line in open(path):
        p = line.rstrip("\n").split(",")
        if p[0] == "F":
            frames.append({"t": float(p[1]), "mean": float(p[2]), "w90": float(p[3]), "w99": float(p[4]),
                           "max": float(p[5]), "grid": [float(x) for x in p[7:]]})
        elif p[0] == "E":
            events.append((float(p[1]), p[2]))
    frames.sort(key=lambda f: f["t"])
    return frames, events


def segments(events):
    """mode -> {event name -> time}"""
    out, cur = {}, None
    for t, name in events:
        if name.startswith("mode:"):
            cur = name[5:]
            out[cur] = {"start": t}
        elif cur is not None:
            out[cur][name if not name.startswith("end:") else "end"] = t
    return out


class Timeline:
    def __init__(self, frames):
        self.frames = frames
        self.ts = [f["t"] for f in frames]

    def at(self, t):
        """Last frame at or before t (ScreenCaptureKit only delivers frames when something changes)."""
        i = bisect.bisect_right(self.ts, t) - 1
        return self.frames[max(i, 0)] if self.frames else None

    def between(self, a, b):
        i, j = bisect.bisect_left(self.ts, a), bisect.bisect_left(self.ts, b)
        out = self.frames[i:j]
        prev = self.at(a)  # include the state that was on screen when the phase began
        return ([prev] if prev and (not out or out[0] is not prev) else []) + out


def phase_bounds(seg, phase):
    order = ["R1", "L1", "R2", "L2", "MCopen", "end"]
    key = "MCopen" if phase == "MC" else phase
    a = seg.get(key)
    b = seg.get(order[order.index(key) + 1]) if key in order[:-1] else None
    return a, b


def analyze(frames, events):
    tl = Timeline(frames)
    segs = segments(events)
    rest = {m: tl.at(s["R1"] - 0.05) for m, s in segs.items() if "R1" in s}
    if "OFF" not in segs or "ORIGINAL" not in segs:
        sys.exit("need OFF and ORIGINAL modes in the run for reference")
    off_rest, orig_rest = rest["OFF"], rest["ORIGINAL"]
    k = orig_rest["mean"] / off_rest["mean"]
    unboost_threshold = math.sqrt(k)

    def off_at(phase, offset):
        a, _ = phase_bounds(segs["OFF"], phase)
        return tl.at(a + offset)

    off_white_max = {}
    for ph in PHASES:
        a, b = phase_bounds(segs["OFF"], ph)
        off_white_max[ph] = max((f["w90"] for f in tl.between(a, b)), default=0)

    rows = []
    for mode, seg in segs.items():
        r = rest.get(mode)
        if r is None:
            continue
        boost = r["mean"] / off_rest["mean"]
        look = sum(abs(math.log(max(x, 1e-4) / max(y, 1e-4))) for x, y in zip(r["grid"], orig_rest["grid"])) / len(r["grid"])
        res = {}
        for ph in PHASES:
            a, b = phase_bounds(seg, ph)
            if a is None or b is None:
                continue
            white = unb = n = 0
            for f in tl.between(a, b):
                n += 1
                off = off_at(ph, max(0.0, f["t"] - a))
                if f["w90"] > off_white_max[ph] + 0.05:
                    white += 1
                elif mode != "OFF" and off and f["mean"] / max(off["mean"], 1e-5) < unboost_threshold:
                    unb += 1
            res[ph] = (white, unb, n)
        ok = mode not in ("OFF",) and all(w == 0 and u == 0 for w, u, _ in res.values()) and abs(math.log(boost / k)) < 0.1
        rows.append((mode, boost, look, res, ok))
    return k, rows


def report(k, rows):
    lines = [f"Original's boost at rest: {k:.2f}× (OFF = 1.00×).  "
             "Cells: white frames / unboosted frames / frames.\n",
             "| mode | boost at rest | look vs Original | " + " | ".join(PHASES) + " | pass |",
             "|---|---|---|" + "---|" * len(PHASES) + "---|"]
    for mode, boost, look, res, ok in rows:
        cells = [f"{res[p][0]}/{res[p][1]}/{res[p][2]}" if p in res else "–" for p in PHASES]
        lines.append(f"| `{mode}` | {boost:.2f}× | {look * 100:.1f} % | " + " | ".join(cells) + f" | {'✅' if ok else '❌'} |")
    return "\n".join(lines)


if __name__ == "__main__":
    frames, events = load(sys.argv[1])
    k, rows = analyze(frames, events)
    text = report(k, rows)
    print(text)
    if len(sys.argv) > 2:
        open(sys.argv[2], "w").write(text + "\n")
