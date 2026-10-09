#!/usr/bin/env python3
"""
Trims long battle animations to a smaller frame count without a visible jump when they loop.

Sheets run from a handful of frames to 180. The cap is the median frame count of its kind
(front or back) over every sheet the build packs; a sheet at or under the cap is left alone.
A longer one is cut to a window [start, start + count) of at most `cap` frames chosen so that
the frame that would have followed the window looks like the window's first frame: the loop
then closes on a step as small as any other. Many sheets contain a repeat of their own loop, so
that is often an exact match (Floatzel's 84-frame front is 44 frames repeated, a difference of 0).

A window is only accepted when its seam is no bigger than `--seam` times the sheet's average
frame-to-frame step; otherwise the whole sheet is kept and listed, so nothing jumps.

  python tools/trim_loops.py report                 # dry run: what would be trimmed and saved
  python tools/trim_loops.py write                  # write tools/loop_trims.json
  python tools/trim_loops.py report --only FLOATZEL MASQUERAIN
  python tools/trim_loops.py report --cap mean      # or --cap 60

The normal sheet decides; the shiny sheet keeps the same frames. tools/build_atlas.py applies
loop_trims.json when it packs the atlas.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_atlas as ba  # noqa: E402

ROOT = ba.ROOT
SIDES = ("front", "back")


def load_frames(path: Path) -> list[Image.Image]:
    """The frames of one sheet, premultiplied so a transparent pixel's colour never counts."""
    with Image.open(path) as im:
        img = im.convert("RGBA")
    fs = img.height
    n = max(1, round(img.width / fs))
    return [img.crop((i * fs, 0, (i + 1) * fs, fs)).convert("RGBa") for i in range(n)]


class Sheet:
    """Frame differences of one sheet, computed on demand."""

    def __init__(self, frames: list[Image.Image]):
        self.frames = frames
        self.n = len(frames)
        self._cache: dict[tuple[int, int], float] = {}

    def diff(self, i: int, j: int) -> float:
        """Mean absolute difference of two frames over all four channels (0..255)."""
        i, j = i % self.n, j % self.n
        if i > j:
            i, j = j, i
        key = (i, j)
        hit = self._cache.get(key)
        if hit is None:
            d = ImageChops.difference(self.frames[i], self.frames[j])
            hit = sum(ImageStat.Stat(d).mean) / 4
            self._cache[key] = hit
        return hit

    def step(self) -> float:
        """The average difference between neighbouring frames: what a normal step looks like."""
        if self.n < 2:
            return 0.0
        return sum(self.diff(i, i + 1) for i in range(self.n - 1)) / (self.n - 1)


def best_window(sheet: Sheet, cap: int, min_frac: float = 0.6, tie: float = 0.1):
    """The window of at most `cap` frames whose loop closes best: (start, count, cost), where
    cost is the seam's difference over the sheet's normal step (so 1.0 = as smooth as any step).
    Among windows within `tie` of the best cost the longest wins, then the earliest."""
    n = sheet.n
    floor = max(sheet.step(), 0.5)           # a near-static sheet: any cut is a small absolute change
    k_min = max(2, math.ceil(cap * min_frac))
    candidates = []
    for k in range(min(cap, n - 1), k_min - 1, -1):
        for s in range(0, n - k + 1):
            candidates.append((sheet.diff(s, s + k) / floor, k, s))   # the animation is cyclic
    if not candidates:
        return None
    best = min(c[0] for c in candidates)
    near = [c for c in candidates if c[0] <= best + tie]
    cost, k, s = max(near, key=lambda c: (c[1], -c[2], -c[0]))
    return s, k, cost


def pick_cap(counts: list[int], mode: str) -> int:
    if mode == "median":
        return int(statistics.median(counts))
    if mode == "mean":
        return round(statistics.mean(counts))
    return int(mode)


