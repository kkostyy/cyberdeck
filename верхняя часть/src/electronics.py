"""Models of the electronics inside the upper part, in lid coordinates (mm, glass front at z = 0),
for checking fits and for the SketchUp assembly. Not printed.

Raspberry Pi 4B: from the official mechanical drawing (Raspberry Pi RP-008343-DS-1): board 85 x 56,
corner radius 3, holes Ø2.7 on 58 x 49 at 3.5 from the edges, connector positions and heights
(Z = height above the board top): USB 16.0, Ethernet 13.5, GPIO 8.5, DSI/CSI 5.5, audio 6.0,
USB-C 3.2, micro HDMI 3.0, SoC 2.4. Small chip heights and the microSD socket underneath are not
on the drawing (typical values). Board thickness 1.4.
Placement: corner (DSI end, power side) at PI_X0, PI_Y0 (lid.py), components facing the frame;
board top from the measured glass -> USB top 30.0 minus the official USB height 16.0.

Cooler GeeekPi Armor Lite ZP-0110: outline from the maker's dimension picture (64 wide, ear at
the top-left hole 13 above the left fins, left part 43 incl. ear, right part 49 incl. the tab,
notch 44 from the right edge, 24 mm wire recess on the right), holes on the Pi's diagonal
holes (3.5, 52.5) and (61.5, 3.5), contact pads over SoC, RAM, VL805 and the Ethernet PHY
(maker's underside photo). Heights are NOT published: HS_H = 16 is an estimate (3510 fan
= 10 mm thick, on a 2 mm base resting on the SoC pad). Measure and update HS_H.

Display Waveshare 4.3" DSI 800x480: outline 106 x 68 (fits proba's 106.5 x 68.5 pocket),
active area of a 4.3" 800x480 panel 95.04 x 53.86 centred. Layer thicknesses, the standoffs
and the corner holes under proba's bosses are assumptions until measured.

Usage: electronics.py out_dir
  -> "<out_dir>/<Device> - <part>.stl" (parts, for skp_write: "Device - part" = part group in
     device group) + "<out_dir>/<Device>.stl" (whole device) + colours.json
"""
import json
import os
import sys

import numpy as np
import shapely
import shapely.affinity
import trimesh
import manifold3d as mf
from shapely.geometry import Point, Polygon, box

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
SEG = 48

# ---- placement (lid coordinates)
PI_X0, PI_Y0 = 47.5, 27.0            # Pi corner at the DSI end / power side (lid.py)
USB_TOP, USB_Z, PCB_T = 30.0, 16.0, 1.4
PCB_TOP = USB_TOP - USB_Z            # 14.0
HOLES = [(3.5, 3.5), (61.5, 3.5), (3.5, 52.5), (61.5, 52.5)]
# display (assumed layers; outline and pocket from proba.py)
DISP_C, DISP_WH, ACTIVE_WH = (80.0, 55.0), (106.0, 68.0), (95.04, 53.86)
GLASS_T, MODULE_T, DPCB_T = 1.5, 2.5, 1.6
CORNER_HOLES = (2.75, 3.75)          # from the display edge: under proba's boss holes (3.0 / 4.0 from the pocket wall)
STANDOFF_AF = 5.0                    # M2.5 hex standoffs
BOSS_Z0 = 13.0                       # proba boss underside: corner standoffs reach it
# cooler (Pi coordinates u, v; w above the board top)
HS_H = 16.0                          # total height above the board (estimate, measure!)
HS_BASE = (3.4, 5.4)                 # base plate underside (SoC 2.4 + 1.0 pad) and top
FAN_C, FAN_D, FAN_T = (38.5, 31.0), 35.0, 10.0   # fan centre as style.py's FAN_AT (from the maker's top-view picture, ±1)
FIN_T, FIN_PITCH = 1.2, 3.6


def prism(geom, z0, z1):
    contours = []
    for p in (g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "Polygon" and g.area > 0):
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    return mf.Manifold.extrude(mf.CrossSection(contours, mf.FillRule.EvenOdd), z1 - z0).translate((0, 0, z0))


