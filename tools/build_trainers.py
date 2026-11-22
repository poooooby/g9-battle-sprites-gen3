"""Builds the animated trainer art for FireRed to Emerald from the Animated Trainer Intros pack
(a Pokemon Essentials v21.1 / Deluxe Battle Kit add-on by Lucidious89) and Pokemon Essentials'
own VS graphics.

Reads, without extracting:
  --zip         the pack's zip ("Animated Trainer Intros.zip": Graphics/Trainers/*.png strips,
                Graphics/Transitions/*, PBS/*trainer_types*.txt)
  --essentials  a Pokemon Essentials v21.1 folder (Graphics/Transitions: hgss_vs1/2 and the
                Kanto VS portraits and bars the pack does not ship)

Writes, for the art data/trainer_map.lua names (nothing else is packed):
  assets/trainers/fronts_<n>.png  every front strip's frames, each with the pack's shadow baked
                                  under it (a black silhouette of the frame, 1.1 x 0.25 of its size,
                                  opacity 100/255, moved by the trainer type's ShadowXY; none with
                                  HideShadow), packed in rows
  assets/trainers/vs/<name>.png   the VS portraits, bars and logos, copied as they are
  data/trainer_index.lua          per sprite: its page, cell size, frame count and layout, and the
                                  pivot (the frame's bottom centre, which the game stands on its spot)

A strip is read as Essentials' plugin reads it: square frames, as tall as the image, ceil(width /
height) of them; an image no wider than twice its height is a single still frame.

Usage (from this repo, luajit on PATH):
    python tools/build_trainers.py --zip "<Animated Trainer Intros.zip>" --essentials "<Essentials>"
"""

from __future__ import annotations

import argparse
import io
import math
import re
import subprocess
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "trainers"
VS_DIR = OUT_DIR / "vs"
INDEX = ROOT / "data" / "trainer_index.lua"
PAGE = 2048
SHADOW_ZOOM = (1.1, 0.25)
SHADOW_ALPHA = 100 / 255
DEFAULT_SCALE = 2          # Settings::TRAINER_SPRITE_SCALE: ShadowXY is in its screen px


def map_names() -> tuple[set[str], set[str]]:
    """The front sprites and VS files data/trainer_map.lua names (through luajit)."""
    code = r"""
      local m = dofile("data/trainer_map.lua")
      local seen = {}
      for _, game in pairs(m.fronts) do for _, n in pairs(game) do seen["F " .. n] = true end end
      for _, game in pairs(m.vs) do for _, e in pairs(game) do
        seen["V " .. e.foe] = true; seen["V " .. e.bar] = true end end
      for _, n in ipairs(m.vsParts or {}) do seen["V " .. n] = true end
      local out = {}
      for k in pairs(seen) do out[#out + 1] = k end
      table.sort(out)
      io.write(table.concat(out, "\n"))
    """
    res = subprocess.run(["luajit", "-e", code], cwd=ROOT, capture_output=True, text=True, check=True)
    fronts, vs = set(), set()
    for line in res.stdout.splitlines():
        kind, name = line.split(" ", 1)
        (fronts if kind == "F" else vs).add(name)
    return fronts, vs


