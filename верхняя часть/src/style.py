"""Rugged styling after the reference case ("05" box), at our sizes.

Lid (from vents.py, so ports, vents and the monitor mount stay as they are): seam line and
recessed panels around the wall openings.
Back frame (built here, replaces lid.py's grille): container corrugation along the short
side with vent slots hidden in the valleys, curved X straps meeting at an off-centre node
(as in the reference: node right of and below centre, arms to three corners and the bottom
edge), a flat "05" plate filling the right section, a riveted label plate on the ribs.
Corner bumper: separate part, the same for all 4 corners (print 4, e.g. in another colour);
it caps the corner over the frame and is held by the frame's corner screw (M3x10).

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
# X straps: node, arm ends with the sideways bow of each arm (mm), strap width, junction fillet
NODE = (99.0, 44.0)
ARMS = [((12.0, 98.0), 6.0), ((146.0, 102.0), -5.0), ((152.0, 14.0), 5.0), ((71.0, 8.0), -6.0)]
STRAP_W, STRAP_FILLET, STRAP_BEVEL = 8.0, 6.0, 0.6
PLATE_TOP, NUM_D = 3.6, 0.8                 # "05" plate filling the section between the right arms
LABEL = (47.0, 33.0, 48.0, 16.0)            # label plate on the ridges: centre x, y, width, height
LABEL_R, LABEL_Z, LABEL_TEXT, LABEL_D = 1.5, (3.0, 3.8), "CYBERDECK", 0.4
BUMP_T = 3.0                                # bumper wall: sticks out past the lid walls and the frame
BUMP_L = 10.0                               # along each wall from the corner (vent panels start ~11)
BUMP_Z0 = 9.0                               # bumper skirt reaches down to here
BUMP_C = 1.6                                # chamfer on the bumper's outer edges
BUMP_GROOVE = (21.0, 1.2, 0.6)              # moulding line round the skirt: z centre, height, depth
BUMP_GAP = 0.2                              # fit around the lid corner
SCREW_AT, SCREW_D = (5.5, 5.5), 3.3         # frame corner screw (M3)
HEAD_D, HEAD_SEAT = 6.5, 0.6                # seat for the M3 button head
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

# ================= back frame: corrugation, curved X straps, plates =================
def bezier(p0, p2, bow, n=40):
    """Quadratic curve p0 -> p2, middle pushed sideways by `bow` mm."""
    p0, p2 = np.asarray(p0), np.asarray(p2)
    d = p2 - p0
    c = (p0 + p2) / 2 + bow * np.array([-d[1], d[0]]) / np.linalg.norm(d)
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * c + t ** 2 * p2


def fit_text(name, region, margin=1.5):
    """Largest scale/orientation of the text that fits inside region, centred at its pole."""
    centre = shapely.ops.polylabel(region, tolerance=0.2)
    inner = region.buffer(-margin)
    for scale in np.arange(1.4, 0.5, -0.05):
        for ang in (0, 90):
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
centre_lines = [LineString(bezier(NODE, end, bow)) for end, bow in ARMS]
straps = shapely.union_all([c.buffer(STRAP_W / 2, cap_style="flat") for c in centre_lines]
                           + [Point(NODE).buffer(STRAP_W * 0.75, quad_segs=SEG // 4)])
straps = straps.buffer(STRAP_FILLET, quad_segs=SEG // 4).buffer(-STRAP_FILLET, quad_segs=SEG // 4) & fouter
# sections between the straps; opening by 0.3 mm drops slivers and point contacts where an arm
# meets the field edge (they would leave non-manifold pinches); border + straps = the rest
zones = (field - straps).buffer(-0.3, join_style="mitre").buffer(0.3, join_style="mitre")
plate = next(g for g in zones.geoms if g.contains(Point(fx1 - 3, NODE[1])))   # right section
corr_zone = zones - plate
top = fouter - zones

# corrugation profile in (x, z), pushed along y over the field
ridges = np.arange(L / 2 - 30 * CORR_PITCH, L / 2 + 30 * CORR_PITCH, CORR_PITCH)
wave = []
for xr in ridges:
    wave += [(xr - CORR_TOP / 2 - CORR_RUN, CORR_Z[0]), (xr - CORR_TOP / 2, CORR_Z[1]),
             (xr + CORR_TOP / 2, CORR_Z[1]), (xr + CORR_TOP / 2 + CORR_RUN, CORR_Z[0])]
profile = Polygon([(wave[0][0], 0)] + wave + [(wave[-1][0], 0)]) & box(fx0 - 1, 0, fx1 + 1, T)
corr = prism(profile, 0, fy1 - fy0 + 2).transform(np.array([[1, 0, 0, 0], [0, 0, -1, fy1 + 1], [0, 1, 0, 0]], float))
corr = corr ^ prism(corr_zone, -1, T + 1)

lx, ly, lw, lh = LABEL
label = rounded(lx, ly, lw, lh, LABEL_R)
assert corr_zone.buffer(-1.0).contains(label), "label plate leaves its section"
bevel = [prism(top.buffer(-STRAP_BEVEL * k / 3, join_style="mitre"),
               T - STRAP_BEVEL + STRAP_BEVEL * (k - 1) / 3, T - STRAP_BEVEL + STRAP_BEVEL * k / 3) for k in (1, 2, 3)]
frame = mf.Manifold.batch_boolean([prism(top, 0, T - STRAP_BEVEL), *bevel,
                                   prism(plate, 0, PLATE_TOP), corr, prism(label, *LABEL_Z)], mf.OpType.Add)

# vents: a slot along the floor of every valley, clear of straps, plates and the border
valleys = shapely.union_all([box(xr + CORR_PITCH / 2 - VENT_W / 2, fy0, xr + CORR_PITCH / 2 + VENT_W / 2, fy1)
                             for xr in ridges])
vents = valleys & (corr_zone - label.buffer(VENT_KEEP)).buffer(-VENT_KEEP)
vents = vents.buffer(-VENT_W / 2 + 0.01, quad_segs=8).buffer(VENT_W / 2 - 0.01, quad_segs=8)
vents = shapely.union_all([v for v in getattr(vents, "geoms", [vents]) if v.length > 2 * VENT_W + 8])
num, num_scale, num_ang = fit_text(NUM_TEXT, plate)
lab, lab_scale, _ = fit_text(LABEL_TEXT, label, margin=2.5)
holes = shapely.union_all([Point(p).buffer(SCREW_D / 2, quad_segs=SEG // 4) for p in FRAME_SCREWS])
frame = mf.Manifold.batch_boolean([frame, prism(vents, -1, CORR_Z[0] + 0.5), prism(holes, -1, T + 1),
                                   prism(num, PLATE_TOP - NUM_D, T + 1),
                                   prism(lab, LABEL_Z[1] - LABEL_D, T + 1)], mf.OpType.Subtract)

bolts = [bolt(*along(c, 7.0), T) for c in centre_lines]                        # strap ends
bolts += [bolt(lx + sx * (lw / 2 - 2.5), ly + sy * (lh / 2 - 2.5), LABEL_Z[1]) for sx in (-1, 1) for sy in (-1, 1)]
pb = plate.buffer(-4.0).bounds                                                  # plate: two bolts at the border side
bolts += [bolt(pb[2], pb[1] + 4, PLATE_TOP), bolt(pb[2], pb[3] - 4, PLATE_TOP)]
frame = mf.Manifold.batch_boolean([frame] + bolts, mf.OpType.Add)
print(f"frame: {len(getattr(vents, 'geoms', [vents]))} vent slots, open area {vents.area:.0f} mm2; "
      f"'{NUM_TEXT}' x{num_scale:.2f} rot {num_ang}, label text x{lab_scale:.2f}")

# ================= corner bumper (corner at x=0, y=0; same part fits all four) =================
ztop = H + BUMP_T
fp = outline.buffer(BUMP_T, join_style="mitre") & box(-BUMP_T - 1, -BUMP_T - 1, BUMP_L, BUMP_L)
bumper = mf.Manifold.batch_hull([prism(fp, BUMP_Z0 + BUMP_C, ztop - BUMP_C),
                                 prism(fp.buffer(-BUMP_C, join_style="mitre"), BUMP_Z0, ztop)])
sx, sy = SCREW_AT
gz, gh, gd = BUMP_GROOVE
bumper = mf.Manifold.batch_boolean([bumper,
                                    prism(fp - fp.buffer(-gd, join_style="mitre"), gz - gh / 2, gz + gh / 2),
                                    prism(outline.buffer(BUMP_GAP, join_style="mitre"), BUMP_Z0 - 1, H),
                                    prism(Point(sx, sy).buffer(SCREW_D / 2, quad_segs=SEG // 4), H - 1, ztop + 1),
                                    prism(Point(sx, sy).buffer(HEAD_D / 2, quad_segs=SEG // 4), ztop - HEAD_SEAT, ztop + 1)],
                                   mf.OpType.Subtract)

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
