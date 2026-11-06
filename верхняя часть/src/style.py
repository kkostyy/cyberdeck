"""Rugged styling after the reference case ("05" box), at our sizes.

Lid (from vents.py, so ports, vents and the monitor mount stay as they are): seam line and
recessed panels around the wall openings.
Back frame (built here, replaces lid.py's grille): container corrugation along the short
side with vent slots hidden in the valleys, curved X straps meeting at a band round the fan
window of the Pi's cooler (GeeekPi Armor Lite: the ridges run on across the window as an open
grille, the heatsink sits 2.6 mm under it), a flat "05" plate filling the right section, a
riveted label plate on the ribs, a buckle plate with a pocket underneath for the fan's GPIO plugs.
Corner bumper: separate part, the same for all 4 corners (print 4, e.g. in another colour);
it caps the corner over the frame and is held by the frame's corner screw: M3x8 socket cap
(DIN 912) sunk below the bumper top, through bumper and frame into a heat-set insert M3x4x5
in the lid post. Under the bumper the frame corner is thinned to 2 mm and the bumper drops a
tongue into it, so the short screw still runs through the whole insert.

Usage: style.py lid.stl texts.json out_prefix
  -> "<out_prefix> - крышка.stl", "- рамка.stl", "- угол.stl", "- сборка.stl"
texts.json: text_outline.py C:/Windows/Fonts/bahnschrift.ttf texts.json "05=24" "CYBERDECK=6"
"""
import json
import sys

import numpy as np
import shapely
import trimesh
import manifold3d as mf
import shapely.affinity
import shapely.ops
from shapely.geometry import LineString, Point, Polygon, box

lid_path, texts_path, prefix = sys.argv[1:4]

# ---- parameters
L, W, CH, H = 160.0, 110.0, 4.0, 35.0       # lid footprint, corner chamfer, height
FRAME_Z, T = 31.0, 4.0                      # back frame seat and thickness (border, straps)
FRAME = (2.0, 2.0, 158.0, 108.0, 3.5)       # frame outline (inside the lid walls), corner radius
FIELD = (10.0, 10.0, 150.0, 100.0, 3.0)     # textured field inside the border
FRAME_SCREWS = [(5.5, 5.5), (154.5, 5.5), (5.5, 104.5), (154.5, 104.5)]
# container corrugation: ridges along y, trapezoid profile (frame z: 0 = underside)
CORR_PITCH, CORR_TOP, CORR_RUN = 6.0, 1.8, 0.8  # pitch, ridge top width, flank run (valley = rest, 2.6)
CORR_Z = (1.4, 3.2)                         # valley floor, ridge top
VENT_W, VENT_KEEP = 2.0, 1.5                # slot in each valley; kept clear of straps/plates/border
# Pi 4B cooler GeeekPi Armor Lite (ZP-0110): heatsink with a 3510 fan on the Pi's component side,
# so it faces the frame. Its height is not published: HS_H is estimated, measure and update
# (same values as electronics.py, which models the Pi, the cooler and the display).
PCB_TOP = 14.0                              # Pi board top: measured USB top 30 - official USB height 16.0
HS_H = 16.0                                 # heatsink + fan above the board (estimate: 3510 fan is 10 mm thick)
FAN_AT = (86.0, 58.0)                       # fan centre: Pi (38.5, 31) from its DSI/power corner (47.5, 27)
WIN_W, WIN_H, WIN_R = 46.0, 38.0, 6.0       # grille window over the fan (Ø35); width puts its sides one valley
                                            # past the outer ribs, so all gaps are equal (4.2)
