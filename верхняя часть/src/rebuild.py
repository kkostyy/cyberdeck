"""Rebuild a watertight solid from a 2.5D SketchUp triangle soup.

Every face is horizontal (at a few z levels) or vertical, so space splits into
prisms: (2D arrangement cell) x (slab between adjacent z levels). Faces act as
walls; prisms reachable from outside without crossing a face are air, the rest
is solid. This drops internal faces, hole caps and dangling faces, and ignores
T-junctions/overlaps because coverage is tested geometrically.

Usage: rebuild.py tris.npz solid.npz [regions.json]
regions.json holds the solid 2D region of every slab (WKT), which lid.py builds on.
"""
import sys
from collections import deque, defaultdict

import numpy as np
import shapely
from shapely.geometry import LineString, Polygon, MultiLineString, box, Point
from shapely.ops import unary_union, polygonize
from shapely.strtree import STRtree
import manifold3d as mf

EPS = 0.03  # SketchUp model has near-duplicate edges ~0.01 mm apart; treat them as one
T = np.round(np.load(sys.argv[1])["tris"], 4)
out_path = sys.argv[2]

n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
area2 = np.linalg.norm(n, axis=1)
keep = area2 > 1e-8
T, n = T[keep], n[keep] / area2[keep, None]
nz = np.abs(n[:, 2])
horiz = T[nz > 0.999]
vert = T[nz < 0.01]
print("tris", len(T), "horizontal", len(horiz), "vertical", len(vert), "other", len(T) - len(horiz) - len(vert))

levels = sorted(set(np.round(horiz[:, :, 2].ravel(), 3)))
slabs = list(zip(levels[:-1], levels[1:]))
print("levels", levels)

# --- horizontal coverage per level
hpolys = defaultdict(list)
for t in horiz:
    z = round(float(t[0, 2]), 3)
    p = Polygon(t[:, :2])
    if p.area > 1e-8:
        hpolys[z].append(p)
H = {z: unary_union(ps).buffer(0) for z, ps in hpolys.items()}
Hcov = {z: g.buffer(EPS) for z, g in H.items()}  # slivers along a face edge count as covered

# --- vertical walls per slab: section of each vertical tri at slab mid-height
walls = defaultdict(list)
for si, (z0, z1) in enumerate(slabs):
    zm = 0.5 * (z0 + z1)
    for t in vert:
        pts = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            pa, pb = t[a], t[b]
            da, db = pa[2] - zm, pb[2] - zm
            if da * db < 0:
                pts.append(pa[:2] + (pb[:2] - pa[:2]) * (da / (da - db)))
        if len(pts) == 2 and np.linalg.norm(pts[0] - pts[1]) > 1e-6:
            walls[si].append(LineString(pts))
wall_union = {si: unary_union(ls) for si, ls in walls.items()}
wall_tree = {si: STRtree(ls) for si, ls in walls.items()}

# --- common 2D arrangement
allpts = T[:, :, :2].reshape(-1, 2)
lo, hi = allpts.min(0) - 5, allpts.max(0) + 5
lines = [box(*lo, *hi).exterior]
for ls in walls.values():
    lines += ls
for g in H.values():
    lines.append(g.boundary)
noded = shapely.union_all(lines, grid_size=1e-4)  # snap-rounded noding keeps rings valid
atoms = [a for a in polygonize(noded) if a.area > 1e-7]
print("atoms", len(atoms))
atom_tree = STRtree(atoms)
reps = [a.representative_point() for a in atoms]
outer = max(range(len(atoms)), key=lambda i: atoms[i].area)  # frame between bbox and model


def locate(pt):
    for i in atom_tree.query(pt):
        if atoms[i].contains(pt):
            return int(i)
    return None


def on_wall(si, pt):
    if si not in walls:
        return False
    return any(walls[si][j].distance(pt) < EPS for j in wall_tree[si].query(pt.buffer(EPS)))


def covered(z, pt):
    g = Hcov.get(z)
    return g is not None and g.contains(pt)


# --- in-slab neighbours across each noded edge piece
edges2d = []
segs = [noded] if isinstance(noded, LineString) else list(getattr(noded, "geoms", [noded]))
for g in segs:
    c = np.asarray(g.coords)
    for p, q in zip(c[:-1], c[1:]):
        d = q - p
        L = np.linalg.norm(d)
        if L < 1e-7:
            continue
        mid = (p + q) / 2
        nrm = np.array([-d[1], d[0]]) / L
        off = min(1e-4, L / 10)
        a, b = locate(Point(mid + nrm * off)), locate(Point(mid - nrm * off))
        if a is not None and b is not None and a != b:
            edges2d.append((a, b, Point(mid)))
print("2D adjacencies", len(edges2d))

# --- flood fill air from outside
N = len(atoms)
S = len(slabs)
air = np.zeros((S, N), bool)
q = deque()


def push(si, ai):
    if not air[si, ai]:
        air[si, ai] = True
        q.append((si, ai))


for si in range(S):
    push(si, outer)
for ai in range(N):  # from below / above unless capped
    if not covered(levels[0], reps[ai]):
        push(0, ai)
    if not covered(levels[-1], reps[ai]):
        push(S - 1, ai)

nbr = defaultdict(list)
for a, b, mid in edges2d:
    nbr[a].append((b, mid))
    nbr[b].append((a, mid))
cov = {}
while q:
    si, ai = q.popleft()
    for b, mid in nbr[ai]:
        if not air[si, b] and not on_wall(si, mid):
            push(si, b)
    for sj, z in ((si - 1, levels[si]), (si + 1, levels[si + 1])):
        if 0 <= sj < S and not air[sj, ai]:
            key = (z, ai)
            if key not in cov:
                cov[key] = covered(z, reps[ai])
            if not cov[key]:
                push(sj, ai)

# --- extrude solid regions and union
parts = []
regions = {}
for si, (z0, z1) in enumerate(slabs):
    solid = [atoms[i] for i in range(N) if not air[si, i]]
    if not solid:
        continue
    reg = unary_union(solid).buffer(0)
    regions[f"{z0:g}-{z1:g}"] = reg.wkt
    polys = [reg] if reg.geom_type == "Polygon" else list(reg.geoms)
    print(f"slab {z0:>5}-{z1:<5} solid area {reg.area:10.2f} mm2, {len(polys)} pieces")
    contours = []
    for p in polys:
        contours.append(np.asarray(p.exterior.coords)[:-1])
        contours += [np.asarray(r.coords)[:-1] for r in p.interiors]
    cs = mf.CrossSection(contours, mf.FillRule.EvenOdd)
    parts.append(mf.Manifold.extrude(cs, z1 - z0).translate((0, 0, z0)))
solid = mf.Manifold.batch_boolean(parts, mf.OpType.Add)
mesh = solid.to_mesh()
V = np.asarray(mesh.vert_properties)[:, :3]
F = np.asarray(mesh.tri_verts)
print("result: verts", len(V), "tris", len(F), "volume mm3", round(solid.volume(), 1), "genus", solid.genus(),
      "components", len(solid.decompose()))
np.savez(out_path, V=V, F=F)

if len(sys.argv) > 3:
    import json
    json.dump(regions, open(sys.argv[3], "w"))
