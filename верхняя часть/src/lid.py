"""Cyberdeck upper part: box ("крышка") and back frame ("рамка").

Box: monitor window in the front panel (z=0..2, monitor side), other test windows
closed, outer walls raised to 35 mm, slanted exhaust slots in wall 1, port openings
for the Pi 4B (USB/Ethernet in wall 2, USB-C in wall 3), hidden paw inside.
Back frame (z=31..35 in the box): ribbed grille with a raised X-brace and an open
hub ring, styled after the reference case.

Usage: lid.py <folder with regions.json> box.stl frame.stl assembly.stl
"""
import json
import sys

import numpy as np
import shapely
import trimesh
import manifold3d as mf
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

data_dir, out_box, out_frame, out_asm = sys.argv[1:5]

# ---- parameters
WALL = 2.0          # outer wall thickness (matches the test part)
H = 35.0            # wall height = top of corner brackets
PLATE = 2.0         # front panel thickness
FRAME_Z = 31.0      # back frame sits on the corner posts
FRAME_GAP = 0.2     # clearance around the back frame pocket
SIDE_SLOTS, SIDE_W, SIDE_PITCH = 9, 2.5, 5.5
SIDE_Z0, SIDE_Z1, SIDE_LEAN = 19.0, 29.0, 4.0   # slanted exhaust slots at Pi height
# Pi 4B on the back of the 4.3" DSI LCD (display 106x68 in the window, glass at z=0),
# centred across the display, USB/Ethernet end at wall 2,
# power side towards wall 3. Ports sit ~25 mm behind the walls, so openings are
# sized for plug bodies, not just the sockets.
USB_TOP = 30.0                                  # measured: screen glass to top of the USB stacks
PI_Z = USB_TOP - 15.6 - 1.4                     # Pi board bottom
PI_X0, PI_Y0 = 47.5, 27.0                       # Pi board corner (DSI end, power side)
USB_WIN = (PI_Y0 - 2.0, PI_Y0 + 57.0, PI_Z - 1.0, USB_TOP + 0.5)   # wall 2: y0, y1, z0, z1 (USB2, USB3, Ethernet)
USBC_Z = PI_Z + 1.4 + 1.6                       # USB-C socket centre height
USBC_WIN = (PI_X0 + 11.2 - 8.0, PI_X0 + 11.2 + 8.0, USBC_Z - 5.25, USBC_Z + 5.25)  # wall 3: x0, x1, z0, z1
WIN_R = 2.5
MON_GROW = 1.0                                  # monitor window + pocket grown per side (106x68 -> 108x70)
PAW_AT, PAW_H = (13.5, 55.0), 0.6               # hidden emboss on the inner face of the front panel
SLOT_W, SLOT_PITCH = 2.2, 4.4   # back grille slots
RIB_H = 2.5                     # ribs between slots; brace and border stay full height
ARM_W = 8.0                     # X-brace arm width
HUB_OUT, HUB_IN = 32.0, 22.0    # open hub ring at the X centre


def to_cs(geom):
    polys = [geom] if geom.geom_type == "Polygon" else list(geom.geoms)
    contours = []
    for p in polys:
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    return mf.CrossSection(contours, mf.FillRule.EvenOdd)


def prism(geom, z0, z1):
    return mf.Manifold.extrude(to_cs(geom), z1 - z0).translate((0, 0, z0))


def save(man, path):
    m = man.to_mesh()
    t = trimesh.Trimesh(np.asarray(m.vert_properties)[:, :3], np.asarray(m.tri_verts), process=True)
    t.export(path)
    b = man.bounding_box()
    print(f"{path}: size {np.round(np.subtract(b[3:], b[:3]), 2).tolist()} volume {man.volume() / 1000:.1f} cm3 "
          f"genus {man.genus()} watertight {t.is_watertight}")


# ---- original parts, rebuilt from the per-slab regions in float64 so new
# geometry shares exact coordinates with the old outline
regions = {k: shapely.from_wkt(v) for k, v in json.load(open(f"{data_dir}/regions.json")).items()}
BOX_CLIP, FRAME_CLIP = box(-5, -5, 170, 111.5), box(-5, 111.5, 170, 230)


def part(clip):
    pieces = []
    for k, reg in regions.items():
        z0, z1 = map(float, k.split("-"))
        g = reg.intersection(clip)
        if not g.is_empty:
            pieces.append(prism(g, z0, z1))
    return mf.Manifold.batch_boolean(pieces, mf.OpType.Add)


def largest(g):
    return max(getattr(g, "geoms", [g]), key=lambda p: p.area)


# ================= box =================
front = largest(regions["0-1"].intersection(BOX_CLIP))
P = Polygon(front.exterior)
window = next(Polygon(r) for r in front.interiors if Polygon(r).contains(Point(80, 55)))
xmin, ymin, xmax, ymax = P.bounds

inner = box(xmin + WALL, ymin + WALL, xmax - WALL, ymax - WALL)
lid = part(BOX_CLIP) + prism(P.difference(window), 0, PLATE) + prism(P.difference(inner), 0, H)

# back frame pocket with clearance (frame outline moved onto the posts)
F0 = largest(regions["0-1"].intersection(FRAME_CLIP))
dx, dy = xmin + WALL - F0.bounds[0], ymin + WALL - F0.bounds[1]
pocket = shapely.affinity.translate(Polygon(F0.exterior), dx, dy).buffer(FRAME_GAP, join_style="round")
lid = lid - prism(pocket, FRAME_Z, H + 1)

