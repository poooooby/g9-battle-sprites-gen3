"""Packs the battle pages (assets/atlas/battle_*.png, from tools/build_atlas.py) as COLOUR NUMBERS:
what the release ships and src/atlas.lua draws from. Run it after every build_atlas.py run.

A battle sprite uses few colours (at most ~130 normal/shiny pairs, usually ~15), and its shiny is
the same animation in other colours. So each species' front (and back) animation, normal and shiny
together, is stored ONCE as a greyscale image of colour numbers, each number standing for one
(normal colour, shiny colour) pair -- exact, also where a shiny splits one colour in two. The real
colours are one row per variant of assets/numbers/palette.png (RGBA, column = number). A block is
the animation's frames stacked top to bottom (fs wide, fs * frames tall), in single-column shards
(PNG compresses row by row). The game rebuilds a species' block when it is first drawn, instead of
loading whole 4032x4032 pages: ~43 MB shipped instead of ~100 MB, ~10 ms and a few MB of VRAM per
species instead of ~200 ms and ~55 MB per page.

    python tools/build_numbers.py           # writes assets/numbers/ + data/numbers_index.lua
    python tools/build_numbers.py --check   # exit 1 when they are stale (tools/build_dist.py runs it)

Every block is decoded back and compared with its page cell by cell before anything is written.
The index records each page's SHA-256, so --check catches a page rebuilt since. Output is
deterministic: the same pages give identical bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PAGES = ROOT / "assets" / "atlas"
OUT = ROOT / "assets" / "numbers"
INDEX = ROOT / "data" / "numbers_index.lua"
ATLAS_INDEX = ROOT / "data" / "atlas_index.lua"
VARIANTS = ("front", "front_shiny", "back", "back_shiny")
CELL = re.compile(r"\b(front_shiny|back_shiny|front|back) = \{ sheet = (\d+), start = (\d+), fs = (\d+), "
                  r"cols = (\d+), frames = (\d+), ox = (\d+), oy = (\d+)")
MAX_COLOURS = 256
MAX_SHARD_PX = 1_500_000
MAX_SHARD_H = 16000

_pages: dict[tuple[str, int], np.ndarray] = {}


def page(variant: str, sheet: int) -> np.ndarray:
    key = (variant, sheet)
    if key not in _pages:
        with Image.open(PAGES / f"battle_{variant}_{sheet}.png") as im:
            _pages[key] = np.asarray(im.convert("RGBA")).copy().view("<u4")[:, :, 0]
    return _pages[key]


def strip(variant: str, cell: tuple) -> np.ndarray:
    """The cell's frames, stacked top to bottom (fs wide)."""
    sheet, start, fs, cols, frames, ox, oy = cell
    P = page(variant, sheet)
    out = []
    for n in range(frames):
        i = start + n
        x, y = ox + (i % cols) * fs, oy + (i // cols) * fs
        out.append(P[y:y + fs, x:x + fs])
    return np.concatenate(out, axis=0)


def cell_key(variant: str, cell: tuple) -> str:
    sheet, start, _, _, _, ox, oy = cell
    return f"{variant}:{sheet}:{start}:{ox}:{oy}"


def number_block(job):
    """job = [(variant, cell), ...] (1 or 2 members of one size) -> (numbers, [palette row per
    member]) or None when it needs more than 256 numbers. Checks the round trip."""
    strips = [strip(v, c) for v, c in job]
    key = strips[0].astype(np.uint64)
    if len(strips) > 1:
        key |= strips[1].astype(np.uint64) << np.uint64(32)
    pairs, inverse, counts = np.unique(key.ravel(), return_inverse=True, return_counts=True)
    if len(pairs) > MAX_COLOURS:
        return None
    order = np.lexsort((pairs, -counts))  # most common first, ties by colour (deterministic)
    number = np.empty(len(pairs), dtype=np.uint8)
    number[order] = np.arange(len(pairs), dtype=np.uint8)
    data = number[inverse].reshape(key.shape)
    ranked = pairs[order]
    rows = [((ranked >> np.uint64(32 * m)) & np.uint64(0xFFFFFFFF)).astype("<u4") for m in range(len(job))]
    for m, s in enumerate(strips):
        if not np.array_equal(rows[m][data], s):
            raise SystemExit(f"round trip failed for {cell_key(*job[m])}")
    return data, [r.tobytes() for r in rows]


def collect_jobs(index_text: str):
    """Distinct cells per species, normal paired with its shiny when they have the same frames.
    A form / female sheet reusing a base's cells adds nothing."""
    jobs, seen = [], set()
    for line in index_text.splitlines():
        cells = {m[0]: tuple(map(int, m[1:])) for m in CELL.findall(line)}
        for side in ("front", "back"):
            normal, shiny = cells.get(side), cells.get(side + "_shiny")
            members = []
            if normal and shiny and (normal[2], normal[4]) == (shiny[2], shiny[4]):
                members.append([(side, normal), (side + "_shiny", shiny)])
            else:
                if normal:
                    members.append([(side, normal)])
                if shiny:
                    members.append([(side + "_shiny", shiny)])
            for job in members:
                k = tuple(cell_key(v, c) for v, c in job)
                if k in seen or any(cell_key(v, c) in seen for v, c in job):
                    continue
                seen.update(k)
                seen.add(k)
                jobs.append(job)
    return jobs


def page_hashes() -> dict[str, str]:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(PAGES.glob("battle_*.png"))}


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build() -> int:
    jobs = collect_jobs(ATLAS_INDEX.read_text(encoding="utf-8"))
    with ProcessPoolExecutor() as pool:
        results = list(pool.map(number_block, jobs, chunksize=4))
    too_many = [cell_key(*j[0]) for j, r in zip(jobs, results) if r is None]
    if too_many:
        # never seen with the current pack; would need a full-colour fallback before shipping
        print(f"{len(too_many)} blocks need more than {MAX_COLOURS} colours (first: {too_many[0]})", file=sys.stderr)
        return 1

    shards, cur, h, w = [], [], 0, 0
    for job, res in zip(jobs, results):
        bh, bw = res[0].shape
        if cur and (h + bh > MAX_SHARD_H or max(w, bw) * (h + bh) > MAX_SHARD_PX):
            shards.append(cur)
            cur, h, w = [], 0, 0
        cur.append((job, res))
        h, w = h + bh, max(w, bw)
    if cur:
        shards.append(cur)

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    rows: list[bytes] = []
    blocks: dict[str, list[int]] = {}
    shard_meta = []
    for n, group in enumerate(shards):
        W = max(r[0].shape[1] for _, r in group)
        H = sum(r[0].shape[0] for _, r in group)
        im = np.zeros((H, W), np.uint8)
        y = 0
        for job, (data, member_rows) in group:
            im[y:y + data.shape[0], :data.shape[1]] = data
            for (variant, cell), row in zip(job, member_rows):
                blocks[cell_key(variant, cell)] = [n, y, data.shape[1], data.shape[0], len(rows)]
                rows.append(row)
            y += data.shape[0]
        Image.fromarray(im, "L").save(OUT / f"num_{n}.png", "PNG", optimize=True)
        shard_meta.append((f"num_{n}", W, H))
    pal_w = max(len(r) for r in rows) // 4
    pal = Image.new("RGBA", (pal_w, len(rows)), (0, 0, 0, 0))
    for i, r in enumerate(rows):
        pal.paste(Image.frombytes("RGBA", (len(r) // 4, 1), r), (0, i))
    pal.save(OUT / "palette.png", "PNG", optimize=True)

    lines = [
        "-- Generated by tools/build_numbers.py. Do not edit by hand; rerun the tool instead.",
        "-- The battle pages as colour numbers (assets/numbers/). blocks[\"<variant>:<sheet>:<start>:<ox>:<oy>\"]",
        "-- (a cell of data/atlas_index.lua) = { shard, y, w, h, palette row }: the cell's frames stacked",
        "-- top to bottom at x 0, y of num_<shard>.png (greyscale: the number is the red channel), its",
        "-- colours row `palette row` of palette.png (column = number). pages: SHA-256 of the pages it",
        "-- was built from (tools/build_numbers.py --check).",
        "return {",
        f"  palette = {{ file = \"palette\", w = {pal_w}, h = {len(rows)} }},",
        "  shards = {",
    ]
    lines += [f"    {{ file = \"{f}\", w = {w}, h = {h} }}," for f, w, h in shard_meta]
    lines += ["  },", "  blocks = {"]
    lines += [f"    [{lua_str(k)}] = {{ {', '.join(map(str, v))} }}," for k, v in sorted(blocks.items())]
    lines += ["  },", "  pages = {"]
    lines += [f"    [{lua_str(k)}] = \"{v}\"," for k, v in page_hashes().items()]
    lines += ["  },", "}", ""]
    INDEX.write_text("\n".join(lines), encoding="utf-8", newline="\n")

    size = sum(p.stat().st_size for p in OUT.glob("*.png"))
    old = sum(p.stat().st_size for p in PAGES.glob("battle_*.png"))
    print(f"{len(blocks)} cells in {len(jobs)} blocks, {len(shards)} shards + palette: "
          f"{size / 1e6:.1f} MB (the pages: {old / 1e6:.1f} MB); every frame checked against its page")
    return 0


def check() -> int:
    if not INDEX.exists():
        print("data/numbers_index.lua is missing: run python tools/build_numbers.py", file=sys.stderr)
        return 1
    recorded = dict(re.findall(r'\["(battle_[^"]+)"\] = "([0-9a-f]{64})"', INDEX.read_text(encoding="utf-8")))
    if recorded != page_hashes():
        print("assets/numbers/ is older than the battle pages: run python tools/build_numbers.py", file=sys.stderr)
        return 1
    shards = re.findall(r'file = "(num_\d+|palette)"', INDEX.read_text(encoding="utf-8"))
    missing = [s for s in shards if not (OUT / f"{s}.png").exists()]
    if missing:
        print(f"assets/numbers/ is missing {missing[0]}.png: run python tools/build_numbers.py", file=sys.stderr)
        return 1
    print("assets/numbers/ matches the battle pages")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only check the output is current")
    args = ap.parse_args()
    return check() if args.check else build()


if __name__ == "__main__":
    sys.exit(main())
