"""Lid from the user's 5.skp + Pi 4B port windows + vents for through-flow.

Box geometry comes from regions.json (rebuild.py of 5.skp, with the user's half-cut
slot outlines on wall 2 filled first). Added:
- monitor mount from proba.py (v4: pocket 106.5x68.5, 4 bosses with 2.6 mm holes up to
  z 23) in place of the 5.skp one (106x68 ring, 5 mm bosses up to z 18);
- port windows from lid.py v6: USB/Ethernet in wall 2, USB-C in wall 3;
- 0.2 mm clearance around the back frame pocket (5.skp has it at exactly 156x106);
- slanted slots in a band at the Pi's component side. With the lid open and upright
  the long walls are bottom (3, intake) and top (4, exhaust), so air rises across the
  Pi; wall 1 adds cross-flow, wall 2 is already open through the port window.

Usage: vents.py regions.json out.stl
"""
import json
import os
import sys

import numpy as np
import shapely
import trimesh
import manifold3d as mf
from shapely.geometry import Polygon, box

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # -P leaves the script dir off sys.path
import proba

regions_path, out = sys.argv[1:3]

# ---- parameters
WALL = 2.0
POST = 9.0                                  # corner posts reach 9 mm in from the outer faces
FRAME_Z, FRAME_GAP = 31.0, 0.2              # back frame drops in at z 31..35
SLOT_W, SLOT_PITCH, SLOT_LEAN = 3.0, 6.0, 4.0   # slot width along the wall, step, top shifted by LEAN
SLOT_Z = (10.0, 29.0)                       # band from below the Pi board to under the frame
SLOT_KEEP = 3.0                             # solid wall kept next to posts and windows
SLOT_WALLS = (1, 3, 4)                      # 1 = x=0, 2 = x=160, 3 = y=0, 4 = y=110
# Pi 4B on the display back, same placement as lid.py (v6)
USB_TOP = 30.0
PI_Z = USB_TOP - 15.6 - 1.4
PI_X0, PI_Y0 = 47.5, 27.0
USB_WIN = (PI_Y0 - 2.0, PI_Y0 + 57.0, PI_Z - 1.0, USB_TOP + 0.5)   # wall 2: y0, y1, z0, z1
USBC_Z = PI_Z + 1.4 + 1.6
USBC_WIN = (PI_X0 + 11.2 - 8.0, PI_X0 + 11.2 + 8.0, USBC_Z - 5.25, USBC_Z + 5.25)  # wall 3: x0, x1, z0, z1
WIN_R = 2.5
OLD_MOUNT = (24.9, 18.9, 135.1, 91.1)       # 5.skp pocket ring 25..135 x 19..91 with its stops and bosses


def prism(geom, z0, z1):
    polys = [g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "Polygon" and g.area > 0]
    contours = []
    for p in polys:
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    return mf.Manifold.extrude(mf.CrossSection(contours, mf.FillRule.EvenOdd), z1 - z0).translate((0, 0, z0))


regions = {k: shapely.from_wkt(v) for k, v in json.load(open(regions_path)).items()}
lid = mf.Manifold.batch_boolean([prism(reg, *map(float, k.split("-"))) for k, reg in regions.items()],
                                mf.OpType.Add)
xmin, ymin, _, xmax, ymax, H = lid.bounding_box()

mount, mon_pocket, groove = proba.build()                 # same coordinates as the lid
lid = lid - prism(box(*OLD_MOUNT), 2.0, proba.BOSS_TOP - 3.0) - prism(mon_pocket, -1.0, 2.5)
lid = lid + mount - groove                                 # the front panel would refill the groove


def wall_cut(shape, wall):
    """Shape drawn in (a, z) — a = y on walls 1/2, x on walls 3/4 — pushed through the wall."""
    rot, t = {1: ([[0, 0, 1], [1, 0, 0], [0, 1, 0]], [xmin - 1, 0, 0]),
              2: ([[0, 0, 1], [1, 0, 0], [0, 1, 0]], [xmax - WALL - 1, 0, 0]),
              3: ([[1, 0, 0], [0, 0, -1], [0, 1, 0]], [0, ymin + WALL + 1, 0]),
              4: ([[1, 0, 0], [0, 0, -1], [0, 1, 0]], [0, ymax + 1, 0])}[wall]
    return prism(shape, 0, WALL + 2.0).transform(np.hstack([np.array(rot, float), np.array(t, float)[:, None]]))


def window(a0, a1, z0, z1):
    return box(a0, z0, a1, z1).buffer(-WIN_R).buffer(WIN_R, quad_segs=8)


def free(a0, a1, blocked):
    spans = [(a0, a1)]
    for b0, b1 in blocked:
        spans = [s for lo, hi in spans for s in ((lo, min(hi, b0)), (max(lo, b1), hi)) if s[1] > s[0]]
    return spans


cuts = [wall_cut(window(*USB_WIN), 2), wall_cut(window(*USBC_WIN), 3)]
blocked = {2: [(USB_WIN[0] - SLOT_KEEP, USB_WIN[1] + SLOT_KEEP)],
           3: [(USBC_WIN[0] - SLOT_KEEP, USBC_WIN[1] + SLOT_KEEP)]}
z0, z1 = SLOT_Z
span = SLOT_W + SLOT_LEAN
counts = {}
for wall in SLOT_WALLS:
    lo, hi = (ymin, ymax) if wall in (1, 2) else (xmin, xmax)
    counts[wall] = 0
    for a0, a1 in free(lo + POST + SLOT_KEEP, hi - POST - SLOT_KEEP, blocked.get(wall, [])):
        n = int((a1 - a0 - span) // SLOT_PITCH) + 1
        if n < 2:
            continue
        start = a0 + (a1 - a0 - span - (n - 1) * SLOT_PITCH) / 2
        for k in range(n):
            a = start + k * SLOT_PITCH
            cuts.append(wall_cut(Polygon([(a, z0), (a + SLOT_W, z0), (a + span, z1), (a + SLOT_LEAN, z1)]), wall))
        counts[wall] += n

top = max(getattr(regions[f"{FRAME_Z:g}-{H:g}"], "geoms", [regions[f"{FRAME_Z:g}-{H:g}"]]), key=lambda p: p.area)
frame_pocket = Polygon(max(top.interiors, key=lambda r: Polygon(r).area)).buffer(FRAME_GAP, join_style="round")
cuts.append(prism(frame_pocket, FRAME_Z, H + 1))
lid = mf.Manifold.batch_boolean([lid] + cuts, mf.OpType.Subtract)

m = lid.to_mesh()
t = trimesh.Trimesh(np.asarray(m.vert_properties)[:, :3], np.asarray(m.tri_verts), process=True)
t.export(out)
b = lid.bounding_box()
slot_area = sum(counts.values()) * SLOT_W * (z1 - z0)
win_area = sum(window(*w).area for w in (USB_WIN, USBC_WIN))
print(f"{out}: size {np.round(np.subtract(b[3:], b[:3]), 2).tolist()} volume {lid.volume() / 1000:.1f} cm3 "
      f"genus {lid.genus()} watertight {t.is_watertight}")
print(f"slots per wall {counts}, slot area {slot_area / 100:.1f} cm2 + port windows {win_area / 100:.1f} cm2; "
      f"frame pocket {np.round(frame_pocket.bounds, 2).tolist()}")
