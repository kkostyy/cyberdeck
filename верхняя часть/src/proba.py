"""Monitor pocket test part ("proba"): flange, 2 mm walls around the display pocket,
4 identical corner bosses with a small screw hole.

Built from the user's edited corner in "proba na izminenie 4.skp" (bottom right),
mirrored to all 4 corners; the pocket is centred in the flange.
Earlier corners: v2 HOLE_DX, HOLE_DY = 3.0, 2.5, BOSS_R = 2.3, BOSS_ALONG = 5.3 / 4.8;
v3 HOLE_DX, HOLE_DY = 3.5, 3.5, BOSS_R = 3.5, BOSS_ALONG = 7.0.

Usage: proba.py out.stl
"""
import sys

import numpy as np
import trimesh
import manifold3d as mf
from shapely.geometry import Point, box

# ---- parameters
FLANGE = (23.5, 17.5, 136.5, 92.5)   # outer flange, z 0..FLANGE_H
FLANGE_H = 2.0
POCKET_W, POCKET_H = 106.5, 68.5     # display pocket, through, centred in the flange
WALL, WALL_H = 2.0, 12.0
GROOVE_D, GROOVE_Z = 1.0, (1.0, 7.0)  # slot in the long wall at the high-y side
HOLE_D = 2.6
HOLE_DX, HOLE_DY = 3.0, 4.0          # hole centre from the short / long pocket wall
BOSS_R = 3.0                         # inner corner of the boss, concentric with the hole
BOSS_ALONG = 8.0                     # boss length along each wall, from the inner pocket corner
BOSS_Z0, BOSS_TOP = 13.0, 23.0       # underside over the pocket, top
SEG = 48                             # segments per full circle


def prism(geom, z0, z1):
    polys = [g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "Polygon" and g.area > 0]
    contours = []
    for p in polys:
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    cs = mf.CrossSection(contours, mf.FillRule.EvenOdd)
    return mf.Manifold.extrude(cs, z1 - z0).translate((0, 0, z0))


def circle(c, r):
    return Point(c).buffer(r, quad_segs=SEG // 4)


cx, cy = (FLANGE[0] + FLANGE[2]) / 2, (FLANGE[1] + FLANGE[3]) / 2


def build():
    """-> (body, pocket outline, groove cut). The groove is returned so a part that unions
    the body into other geometry (vents.py, the lid) can cut it again."""
    pocket = box(cx - POCKET_W / 2, cy - POCKET_H / 2, cx + POCKET_W / 2, cy + POCKET_H / 2)
    outer = pocket.buffer(WALL, join_style="mitre")
    body = prism(box(*FLANGE) - pocket, 0, FLANGE_H) + prism(outer - pocket, 0, WALL_H)
    holes = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            hx = cx + sx * (POCKET_W / 2 - HOLE_DX)
            hy = cy + sy * (POCKET_H / 2 - HOLE_DY)
            ix, iy = cx + sx * POCKET_W / 2, cy + sy * POCKET_H / 2
            ox, oy = ix + sx * WALL, iy + sy * WALL
            fp = (box(min(hx - sx * BOSS_R, ox), min(oy, hy), max(hx - sx * BOSS_R, ox), max(oy, hy))
                  | box(min(hx, ox), min(oy, hy - sy * BOSS_R), max(hx, ox), max(oy, hy - sy * BOSS_R))
                  | circle((hx, hy), BOSS_R)
                  | box(min(ix - sx * BOSS_ALONG, ox), min(oy, iy), max(ix - sx * BOSS_ALONG, ox), max(oy, iy))
                  | box(min(ix, ox), min(oy, iy - sy * BOSS_ALONG), max(ix, ox), max(oy, iy - sy * BOSS_ALONG)))
            body += prism(fp - pocket, 0, BOSS_TOP) + prism(fp & pocket, BOSS_Z0, BOSS_TOP)
            holes.append(prism(circle((hx, hy), HOLE_D / 2), BOSS_Z0 - 1, BOSS_TOP + 1))
    x0, y0, x1, y1 = pocket.bounds
    groove = prism(box(x0, y1 - 0.01, x1, y1 + GROOVE_D), *GROOVE_Z)
    body = mf.Manifold.batch_boolean([body, groove] + holes, mf.OpType.Subtract)
    return body, pocket, groove


if __name__ == "__main__":
    body, pocket, _ = build()
    m = body.to_mesh()
    t = trimesh.Trimesh(np.asarray(m.vert_properties)[:, :3], np.asarray(m.tri_verts), process=True)
    t.export(sys.argv[1])
    b = body.bounding_box()
    print(f"{sys.argv[1]}: size {np.round(np.subtract(b[3:], b[:3]), 2).tolist()} volume {body.volume() / 1000:.2f} cm3 "
          f"genus {body.genus()} watertight {t.is_watertight}")
    print("pocket", np.round(pocket.bounds, 2).tolist(), "holes at",
          [(round(cx + sx * (POCKET_W / 2 - HOLE_DX), 2), round(cy + sy * (POCKET_H / 2 - HOLE_DY), 2)) for sx in (-1, 1) for sy in (-1, 1)])