def rbox(x0, y0, x1, y1, r):
    return box(x0, y0, x1, y1).buffer(-r).buffer(r, quad_segs=SEG // 4) if r else box(x0, y0, x1, y1)


def disc(c, d, seg=SEG):
    return Point(c).buffer(d / 2, quad_segs=seg // 4)


def hexagon(c, af):
    r = af / np.sqrt(3)
    return Polygon([(c[0] + r * np.cos(a), c[1] + r * np.sin(a)) for a in np.radians(np.arange(0, 360, 60) + 30)])


def union(parts):
    return mf.Manifold.batch_boolean(parts, mf.OpType.Add)


def to_lid(geom):                     # Pi (u, v) -> lid (x, y)
    return shapely.affinity.translate(geom, PI_X0, PI_Y0)


def pi_prism(geom, w0, w1):           # Pi footprint + heights above the board top -> lid solid
    return prism(to_lid(geom), PCB_TOP + w0, PCB_TOP + w1)


parts = {}                            # "Device - part" -> (manifold, colour)


def add(name, man, colour):
    parts[name] = (man, colour)


# ================= Raspberry Pi 4B =================
board = rbox(0, 0, 85, 56, 3.0) - shapely.union_all([disc(h, 2.7) for h in HOLES])
add("Raspberry Pi 4B - плата", pi_prism(board, -PCB_T, 0), "1e6b30")

metal = []
for vc in (9.0, 27.0):                                                     # USB 2.0 (v 9) and 3.0 (v 27) stacks
    metal += [pi_prism(box(70.5, vc - 6.65, 87.65, vc + 6.65), 0, USB_Z),
              pi_prism(box(87.65, vc - 7.3, 88.1, vc + 7.3), 0.3, USB_Z + 0.3)]   # front flange
metal.append(pi_prism(box(66.6, 38.0, 88.1, 53.5), 0, 13.5))               # Ethernet
usbc = (box(11.2 - 2.85, 0, 11.2 + 2.85, 3.2) | disc((11.2 - 2.85, 1.6), 3.2)    # USB-C: stadium 8.9 x 3.2
        | disc((11.2 + 2.85, 1.6), 3.2))                                      # in (u, w), run along v
metal.append(prism(usbc, -6.2, 1.25).transform(np.array([[1, 0, 0, PI_X0], [0, 0, -1, PI_Y0], [0, 1, 0, PCB_TOP]], float)))
for uc in (26.0, 39.5):                                                    # micro HDMI 0 / 1
    metal += [pi_prism(box(uc - 3.2, -0.6, uc + 3.2, 6.5), 0, 3.0), pi_prism(box(uc - 3.7, -1.2, uc + 3.7, -0.6), 0, 3.0)]
add("Raspberry Pi 4B - разъёмы", union(metal), "c4c4c4")

black = [pi_prism(box(50.6, 0.0, 57.6, 12.4), 0, 6.0)]                     # audio jack body + barrel
barrel = mf.Manifold.cylinder(2.5, 3.0, 3.0, SEG).rotate((90, 0, 0)).translate((PI_X0 + 54.1, PI_Y0, PCB_TOP + 3.0))
assert abs(barrel.bounding_box()[1] - (PI_Y0 - 2.5)) < 0.01, barrel.bounding_box()      # barrel points out of the edge
black.append(barrel)
dsi = Polygon([(2.6, 17.1), (5.4, 17.1), (5.4, 40.2), (2.6, 40.2), (2.6, 37.0), (1.4, 35.8), (1.4, 21.4), (2.6, 20.2)])
csi = Polygon([(45.1, 0.3), (47.8, 0.3), (47.8, 3.6), (49.0, 4.8), (49.0, 18.4), (47.8, 19.6), (47.8, 22.4), (45.1, 22.4)])
black += [pi_prism(dsi, 0, 5.5), pi_prism(csi, 0, 5.5)]
black.append(pi_prism(box(7.1, 49.96, 57.9, 55.04), 0, 2.5))               # GPIO 2x20 base
black.append(pi_prism(box(58.9, 43.9, 64.0, 49.0), 0, 2.5))                # PoE 2x2 base
add("Raspberry Pi 4B - колодки", union(black), "151515")

pins = [pi_prism(box(32.5 + (i - 9.5) * 2.54 - 0.32, 52.5 + s * 1.27 - 0.32, 32.5 + (i - 9.5) * 2.54 + 0.32,
                     52.5 + s * 1.27 + 0.32), 0, 8.5) for i in range(20) for s in (-1, 1)]
pins += [pi_prism(box(61.45 + a * 1.27 - 0.32, 46.45 + b * 1.27 - 0.32, 61.45 + a * 1.27 + 0.32, 46.45 + b * 1.27 + 0.32),
                  0, 8.5) for a in (-1, 1) for b in (-1, 1)]
add("Raspberry Pi 4B - контакты", union(pins), "c9a227")

chips = [pi_prism(box(21.75, 25.0, 36.75, 40.0), 0, 2.4),                  # SoC (Z 2.4 on the drawing)
         pi_prism(box(39.0, 25.0, 50.6, 40.0), 0, 1.0),                    # RAM
         pi_prism(box(55.6, 20.1, 63.6, 28.0), 0, 1.0),                    # VL805 USB
         pi_prism(box(55.6, 35.1, 61.5, 41.0), 0, 0.9),                    # Ethernet PHY
         pi_prism(box(6.6, 36.0, 17.3, 49.2), 0, 2.0),                     # Wi-Fi/BT shield
         pi_prism(box(7.3, 9.9, 12.5, 14.7), 0, 0.9),                      # PMIC
         pi_prism(box(1.0, 21.0, 15.0, 35.0), -PCB_T - 1.5, -PCB_T),       # microSD socket (underside)
         pi_prism(box(-2.4, 22.5, 13.0, 33.5), -PCB_T - 1.1, -PCB_T - 0.3)]  # microSD card
add("Raspberry Pi 4B - микросхемы", union(chips), "2a2a2a")

# ================= cooler: GeeekPi Armor Lite =================
ear = (box(0.5, 42.5, 6.5, 52.5) | disc((3.5, 52.5), 6.0))                # top-left ear round the hole
tab = (box(58.5, 3.5, 64.5, 12.5) | disc((61.5, 3.5), 6.0))                # bottom-right tab
body = (box(0.5, 12.5, 20.5, 42.5) | box(20.5, 12.5, 64.5, 49.5)) - box(59.7, 14.1, 65.0, 38.1)
fan_hole = disc(FAN_C, FAN_D + 1.5)
fins = shapely.union_all([box(0.5, v, 64.5, v + FIN_T) for v in np.arange(12.5, 49.5 - FIN_T + 0.01, FIN_PITCH)]
                         + [box(0.5, 49.5 - FIN_T, 64.5, 49.5)]) & body
hs = [pi_prism(body, HS_BASE[0], HS_BASE[1]), pi_prism(fins - fan_hole, HS_BASE[1], HS_H),
      pi_prism(ear - disc((3.5, 52.5), 2.2), 0, HS_BASE[1]), pi_prism(tab - disc((61.5, 3.5), 2.2), 0, HS_BASE[1])]
pads = [box(39.5, 25.5, 50.1, 39.5), box(56.0, 20.5, 63.2, 27.6), box(56.0, 35.5, 61.1, 40.6)]  # pedestals to RAM, VL805, PHY
hs += [pi_prism(p, 2.0, HS_BASE[0] + 0.01) for p in pads]
cooler = union(hs) - mf.Manifold.batch_boolean(
    [pi_prism(box(58.4, 43.4, 64.6, 49.6), -0.1, 9.0),                      # relief over the PoE header
     pi_prism(box(0.0, 16.6, 6.0, 40.7), -0.1, HS_H + 0.1),                 # DSI connector + ribbon (left edge step)
     pi_prism(box(44.6, 12.0, 49.5, 23.0), -0.1, HS_H + 0.1)], mf.OpType.Add)  # CSI slot (underside photo)
add("Охлаждение - радиатор", cooler, "1b1b1b")
therm = [pi_prism(box(21.75, 25.0, 36.75, 40.0), 2.4, 3.4), pi_prism(box(39.5, 25.5, 50.1, 39.5), 1.0, 2.0),
         pi_prism(box(56.0, 20.5, 63.2, 27.6), 1.0, 2.0), pi_prism(box(56.0, 35.5, 61.1, 40.6), 0.9, 2.0)]
add("Охлаждение - термопрокладки", union(therm), "e39a9a")
fan_w0 = HS_H - FAN_T - 0.1
blades = []
for k in range(5):
    a = np.radians(72 * k)
    blade = Polygon([(6.0, -2.5), (12.0, -4.5), (17.0, -3.0), (17.2, 3.5), (11.0, 3.0), (6.0, 2.0)])
    blade = shapely.affinity.rotate(blade, 72 * k, origin=(0, 0))
    blades.append(shapely.affinity.translate(blade, *FAN_C))
fan = [pi_prism(disc(FAN_C, 13.0), fan_w0, fan_w0 + FAN_T), pi_prism(shapely.union_all(blades), fan_w0 + 3.0, fan_w0 + 6.5)]
spokes = shapely.union_all([shapely.affinity.rotate(box(FAN_C[0], FAN_C[1] - 1.0, FAN_C[0] + 18.5, FAN_C[1] + 1.0),
                                                    a, origin=FAN_C) for a in (30, 150, 270)]) & disc(FAN_C, FAN_D + 1.4)
fan.append(pi_prism(spokes, fan_w0, fan_w0 + 1.5))                         # motor bracket arms to the heatsink
add("Охлаждение - вентилятор", union(fan), "0e0e0e")
plugs = [pi_prism(box(u - 1.27, 53.77 - 1.27, u + 1.27, 53.77 + 1.27), 2.5, 16.5) for u in (10.91, 13.45, 15.99)]
add("Охлаждение - разъёмы GPIO", union(plugs), "222222")      # dupont housings on pins 4/6/8 (5V, GND, GPIO14)

# ================= display: Waveshare 4.3" DSI =================
dcx, dcy = DISP_C
dw, dh = DISP_WH
outline = box(dcx - dw / 2, dcy - dh / 2, dcx + dw / 2, dcy + dh / 2)
corner_pts = [(dcx + sx * (dw / 2 - CORNER_HOLES[0]), dcy + sy * (dh / 2 - CORNER_HOLES[1])) for sx in (-1, 1) for sy in (-1, 1)]
pi_pts = [(PI_X0 + u, PI_Y0 + v) for u, v in HOLES]
holes = shapely.union_all([disc(p, 2.7) for p in corner_pts + pi_pts])
z_mod, z_pcb = GLASS_T, GLASS_T + MODULE_T
add("Экран - стекло", prism(outline, 0, GLASS_T), "0a0a0a")
add("Экран - изображение", prism(box(dcx - ACTIVE_WH[0] / 2, dcy - ACTIVE_WH[1] / 2, dcx + ACTIVE_WH[0] / 2,
                                      dcy + ACTIVE_WH[1] / 2), -0.05, 0.0), "16324f")
add("Экран - матрица", prism(outline.buffer(-0.5, join_style="mitre"), z_mod, z_pcb), "4a4a4a")
add("Экран - плата", prism(outline - holes, z_pcb, z_pcb + DPCB_T), "202020")
top = z_pcb + DPCB_T
stand = [prism(hexagon(p, STANDOFF_AF) - disc(p, 2.5), top, PCB_TOP - PCB_T) for p in pi_pts]
stand += [prism(hexagon(p, STANDOFF_AF) - disc(p, 2.5), top, BOSS_Z0) for p in corner_pts]
add("Экран - стойки", union(stand), "b08d57")
screws = [prism(disc((PI_X0 + u, PI_Y0 + v), 4.5), PCB_TOP, PCB_TOP + 1.8) for u, v in ((61.5, 52.5), (3.5, 3.5))]
add("Экран - винты", union(screws), "9a9a9a")      # the other two Pi holes carry the cooler's ears


# ---- save: parts, whole devices, colours
def save(man, path):
    m = man.to_mesh()
    t = trimesh.Trimesh(np.asarray(m.vert_properties)[:, :3], np.asarray(m.tri_verts), process=True)
    t.update_faces(t.nondegenerate_faces())
    t.remove_unreferenced_vertices()
    t.export(path)
    return t.is_watertight


colours = {}
for name, (man, col) in parts.items():
    assert man.status() == mf.Error.NoError and man.volume() > 0, name
    ok = save(man, os.path.join(out, name + ".stl"))
    colours[name] = col
    b = man.bounding_box()
    print(f"{name:34s} z {b[2]:6.2f}..{b[5]:6.2f}  volume {man.volume() / 1000:7.3f} cm3  watertight {ok}")
for dev in sorted({n.split(" - ")[0] for n in parts}):
    save(mf.Manifold.compose([m for n, (m, _) in parts.items() if n.startswith(dev + " - ")]),
         os.path.join(out, dev + ".stl"))
json.dump(colours, open(os.path.join(out, "colours.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"Pi board top z {PCB_TOP:.1f}, cooler top z {PCB_TOP + HS_H:.1f}, GPIO plug tops z {PCB_TOP + 16.5:.1f}, "
      f"display back z {top:.1f}")
