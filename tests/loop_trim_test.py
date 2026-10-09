"""Run from the mod root: python tests/loop_trim_test.py
Checks the loop trimmer (tools/trim_loops.py) on synthetic sheets and the build's two small
helpers (trim windows, back-sprite scale snapping)."""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import build_atlas as ba  # noqa: E402
import trim_loops as tl  # noqa: E402

passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL:", msg)


def frame(seed: int, size: int = 12) -> Image.Image:
    """A frame that differs from every other seed (a bright block at a seed-specific spot)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for x in range(size):
        for y in range(size):
            if (x * 7 + y * 13 + seed * 31) % 5 < 2:
                img.putpixel((x, y), (60, 90, 160, 255))
    bx, by = (seed * 5) % (size - 3), (seed * 3 // 2) % (size - 3)
    for x in range(bx, bx + 3):
        for y in range(by, by + 3):
            img.putpixel((x, y), (255, 40 + seed % 200, 40, 255))
    return img.convert("RGBa")


def sheet(cycle: list[int], repeats: int) -> tl.Sheet:
    return tl.Sheet([frame(s) for s in cycle * repeats])


# a sheet that is one 10-frame loop played 8 times: any window of one period closes exactly
s = sheet(list(range(10)), 8)
found = tl.best_window(s, 30)
check(found is not None and found[2] < 0.05, "a repeating sheet has a window with a seam of ~0")
check(found is not None and found[1] % 10 == 0 and found[1] <= 30,
      f"...whose length is a whole number of loops, at most the cap (got {found})")

# a sheet that never repeats (every frame different): nothing closes on a matching frame
s = tl.Sheet([frame(i) for i in range(40)])
found = tl.best_window(s, 24)
check(found is None or found[2] > 0.05, "a sheet with no repeat has no window that closes on an identical frame")

# a loop that starts partway: the window must be allowed to start after frame 0
cycle = [3, 1, 4, 1, 5, 9, 2, 6]
s = tl.Sheet([frame(100 + i) for i in range(5)] + [frame(c) for c in cycle * 5])
found = tl.best_window(s, 17)
check(found is not None and found[2] < 0.05 and found[0] >= 5,
      f"a window may start after the intro (got {found})")

check(tl.pick_cap([5, 10, 20, 30, 100], "median") == 20, "median cap")
check(tl.pick_cap([10, 20], "mean") == 15, "mean cap")
check(tl.pick_cap([10, 20], "37") == 37, "a number is a cap")

# trim windows apply to a sheet and its shiny alike, and never to a sheet they do not fit
trims = {"A": {"front": [16, 56], "back": [0, 40]}}
check(ba.trim_window(trims, "A", "front", 84) == (16, 56), "front window")
check(ba.trim_window(trims, "A", "front_shiny", 84) == (16, 56), "the shiny front shares it")
check(ba.trim_window(trims, "A", "back_shiny", 84) == (0, 40), "the shiny back shares the back window")
check(ba.trim_window(trims, "A", "front", 60) is None, "a sheet the window does not fit is left whole")
check(ba.trim_window(trims, "B", "front", 84) is None, "no entry: no trim")

# back sprites: the cart's height over ours, snapped to 1 / 1.5 / 2 and never below 1
check(ba.back_scale(40, 80) == 1.0, "a body taller than the reference stays at 1x")
check(ba.back_scale(60, 60) == 1.0, "as tall as the reference: 1x")
check(ba.back_scale(75, 50) == 1.5, "1.5x reference ratio snaps to 1.5x")
check(ba.back_scale(60, 50) == 1.0, "1.2x is closer to 1x than to 1.5x")
check(ba.back_scale(64, 50) == 1.5, "1.28x is closer to 1.5x")
check(ba.back_scale(100, 50) == 2.0, "2x ratio is 2x")
check(ba.back_scale(300, 50) == 2.0, "never above 2x")
check(ba.back_scale(0, 50) == 1.0 and ba.back_scale(50, 0) == 1.0, "nothing to go on: 1x")

print(f"{passed}/{passed + failed} checks passed (loop trimming and back scale)")
sys.exit(0 if failed == 0 else 1)