def read_pbs(text: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    cur = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            cur = sections.setdefault(m.group(1), {})
            continue
        if cur is not None and "=" in line:
            k, v = line.split("=", 1)
            cur[k.strip()] = v.strip()
    return sections


def shadow_settings(z: zipfile.ZipFile) -> dict[str, dict[str, str]]:
    """Per trainer type: the pack's own types, then its patches to Essentials' (DBK applies those
    over the base PBS)."""
    merged: dict[str, dict[str, str]] = {}
    for name in ("PBS/trainer_types_animated.txt", "PBS/Plugins/[DBK] Animated Trainers/trainer_types.txt"):
        if name in z.namelist():
            for sec, kv in read_pbs(z.read(name).decode("utf-8-sig", "replace")).items():
                merged.setdefault(sec, {}).update(kv)
    return merged


def frames_of(img: Image.Image) -> list[Image.Image]:
    w, h = img.size
    if w <= 2 * h:
        return [img]
    n = math.ceil(w / h)
    return [img.crop((i * h, 0, min(w, i * h + h), h)) for i in range(n)]


def bake(frame: Image.Image, fw: int, fh: int, sx: float, sy: float, hide: bool):
    """The frame on a cell with its shadow under it; returns the cell and the pivot (the frame's
    bottom centre) in it. sx, sy: the shadow's offset in pack px."""
    if hide:
        return frame, (fw / 2, fh)
    sw, sh = max(1, round(fw * SHADOW_ZOOM[0])), max(1, round(fh * SHADOW_ZOOM[1]))
    # shadow box: bottom-centred on the frame's bottom centre, moved by (sx, sy)
    sx0 = fw / 2 + sx - sw / 2
    sy0 = fh + sy - sh
    x0, y0 = math.floor(min(0, sx0)), math.floor(min(0, sy0))
    x1, y1 = math.ceil(max(fw, sx0 + sw)), math.ceil(max(fh, sy0 + sh))
    cell = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    alpha = frame.getchannel("A").resize((sw, sh), Image.BOX)
    alpha = alpha.point(lambda a: round(a * SHADOW_ALPHA))
    shadow = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    shadow.putalpha(alpha)
    cell.alpha_composite(shadow, (round(sx0 - x0), round(sy0 - y0)))
    cell.alpha_composite(frame, (-x0, -y0))
    return cell, (fw / 2 - x0, fh - y0)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", type=Path, required=True)
    ap.add_argument("--essentials", type=Path, required=True)
    args = ap.parse_args()
    fronts, vs = map_names()
    z = zipfile.ZipFile(args.zip)
    names = set(z.namelist())
    shadows = shadow_settings(z)
    ess = args.essentials / "Graphics" / "Transitions"

    missing = [n for n in sorted(fronts) if f"Graphics/Trainers/{n}.png" not in names]
    if missing:
        print("missing front sprites:", ", ".join(missing), file=sys.stderr)
        return 1

    # ---- fronts: bake, then pack in rows (each sprite's frames on as few rows as fit a page)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("fronts_*.png"):
        old.unlink()
    pages: list[Image.Image] = []
    index: dict[str, dict] = {}
    px = py = row_h = 0
    for name in sorted(fronts):
        img = Image.open(io.BytesIO(z.read(f"Graphics/Trainers/{name}.png"))).convert("RGBA")
        frames = frames_of(img)
        fw, fh = frames[0].size
        st = shadows.get(name, {})
        scale = float(st.get("SpriteScale", DEFAULT_SCALE) or DEFAULT_SCALE)
        sxy = [float(v) for v in st.get("ShadowXY", "0,0").split(",")] if st.get("ShadowXY") else [0.0, 0.0]
        hide = st.get("HideShadow", "").lower() == "true"
        cells = []
        pivot = None
        for f in frames:
            if f.size != (fw, fh):   # a last frame cut short: padded to the frame size
                pad = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
                pad.paste(f, (0, 0))
                f = pad
            c, pv = bake(f, fw, fh, sxy[0] / scale, sxy[1] / scale, hide)
            cells.append(c)
            pivot = pivot or pv
        cw, ch = cells[0].size
        cols = max(1, min(len(cells), PAGE // cw))
        rows = math.ceil(len(cells) / cols)
        w, h = cols * cw, rows * ch
        if not pages or px + w > PAGE:
            px, py, row_h = 0, py + row_h, 0
        if not pages or py + h > PAGE:
            pages.append(Image.new("RGBA", (PAGE, PAGE), (0, 0, 0, 0)))
            px, py, row_h = 0, 0, 0
        page = pages[-1]
        for i, c in enumerate(cells):
            page.paste(c, (px + (i % cols) * cw, py + (i // cols) * ch))
        index[name] = {
            "page": len(pages) - 1, "x": px, "y": py, "cw": cw, "ch": ch, "frames": len(cells),
            "cols": cols, "px": pivot[0], "py": pivot[1], "fw": fw, "fh": fh,
        }
        px += w
        row_h = max(row_h, h)

    for i, page in enumerate(pages):
        bbox = page.getbbox() or (0, 0, 1, 1)
        page = page.crop((0, 0, PAGE, bbox[3]))
        page.save(OUT_DIR / f"fronts_{i}.png", optimize=True)

    # ---- VS art: copied as it is, the pack's first, else Essentials'
    VS_DIR.mkdir(parents=True, exist_ok=True)
    for old in VS_DIR.glob("*.png"):
        old.unlink()
    vs_missing = []
    for name in sorted(vs):
        zname = f"Graphics/Transitions/{name}.png"
        if zname in names:
            data = z.read(zname)
        elif (ess / f"{name}.png").exists():
            data = (ess / f"{name}.png").read_bytes()
        else:
            vs_missing.append(name)
            continue
        (VS_DIR / f"{name}.png").write_bytes(data)
    if vs_missing:
        print("missing VS art:", ", ".join(vs_missing), file=sys.stderr)
        return 1

    # ---- the index
    lines = ["-- built by tools/build_trainers.py: do not edit (see data/trainer_map.lua)",
             "-- per sprite: page (assets/trainers/fronts_<page>.png), x / y (its first cell), cw / ch",
             "-- (cell size), frames, cols (cells per row), px / py (pivot: the frame's bottom centre in",
             "-- its cell), fw / fh (the pack's frame size)", "return {"]
    for name in sorted(index):
        e = index[name]
        lines.append(
            f'  ["{name}"] = {{ page = {e["page"]}, x = {e["x"]}, y = {e["y"]}, cw = {e["cw"]}, '
            f'ch = {e["ch"]}, frames = {e["frames"]}, cols = {e["cols"]}, px = {e["px"]:g}, '
            f'py = {e["py"]:g}, fw = {e["fw"]}, fh = {e["fh"]} }},')
    lines.append("}")
    INDEX.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    # ---- coverage per game
    gen1recomp = ROOT.parent / "gen1recomp" / "src" / "core" / "game3" / "constants"
    code = r"""
      local m = dofile("data/trainer_map.lua")
      for _, g in ipairs({ "firered", "emerald", "ruby" }) do
        local n = 0
        for _ in pairs(m.fronts[g]) do n = n + 1 end
        local v = 0
        for _ in pairs(m.vs[g]) do v = v + 1 end
        io.write(g, " ", n, " ", v, "\n")
      end
    """
    res = subprocess.run(["luajit", "-e", code], cwd=ROOT, capture_output=True, text=True, check=True)
    for line in res.stdout.splitlines():
        game, n, v = line.split()
        total = "?"
        f = gen1recomp / game / "trainer_classes.lua"
        if f.exists():
            body = f.read_text(encoding="utf-8")
            m = re.search(r"TRAINER_PIC_ = \{(.*?)\n    \}", body, re.S)
            total = len(re.findall(r'"TRAINER_PIC_', m.group(1))) if m else "?"
        print(f"{game}: {n} mapped names for {total} trainer pics, {v} VS screens")
    print(f"{len(index)} sprites, {sum(e['frames'] for e in index.values())} frames on {len(pages)} page(s); "
          f"{len(vs)} VS files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