# monitor pocket: window and inner ring grown by MON_GROW per side, ring stays 2 mm thick,
# corner stops (z 12..13) extended onto the moved ring; screw bosses stay where they were
wx0, wy0, wx1, wy1 = np.round(window.bounds, 1)
mon = box(wx0 - MON_GROW, wy0 - MON_GROW, wx1 + MON_GROW, wy1 + MON_GROW)
ring = mon.buffer(2.0, join_style="mitre").difference(mon)
corners = unary_union([box(x - 10, y - 10, x + 10, y + 10) for x in (wx0, wx1) for y in (wy0, wy1)])
lid = (lid - prism(mon, -1.0, 12.0) + prism(ring, PLATE - 0.01, 12.0)
       + prism(ring.intersection(corners), 12.0 - 0.01, 13.0))
print("monitor window", np.round(mon.bounds, 2).tolist(), "size", wx1 - wx0 + 2 * MON_GROW, "x", wy1 - wy0 + 2 * MON_GROW)

yc = (ymin + ymax) / 2
for k in range(SIDE_SLOTS):
    y = yc + (k - (SIDE_SLOTS - 1) / 2) * SIDE_PITCH - SIDE_LEAN / 2
    for x0, x1 in ((xmin - 1, xmin + WALL + 0.5),):   # wall 1 only: wall 2 has the port window
        pts = [(x, yy, z) for x in (x0, x1)
               for (yy, z) in ((y, SIDE_Z0), (y + SIDE_W, SIDE_Z0),
                               (y + SIDE_LEAN, SIDE_Z1), (y + SIDE_LEAN + SIDE_W, SIDE_Z1))]
        lid = lid - mf.Manifold.hull_points(np.array(pts, float))



def wall_window(a0, a1, z0, z1, rot, t):
    """Rounded window drawn in the (a, z) plane, pushed through a wall by matrix rot."""
    w = box(a0, z0, a1, z1).buffer(-WIN_R).buffer(WIN_R, quad_segs=8)
    m = mf.Manifold.extrude(to_cs(w), WALL + 1.5)
    return m.transform(np.hstack([np.array(rot, float), np.array(t, float)[:, None]]))


y0, y1, z0, z1 = USB_WIN
lid = lid - wall_window(y0, y1, z0, z1, [[0, 0, 1], [1, 0, 0], [0, 1, 0]], [xmax - WALL - 0.5, 0, 0])
x0, x1, z0, z1 = USBC_WIN
lid = lid - wall_window(x0, x1, z0, z1, [[1, 0, 0], [0, 0, -1], [0, 1, 0]], [0, ymin + WALL + 0.5, 0])

# snow leopard paw (easter egg): main pad + four toes, raised on the inside of the front panel
px, py = PAW_AT
pad = unary_union([Point(x, y).buffer(2.6, quad_segs=16) for x, y in ((-3.0, -1.0), (0.0, -1.8), (3.0, -1.0))]
                 + [shapely.affinity.scale(Point(0, 1.0).buffer(1.0, quad_segs=24), 4.2, 3.0)])
toes = [shapely.affinity.rotate(shapely.affinity.scale(Point(dx, dy).buffer(1.0, quad_segs=16), 1.7, 2.3), ang)
        for dx, dy, ang in ((-6.0, 5.6, 25), (-2.1, 8.3, 8), (2.1, 8.3, -8), (6.0, 5.6, -25))]
paw = shapely.affinity.translate(shapely.affinity.rotate(unary_union([pad] + toes), 90, origin=(0, 0)), px, py)
print("paw gaps toe-pad mm:", [round(t.distance(pad), 2) for t in toes], "size", np.round(np.subtract(paw.bounds[2:], paw.bounds[:2]), 1))
lid = lid + prism(paw, PLATE - 0.01, PLATE + PAW_H)

# ================= back frame =================
T = 4.0
outline = Polygon(F0.exterior)
rings = sorted((Polygon(r) for r in F0.interiors), key=lambda p: -p.area)
opening, screw_holes = rings[0], unary_union(rings[1:])
gx0, gy0, gx1, gy1 = opening.bounds
gc = Point((gx0 + gx1) / 2, (gy0 + gy1) / 2)

arms = unary_union([LineString([(gx0, gy0), (gx1, gy1)]).buffer(ARM_W / 2, cap_style="flat"),
                    LineString([(gx0, gy1), (gx1, gy0)]).buffer(ARM_W / 2, cap_style="flat")])
hub_hole = gc.buffer(HUB_IN / 2, quad_segs=32)
brace = arms.difference(hub_hole).union(gc.buffer(HUB_OUT / 2, quad_segs=32).difference(hub_hole))
brace = brace.intersection(opening)

n = int((gx1 - gx0 - 2 * 3.0 - SLOT_W) // SLOT_PITCH) + 1   # keep >=3 mm to the border
x_first = (gx0 + gx1) / 2 - (n - 1) * SLOT_PITCH / 2
slots = unary_union([LineString([(x, gy0), (x, gy1)]) for x in x_first + SLOT_PITCH * np.arange(n)])
cuts = slots.buffer(SLOT_W / 2, cap_style="flat").intersection(opening.buffer(-3.0, join_style="mitre"))
cuts = cuts.difference(brace.buffer(1.0))
cuts = cuts.buffer(-SLOT_W / 2 + 0.01, quad_segs=8).buffer(SLOT_W / 2 - 0.01, quad_segs=8)
cuts = unary_union([c for c in getattr(cuts, "geoms", [cuts]) if c.area > SLOT_W * 6.0])

frame = (prism(outline.difference(opening).union(brace).difference(screw_holes), 0, T)
         + prism(opening.difference(cuts), 0, RIB_H))
print(f"grille: {len(getattr(cuts, 'geoms', [cuts]))} slots, open area {cuts.area:.0f} mm2")

save(lid, out_box)
save(frame, out_frame)
save(lid + frame.translate((dx, dy, FRAME_Z)), out_asm)
