"""Text -> polygon outlines (mm) for engraving, centred on the origin.

Needs matplotlib, so run with `py -I` (the user-site numpy breaks it under -P -E).
Usage: text_outline.py font.ttf out.json "TEXT=height_mm" ["TEXT2=height_mm" ...]
"""
import json
import sys

from matplotlib.font_manager import FontProperties
from matplotlib.textpath import TextPath

font, out = sys.argv[1], sys.argv[2]
result = {}
for spec in sys.argv[3:]:
    text, height = spec.rsplit("=", 1)
    path = TextPath((0, 0), text, size=100, prop=FontProperties(fname=font))
    polys = [p.tolist() for p in path.to_polygons(closed_only=True)]
    xs = [x for p in polys for x, _ in p]
    ys = [y for p in polys for _, y in p]
    s = float(height) / (max(ys) - min(ys))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    result[text] = [[[(x - cx) * s, (y - cy) * s] for x, y in p] for p in polys]
    print(f"{text!r}: {len(polys)} contours, {(max(xs) - min(xs)) * s:.1f} x {float(height):.1f} mm")
json.dump(result, open(out, "w"))