HUB_W = 7.0                                 # strap band round the window: the X straps meet here
GRILLE_TOP = 3.2                            # window ribs: the corrugation ridges carried across, top level with them
# fan plugs (dupont, 14 mm housings) on GPIO pins 4/6/8 = 5V, GND, TXD at Pi (10.9..16.0, 53.8):
# their tops reach z ~30.9, just under the frame (31), so the frame gets a pocket there under a buckle plate
PLUGS = (55.5, 77.0, 67.0, 85.0)            # pocket footprint x0, y0, x1, y1 (plugs 57..65 x 79.5..82)
PLUG_POCKET = 2.6                           # pocket depth into the frame underside (wire bend room)
# X straps: arm ends with the sideways bow of each arm (mm), from the hub corners TL, TR, BR, BL
ARMS = [((14.0, 96.0), 6.0), ((146.0, 100.0), -5.0), ((150.0, 16.0), 5.0), ((40.0, 10.0), -5.0)]
STRAP_W, STRAP_FILLET, STRAP_BEVEL = 8.0, 6.0, 0.6
PLATE_TOP, NUM_D = 3.6, 0.8                 # "05" plate filling the section between the right arms
LABEL = (33.0, 55.0, 40.0, 15.0)            # label plate on the ridges: centre x, y, width, height
LABEL_R, LABEL_Z, LABEL_TEXT, LABEL_D = 1.5, (3.0, 3.8), "CYBERDECK", 0.4
BUMP_T = 3.0                                # bumper wall: sticks out past the lid walls and the frame
BUMP_L = 10.0                               # along each wall from the corner (vent panels start ~11)
BUMP_Z0 = 9.0                               # bumper skirt reaches down to here
BUMP_C, BUMP_C_IN = 1.6, 0.6                # chamfer on the bumper's outer / inner top edges (inner one
                                            # small, so the head counterbore keeps a rim)
BUMP_GROOVE = (21.0, 1.2, 0.6)              # moulding line round the skirt: z centre, height, depth
BUMP_GAP = 0.2                              # fit around the lid corner and in the frame recess
BUMP_IN, FRAME_UNDER = 9.5, 2.0             # frame recess under the bumper: reach from the corner, frame left below
SCREW_AT, SCREW_D, SCREW_L = (5.5, 5.5), 3.3, 8.0   # frame corner screw M3x8 (length under the head)
HEAD_D, HEAD_H, HEAD_SINK = 6.0, 3.0, 0.3   # counterbore for the DIN 912 head (d 5.5, h 3), head sunk below the top
INSERT_D, INSERT_L, INSERT_OD = 4.2, 4.0, 5.0   # heat-set insert M3x4x5: hole, insert length, outer diameter
INSERT_SPARE = 2.0                          # hole deeper than the insert (melt, screw tip)
INSERT_LEAD, INSERT_LEAD_D = 0.45, 5.1      # lead-in chamfer (45°): depth, top diameter
OLD_INSERT_D = 5.0                          # 5.skp's post: Ø7 cylinder touching the walls, Ø5 hole (really 4.97)
# The insert needs more wall than 5.skp's Ø7 post gives (1.4 mm around Ø4.2), and its dirty top
# leaves slivers, so the post top is cut out and rebuilt: Ø9 from POST_Z0 up, 45° cone below.
# Radii are kept > 0.05 mm away from what stays of 5.skp (post r 3.5, frame pocket arc r 3.7),
# because skp_write welds points closer than 0.03 mm.
POST_D, POST_Z0, POST_CUT_D = 9.0, 21.5, 7.2
SEAM_Z, SEAM_D = (4.5, 5.5), 0.6            # panel line around the lid
PANEL_PAD, PANEL_R, PANEL_D = 1.5, 1.5, 0.6     # recessed panels around vents and port windows
NUM_TEXT = "05"
BOLT_D, BOLT_H = 3.0, 0.8                   # hex bolt heads: across corners, height
SEG = 48


def load(path):
    t = trimesh.load(path, process=True)
    m = mf.Manifold(mf.Mesh(vert_properties=np.asarray(t.vertices, np.float32),
                            tri_verts=np.asarray(t.faces, np.uint32)))
    assert m.status() == mf.Error.NoError, (path, m.status())
    return m