def analyse(args, only: set[str] | None = None):
    dbk, species = ba.battle_species(args)
    sheets: dict[tuple[str, str], Path] = {}
    for _dex, sid in species:
        stem = dbk.get(sid)
        if stem is None or (only and sid not in only):
            continue
        for side in SIDES:
            path = args.sheets / side / f"{stem}.png"
            if path.exists():
                sheets[(sid, side)] = path
    return sheets


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("report", "write"))
    ba.add_source_args(ap)
    ap.add_argument("--cap", default="median", help="median (default), mean, or a frame count")
    ap.add_argument("--seam", type=float, default=1.15,
                    help="accept a window whose seam is at most this many normal steps (default 1.15)")
    ap.add_argument("--only", nargs="*", help="only these species ids (cap still comes from all sheets)")
    ap.add_argument("--out", type=Path, default=ROOT / "tools" / "loop_trims.json")
    args = ap.parse_args()

    everything = analyse(args)
    wanted = set(args.only) if args.only else None

    # the cap per side comes from every sheet, whatever --only asks to look at
    counts: dict[str, list[int]] = {s: [] for s in SIDES}
    sizes: dict[tuple[str, str], tuple[int, int]] = {}
    for (sid, side), path in everything.items():
        with Image.open(path) as im:
            fs = im.height
            n = max(1, round(im.width / fs))
        counts[side].append(n)
        sizes[(sid, side)] = (n, fs)
    caps = {side: pick_cap(counts[side], args.cap) for side in SIDES}
    print("frame counts  " + "   ".join(
        f"{side}: {len(counts[side])} sheets, median {int(statistics.median(counts[side]))}, "
        f"mean {statistics.mean(counts[side]):.1f}, max {max(counts[side])}, cap {caps[side]}"
        for side in SIDES))

    trims: dict[str, dict[str, list[int]]] = {}
    kept_long: list[tuple[str, str, int, float]] = []
    before = after = 0
    total_area = 0
    seams: list[tuple[float, str, str, int, int]] = []
    for (sid, side), path in sorted(everything.items()):
        n, fs = sizes[(sid, side)]
        total_area += n * fs * fs
        if n <= caps[side] or (wanted and sid not in wanted):
            continue
        sheet = Sheet(load_frames(path))
        found = best_window(sheet, caps[side])
        if found and found[2] <= args.seam:
            start, count, cost = found
            trims.setdefault(sid, {})[side] = [start, count]
            before += n * fs * fs
            after += count * fs * fs
            seams.append((cost, sid, side, start, count))
        else:
            kept_long.append((sid, side, n, found[2] if found else float("inf")))

    saved = before - after
    shiny = 2          # a shiny sheet repeats every normal sheet's frames
    print(f"\ntrimmed {len(seams)} sheets; kept {len(kept_long)} long ones with no clean loop")
    if total_area:
        print(f"animation pixels saved: {100 * saved / total_area:.1f}% of {total_area:,} (x{shiny} with shinies)")
    if seams:
        print("\nroughest accepted seams (1.0 = a normal step):")
        for cost, sid, side, s, k in sorted(seams, reverse=True)[:8]:
            print(f"  {sid:<28} {side:<5} frames {s}..{s + k - 1} of {sizes[(sid, side)][0]}   seam {cost:.2f}")
        exact = [x for x in seams if x[0] < 0.05]
        print(f"\n{len(exact)} windows close on an identical frame (seam ~0)")
    if kept_long:
        print("\nkept whole (no window under the cap loops as smoothly as a normal step):")
        for sid, side, n, cost in sorted(kept_long, key=lambda x: -x[2])[:20]:
            print(f"  {sid:<28} {side:<5} {n} frames   best seam {cost:.2f}")
        if len(kept_long) > 20:
            print(f"  ... and {len(kept_long) - 20} more")

    if args.command == "write":
        args.out.write_text(json.dumps(trims, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {args.out} ({len(trims)} species)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