def prism(geom, z0, z1):
    contours = []
    for p in (g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "Polygon" and g.area > 0):
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    return mf.Manifold.extrude(mf.CrossSection(contours, mf.FillRule.EvenOdd), z1 - z0).translate((0, 0, z0))


def text_shape(name, at):
    """Glyph contours (even-odd) -> one shape; the tiny offset joins glyphs that touch at a point,
    which would otherwise leave non-manifold pinches in the engraving."""
    g = Polygon()
    for c in texts[name]:
        g = g.symmetric_difference(Polygon(np.asarray(c) + at).buffer(0))
    return g.buffer(0.02, join_style="mitre").simplify(0.03)     # no edges shorter than skp_write's weld


def rounded(cx, cy, w, h, r):
    return box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2).buffer(-r).buffer(r, quad_segs=SEG // 4)


def bolt(x, y, z_top):
    """Hex bolt head with a chamfered top on a surface at z_top: across corners BOLT_D, height BOLT_H
    (no tiny facets, which SketchUp would drop)."""
    hexa = lambda r: Polygon([(x + r * np.cos(a), y + r * np.sin(a)) for a in np.radians(np.arange(0, 360, 60))])
    return mf.Manifold.batch_hull([prism(hexa(BOLT_D / 2), z_top - 0.2, z_top + BOLT_H * 0.6),
                                   prism(hexa(BOLT_D / 2 - 0.35), z_top - 0.2, z_top + BOLT_H)])


def save(man, path):
    m = man.to_mesh()
    t = trimesh.Trimesh(np.asarray(m.vert_properties)[:, :3], np.asarray(m.tri_verts), process=True)
    t.update_faces(t.nondegenerate_faces())          # zero-area slivers left by 5.skp's dirty corner
    t.remove_unreferenced_vertices()
    t.export(path)
    b = man.bounding_box()
    print(f"{path}: size {np.round(np.subtract(b[3:], b[:3]), 2).tolist()} volume {man.volume() / 1000:.1f} cm3 "
          f"genus {man.genus()} watertight {t.is_watertight}")


outline = Polygon([(CH, 0), (L - CH, 0), (L, CH), (L, W - CH), (L - CH, W), (CH, W), (0, W - CH), (0, CH)])
texts = json.load(open(texts_path))

# ================= lid: seam line + recessed panels around every wall opening =================
lid = load(lid_path)
lid_mesh = trimesh.load(lid_path)
cuts = [prism(outline - outline.buffer(-SEAM_D, join_style="mitre"), *SEAM_Z)]
# wall: (section plane axis, at, axes kept, transform of a cut drawn in (a, z) and pushed in from outside)
WALLS = {1: (0, 1.0, (1, 2), [[0, 0, 1, -1.0], [1, 0, 0, 0], [0, 1, 0, 0]]),
         2: (0, L - 1.0, (1, 2), [[0, 0, 1, L - PANEL_D], [1, 0, 0, 0], [0, 1, 0, 0]]),
         3: (1, 1.0, (0, 2), [[1, 0, 0, 0], [0, 0, -1, PANEL_D], [0, 1, 0, 0]]),
         4: (1, W - 1.0, (0, 2), [[1, 0, 0, 0], [0, 0, -1, W + 1.0], [0, 1, 0, 0]])}
for wall, (axis, at, keep, xf) in WALLS.items():
    n = np.zeros(3); n[axis] = 1; o = np.zeros(3); o[axis] = at
    sec = lid_mesh.section(plane_origin=o, plane_normal=n)
    g = Polygon()
    for d in sec.discrete:
        g = g.symmetric_difference(Polygon(d[:, list(keep)]).buffer(0))
    holes = sorted((Polygon(h) for p in getattr(g, "geoms", [g]) for h in p.interiors), key=lambda p: p.bounds[0])
    groups = []                                              # slots close together -> one panel; windows alone
    for h in holes:
        if groups and h.area < 100 and groups[-1][-1].area < 100 and h.distance(groups[-1][-1]) < 4.0:
            groups[-1].append(h)
        else:
            groups.append([h])
    for grp in groups:
        a0, z0, a1, z1 = shapely.union_all(grp).bounds
        panel = rounded((a0 + a1) / 2, (z0 + z1) / 2, a1 - a0 + 2 * PANEL_PAD, z1 - z0 + 2 * PANEL_PAD, PANEL_R)
        cuts.append(prism(panel, 0, PANEL_D + 1.0).transform(np.array(xf, float)))
    print(f"wall {wall}: {len(holes)} openings in {len(groups)} panels")
lid = mf.Manifold.batch_boolean([lid] + cuts, mf.OpType.Subtract)

# heat-set inserts in the 4 corner posts: fill 5.skp's Ø5 hole, cut the insert hole with a lead-in
v = np.asarray(lid_mesh.vertices)
wall_v = v[np.abs(np.hypot(v[:, 0] - SCREW_AT[0], v[:, 1] - SCREW_AT[1]) - OLD_INSERT_D / 2) < 0.05]
post_top = wall_v[:, 2].max()
assert abs(post_top - FRAME_Z) < 0.01, f"post top at {post_top}, frame seat at {FRAME_Z}"
ins_bot = post_top - INSERT_L - INSERT_SPARE
disc = lambda p, d: Point(p).buffer(d / 2, quad_segs=SEG // 4)
cone_z0 = POST_Z0 - (POST_D - POST_CUT_D) / 2                  # 45° from the cut radius out to the new post
cut_z0 = cone_z0 + 0.5
lid = lid - mf.Manifold.batch_boolean([prism(disc(p, POST_CUT_D), cut_z0, post_top + 1) for p in FRAME_SCREWS],
                                      mf.OpType.Add)
inner = outline.buffer(-0.5, join_style="mitre")               # new post may run into the walls, not through them
lid = mf.Manifold.batch_boolean([lid] + [mf.Manifold.batch_hull([prism(disc(p, POST_CUT_D) & inner, cone_z0 - 1.0, cone_z0),
                                                                prism(disc(p, POST_D) & inner, POST_Z0, post_top)])
                                         for p in FRAME_SCREWS], mf.OpType.Add)
lid = mf.Manifold.batch_boolean([lid] + [prism(disc(p, INSERT_D), ins_bot, post_top + 1) for p in FRAME_SCREWS]
                                + [mf.Manifold.batch_hull([prism(disc(p, INSERT_D), post_top - INSERT_LEAD, post_top + 1),
                                                           prism(disc(p, INSERT_LEAD_D), post_top, post_top + 1)])
                                   for p in FRAME_SCREWS], mf.OpType.Subtract)

# ================= back frame: corrugation, curved X straps, plates =================
def bezier(p0, p2, bow, n=40):
    """Quadratic curve p0 -> p2, middle pushed sideways by `bow` mm."""
    p0, p2 = np.asarray(p0), np.asarray(p2)
    d = p2 - p0
    c = (p0 + p2) / 2 + bow * np.array([-d[1], d[0]]) / np.linalg.norm(d)
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * c + t ** 2 * p2


def fit_text(name, region, margin=1.5, angles=(0, 90)):
    """Largest scale/orientation of the text that fits inside region, centred at its pole."""
    centre = shapely.ops.polylabel(region, tolerance=0.2)
    inner = region.buffer(-margin)
    for scale in np.arange(1.4, 0.5, -0.05):
        for ang in angles:
            g = shapely.affinity.rotate(shapely.affinity.scale(text_shape(name, (0, 0)), scale, scale, origin=(0, 0)),
                                        ang, origin=(0, 0))
            g = shapely.affinity.translate(g, centre.x, centre.y)
            if inner.contains(g):
                return g, scale, ang
    raise RuntimeError(f"{name} does not fit")


def along(line, dist):
    """Point `dist` mm back from the end of a centre line."""
    return line.interpolate(line.length - dist).coords[0]


fx0, fy0, fx1, fy1, fr = FIELD
field = rounded((fx0 + fx1) / 2, (fy0 + fy1) / 2, fx1 - fx0, fy1 - fy0, fr)
ox0, oy0, ox1, oy1, orr = FRAME
fouter = rounded((ox0 + ox1) / 2, (oy0 + oy1) / 2, ox1 - ox0, oy1 - oy0, orr)
# the X straps meet a band (hub) round the fan window instead of a node
cx, cy = FAN_AT
window = rounded(cx, cy, WIN_W, WIN_H, WIN_R)
hub = rounded(cx, cy, WIN_W + 2 * HUB_W, WIN_H + 2 * HUB_W, WIN_R + HUB_W)
starts = [(cx - WIN_W / 2, cy + WIN_H / 2), (cx + WIN_W / 2, cy + WIN_H / 2),      # window corners, inside the band
          (cx + WIN_W / 2, cy - WIN_H / 2), (cx - WIN_W / 2, cy - WIN_H / 2)]
centre_lines = [LineString(bezier(s, end, bow)) for s, (end, bow) in zip(starts, ARMS)]
plugs = box(*PLUGS)
buckle = plugs.buffer(1.6, join_style="mitre").buffer(1.0, quad_segs=SEG // 4)   # strap plate over the fan plugs
straps = shapely.union_all([c.buffer(STRAP_W / 2, cap_style="flat") for c in centre_lines] + [hub, buckle])
straps = straps.buffer(STRAP_FILLET, quad_segs=SEG // 4).buffer(-STRAP_FILLET, quad_segs=SEG // 4) & fouter
# sections between the straps; opening by 0.3 mm drops slivers and point contacts where an arm
# meets the field edge (they would leave non-manifold pinches); border + straps = the rest
zones = (field - straps).buffer(-0.3, join_style="mitre").buffer(0.3, join_style="mitre")
plate = next(g for g in zones.geoms if g.contains(Point(fx1 - 3, cy)))       # right section
corr_zone = zones - plate
top = fouter - zones - window
assert top.buffer(-1.0).contains(plugs - window.buffer(1.2)), "fan plug pocket leaves the straps"
hs_top = PCB_TOP + HS_H
assert hs_top < FRAME_Z - 0.5, f"heatsink top {hs_top} hits the frame"

# corrugation profile in (x, z), pushed along y over the field
ridges = np.arange(L / 2 - 30 * CORR_PITCH, L / 2 + 30 * CORR_PITCH, CORR_PITCH)
wave = []
for xr in ridges:
    wave += [(xr - CORR_TOP / 2 - CORR_RUN, CORR_Z[0]), (xr - CORR_TOP / 2, CORR_Z[1]),
             (xr + CORR_TOP / 2, CORR_Z[1]), (xr + CORR_TOP / 2 + CORR_RUN, CORR_Z[0])]
profile = Polygon([(wave[0][0], 0)] + wave + [(wave[-1][0], 0)]) & box(fx0 - 1, 0, fx1 + 1, T)
corr = prism(profile, 0, fy1 - fy0 + 2).transform(np.array([[1, 0, 0, 0], [0, 0, -1, fy1 + 1], [0, 1, 0, 0]], float))
corr = corr ^ prism(corr_zone, -1, T + 1)
# fan grille: the ridges run on across the window as free ribs, valleys open
wx0, wy0, wx1, wy1 = window.bounds
grille = shapely.union_all([box(xr - CORR_TOP / 2, wy0 - 1, xr + CORR_TOP / 2, wy1 + 1)
                            for xr in ridges if wx0 + 2.5 < xr < wx1 - 2.5]) & window.buffer(0.5)

lx, ly, lw, lh = LABEL
label = rounded(lx, ly, lw, lh, LABEL_R)
assert corr_zone.buffer(-1.0).contains(label), "label plate leaves its section"
bevel = [prism(top.buffer(-STRAP_BEVEL * k / 3, join_style="mitre"),
               T - STRAP_BEVEL + STRAP_BEVEL * (k - 1) / 3, T - STRAP_BEVEL + STRAP_BEVEL * k / 3) for k in (1, 2, 3)]
frame = mf.Manifold.batch_boolean([prism(top, 0, T - STRAP_BEVEL), *bevel, prism(grille, 0, GRILLE_TOP),
                                   prism(plate, 0, PLATE_TOP), corr, prism(label, *LABEL_Z)], mf.OpType.Add)

# vents: a slot along the floor of every valley, clear of straps, plates and the border
valleys = shapely.union_all([box(xr + CORR_PITCH / 2 - VENT_W / 2, fy0, xr + CORR_PITCH / 2 + VENT_W / 2, fy1)
                             for xr in ridges])
vents = valleys & (corr_zone - label.buffer(VENT_KEEP)).buffer(-VENT_KEEP)
vents = vents.buffer(-VENT_W / 2 + 0.01, quad_segs=8).buffer(VENT_W / 2 - 0.01, quad_segs=8)
vents = shapely.union_all([v for v in getattr(vents, "geoms", [vents]) if v.length > 2 * VENT_W + 8])
num, num_scale, num_ang = fit_text(NUM_TEXT, plate, angles=(0,))              # upright, as on the reference
lab, lab_scale, _ = fit_text(LABEL_TEXT, label, margin=2.5)
holes = shapely.union_all([Point(p).buffer(SCREW_D / 2, quad_segs=SEG // 4) for p in FRAME_SCREWS])
recess = shapely.union_all([box(-2.0, -2.0, BUMP_IN, BUMP_IN), box(L - BUMP_IN, -2.0, L + 2.0, BUMP_IN),   # under the bumpers
                            box(-2.0, W - BUMP_IN, BUMP_IN, W + 2.0),
                            box(L - BUMP_IN, W - BUMP_IN, L + 2.0, W + 2.0)])
frame = mf.Manifold.batch_boolean([frame, prism(vents, -1, CORR_Z[0] + 0.5), prism(holes, -1, T + 1),
                                   prism(recess, FRAME_UNDER, T + 1),
                                   prism(plugs - window.buffer(1.2), -1, PLUG_POCKET),
                                   prism(num, PLATE_TOP - NUM_D, T + 1),
                                   prism(lab, LABEL_Z[1] - LABEL_D, T + 1)], mf.OpType.Subtract)

bolts = [bolt(*along(c, 7.0), T) for c in centre_lines]                        # strap ends
bolts += [bolt(lx + sx * (lw / 2 - 2.5), ly + sy * (lh / 2 - 2.5), LABEL_Z[1]) for sx in (-1, 1) for sy in (-1, 1)]
pb = plate.buffer(-4.0).bounds                                                  # plate: two bolts at the border side
bolts += [bolt(pb[2], pb[1] + 4, PLATE_TOP), bolt(pb[2], pb[3] - 4, PLATE_TOP)]
k = (WIN_W / 2 - WIN_R) + (WIN_R + HUB_W / 2) / np.sqrt(2)                       # hub band corners
bolts += [bolt(cx + sx * k, cy + sy * k, T) for sx in (-1, 1) for sy in (-1, 1)]
bolts += [bolt(PLUGS[0] + 0.3, PLUGS[1] + 1.2, T), bolt(PLUGS[0] + 0.3, PLUGS[3] - 1.2, T)]   # buckle plate
frame = mf.Manifold.batch_boolean([frame] + bolts, mf.OpType.Add)
fan_open = (window - grille).intersection(Point(FAN_AT).buffer(17.5)).area
print(f"frame: {len(getattr(vents, 'geoms', [vents]))} vent slots, open area {vents.area:.0f} mm2; "
      f"fan grille {len(getattr(grille, 'geoms', [grille]))} ribs, open {(window - grille).area:.0f} mm2 "
      f"({fan_open:.0f} over the fan disc); heatsink top {hs_top:.1f}, {FRAME_Z - hs_top:.1f} under the frame; "
      f"plug tops {PCB_TOP + 16.5:.1f}, pocket roof at {FRAME_Z + PLUG_POCKET:.1f}, "
      f"left above it {T - PLUG_POCKET:.1f}; '{NUM_TEXT}' x{num_scale:.2f} rot {num_ang}, label text x{lab_scale:.2f}")

# ================= corner bumper (corner at x=0, y=0; same part fits all four) =================
ztop = H + BUMP_T
fp = outline.buffer(BUMP_T, join_style="mitre") & box(-BUMP_T - 1, -BUMP_T - 1, BUMP_L, BUMP_L)
fp_top = (outline.buffer(BUMP_T - BUMP_C, join_style="mitre")
          & box(-BUMP_T - 1, -BUMP_T - 1, BUMP_L - BUMP_C_IN, BUMP_L - BUMP_C_IN))
bumper = mf.Manifold.batch_hull([prism(fp, BUMP_Z0 + BUMP_C, ztop - BUMP_C),
                                 prism(fp.buffer(-BUMP_C, join_style="mitre"), BUMP_Z0, BUMP_Z0 + BUMP_C),
                                 prism(fp_top, ztop - BUMP_C, ztop)])
sx, sy = SCREW_AT
gz, gh, gd = BUMP_GROOVE
bumper = mf.Manifold.batch_boolean([bumper,
                                    prism(fp - fp.buffer(-gd, join_style="mitre"), gz - gh / 2, gz + gh / 2),
                                    prism(outline.buffer(BUMP_GAP, join_style="mitre"), BUMP_Z0 - 1, H)],
                                   mf.OpType.Subtract)
tongue = fouter & box(-2.0, -2.0, BUMP_IN - BUMP_GAP, BUMP_IN - BUMP_GAP)      # drops into the frame recess
under = FRAME_Z + FRAME_UNDER
seat = ztop - HEAD_H - HEAD_SINK                                                # under side of the screw head
bumper = (bumper + prism(tongue, under, H + 0.01)) - mf.Manifold.batch_boolean(
    [prism(disc(SCREW_AT, SCREW_D), under - 1, ztop + 1), prism(disc(SCREW_AT, HEAD_D), seat, ztop + 1)], mf.OpType.Add)
tip = seat - SCREW_L
grip = min(post_top, seat) - max(tip, post_top - INSERT_L)
print(f"corner screw: head {seat:.1f}..{seat + HEAD_H:.1f} (bumper top {ztop:.1f}), plastic under head "
      f"{seat - under:.1f}, frame under bumper {FRAME_UNDER:.1f}; tip at {tip:.1f}, insert {post_top - INSERT_L:.1f}.."
      f"{post_top:.1f} -> thread in insert {grip:.1f} of {INSERT_L:.1f}, hole bottom {ins_bot:.1f} "
      f"({tip - ins_bot:.1f} below the tip)")
assert seat + HEAD_H <= ztop and tip > ins_bot + 0.5 and grip >= INSERT_L - 0.01

save(lid, f"{prefix} - крышка.stl")
save(frame, f"{prefix} - рамка.stl")
save(bumper, f"{prefix} - угол.stl")
corners = [bumper, bumper.mirror((1, 0, 0)).translate((L, 0, 0)), bumper.mirror((0, 1, 0)).translate((0, W, 0)),
           bumper.mirror((1, 0, 0)).mirror((0, 1, 0)).translate((L, W, 0))]
asm = mf.Manifold.compose([lid, frame.translate((0, 0, FRAME_Z))] + corners)
save(asm, f"{prefix} - сборка.stl")
# parts must not overlap in the assembly
for name, part in (("frame", frame.translate((0, 0, FRAME_Z))), *((f"corner {i}", c) for i, c in enumerate(corners))):
    print(f"overlap lid/{name}: {(lid ^ part).volume():.3f} mm3")
print(f"overlap frame/corners: {sum((frame.translate((0, 0, FRAME_Z)) ^ c).volume() for c in corners):.3f} mm3")
