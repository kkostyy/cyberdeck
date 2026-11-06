"""Write a closed STL mesh to .skp via SketchUp 2017 C API (ctypes).

Coplanar triangles are merged into real SketchUp faces (with holes), straight-line
vertices are dropped, edges between faces < SOFT_DEG apart (hole walls, rounded
corners) are made soft + smooth. A new model is created; if a template .skp is given,
its units settings and camera view are copied in (its geometry is not used).

Usage: skp_write.py mesh.stl out.skp [template.skp]
       skp_write.py a.stl,b.stl#6b1a1f,... out.skp [template.skp]
         several meshes: each goes into its own group named after the file,
         "#RRGGBB" after a path paints that group
"""
import collections
import ctypes as C
import os
import sys

import numpy as np
import shapely
import trimesh
from shapely.geometry import Polygon

SU_DIR = r"C:\Program Files\SketchUp\SketchUp 2017"
os.add_dll_directory(SU_DIR)
api = C.CDLL(os.path.join(SU_DIR, "SketchUpAPI.dll"))
Ref = C.c_void_p
SOFT_DEG = 35.0
FLAT_DEG, FLAT_TOL = 0.5, 0.01      # triangles join one face within this angle / distance (mm)
WELD = 0.03                         # mm; SketchUp merges points closer than 0.001" (0.0254 mm)
STRAIGHT_TOL = 0.005                # mm; vertices this close to a straight edge are dropped
UNITS = ["inches", "feet", "mm", "cm", "m"]


class Point3D(C.Structure):
    _fields_ = [("x", C.c_double), ("y", C.c_double), ("z", C.c_double)]


def ok(res, what):
    if res != 0:
        raise RuntimeError(f"{what} failed: SUResult={res}")


def weld(V, F, tol=1e-3):
    """Merge vertices closer than tol (mm); returns remapped faces."""
    parent = list(range(len(V)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    cells = collections.defaultdict(list)
    for i, v in enumerate(V):
        key = np.floor(v / tol).astype(int)
        for off in np.ndindex(3, 3, 3):
            for j in cells.get(tuple(key + np.array(off) - 1), ()):
                if np.linalg.norm(V[j] - v) < tol:
                    parent[root(i)] = root(j)
        cells[tuple(key)].append(i)
    return np.array([[root(i) for i in f] for f in F])


def split_caps(V, F, eps=1e-9):
    """Remove zero-area 'cap' triangles (a vertex lying on the opposite edge, which manifold
    keeps on seams) by splitting the neighbour across that edge at the vertex; stays closed."""
    F = [list(f) for f in F]
    for _ in range(1000):
        T = V[np.array(F)]
        area = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1) / 2
        caps = np.where(area < eps)[0]
        if not len(caps):
            break
        i = int(caps[0]); f = F[i]
        k = max(range(3), key=lambda k: np.linalg.norm(V[f[(k + 1) % 3]] - V[f[(k + 2) % 3]]))
        c, a, b = f[k], f[(k + 1) % 3], f[(k + 2) % 3]          # cap edges c->a, a->b (long), b->c
        hit = [(j, t) for j, g in enumerate(F) if j != i for t in range(3) if g[t] == b and g[(t + 1) % 3] == a]
        if not hit:
            raise RuntimeError(f"cap triangle {np.round(V[f], 4).tolist()} has no neighbour")
        j, t = hit[0]
        d = F[j][(t + 2) % 3]
        F[j] = [b, c, d]
        F.append([c, a, d])
        del F[i]
    return np.array(F)


def faces_from_mesh(path):
    """-> vertices (mm), list of (normal, [outer loop, inner loops...]) as vertex indices."""
    m = trimesh.load(path, process=True)
    F = weld(m.vertices, m.faces, WELD)                    # SketchUp would merge these itself and drop faces
    F = split_caps(m.vertices, F[(F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])])
    m = trimesh.Trimesh(m.vertices, F, process=False)
    m.remove_unreferenced_vertices()
    print(f"mesh: {len(m.faces)} triangles, watertight {m.is_watertight}")
    V, F, N = m.vertices, m.faces, m.face_normals
    tri_edges = lambda f: ((f[0], f[1]), (f[1], f[2]), (f[2], f[0]))
    edge_tris = collections.defaultdict(list)
    for t, f in enumerate(F):
        for a, b in tri_edges(f):
            edge_tris[frozenset((a, b))].append(t)
    # grow faces from the biggest triangles over shared edges while the neighbour stays
    # in the seed's plane (rebuilt SketchUp geometry is flat only to ~0.01 mm)
    cos_tol = np.cos(np.radians(FLAT_DEG))
    taken = np.zeros(len(F), bool)
    faces = []
    for seed in np.argsort(-m.area_faces):
        if taken[seed]:
            continue
        n0, d0 = N[seed], N[seed] @ V[F[seed, 0]]
        taken[seed], stack, tris = True, [seed], [seed]
        while stack:
            for a, b in tri_edges(F[stack.pop()]):
                for nb in edge_tris[frozenset((a, b))]:
                    if not taken[nb] and N[nb] @ n0 > cos_tol and np.all(np.abs(V[F[nb]] @ n0 - d0) < FLAT_TOL):
                        taken[nb] = True
                        stack.append(nb)
                        tris.append(nb)
        n = (N[tris] * m.area_faces[tris, None]).sum(0); n /= np.linalg.norm(n)
        u = np.cross(n, [0, 0, 1] if abs(n[2]) < 0.9 else [1, 0, 0]); u /= np.linalg.norm(u)
        v = np.cross(n, u)
        # boundary = edges used once inside the face, kept in triangle winding (CCW around n)
        cnt = collections.Counter(frozenset(e) for t in tris for e in tri_edges(F[t]))
        nxt = collections.defaultdict(list)
        for t in tris:
            for a, b in tri_edges(F[t]):
                if cnt[frozenset((a, b))] == 1:
                    nxt[a].append(b)
        loops = []
        while any(nxt.values()):
            start = next(a for a, bs in nxt.items() if bs)
            loop, prev, cur = [start], None, start
            while True:
                bs = nxt[cur]
                if len(bs) > 1 and prev is not None:       # pinch vertex: hug the face (sharpest left turn)
                    di = (V[cur] - V[prev]) @ np.c_[u, v]
                    do = [(V[b] - V[cur]) @ np.c_[u, v] for b in bs]
                    turn = [np.arctan2(di[0] * d[1] - di[1] * d[0], di @ d) for d in do]
                    bs[:] = [bs[i] for i in np.argsort(turn)[::-1]]
                prev, cur = cur, bs.pop(0)
                if cur == start:
                    break
                loop.append(cur)
            if len(loop) >= 3:
                loops.append(loop)
        def area(L):                                       # signed, > 0 for CCW around n
            p = V[L] @ np.c_[u, v]
            return 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
        outers = [L for L in loops if area(L) > 0]
        holes = [L for L in loops if area(L) <= 0]
        for L in outers:
            P = Polygon(V[L] @ np.c_[u, v])
            mine = [H for H in holes if len(outers) == 1 or P.contains(Polygon(V[H] @ np.c_[u, v]).representative_point())]
            faces.append((n, [L] + mine))
    return V, faces


def drop_straight(V, faces):
    """Remove vertices that are straight-through in every loop they appear in."""
    bent = set()
    for _, loops in faces:
        for L in loops:
            for i, a in enumerate(L):
                p, q = V[L[i - 1]] - V[a], V[L[(i + 1) % len(L)]] - V[a]
                off_line = np.linalg.norm(np.cross(p, q)) / np.linalg.norm(p - q)   # distance from the chord
                if off_line > STRAIGHT_TOL or p @ q > 0:
                    bent.add(a)
    return [(n, [[a for a in L if a in bent] for L in loops]) for n, loops in faces]


def prepare(path):
    """-> vertices, faces, soft edges for one mesh."""
    V, faces = faces_from_mesh(path)
    faces = drop_straight(V, faces)
    edge_normals = collections.defaultdict(list)
    for n, loops in faces:
        for L in loops:
            for i in range(len(L)):
                edge_normals[frozenset((L[i], L[(i + 1) % len(L)]))].append(n)
    soft = {e for e, ns in edge_normals.items()
            if len(ns) == 2 and np.degrees(np.arccos(np.clip(np.dot(*ns), -1, 1))) < SOFT_DEG}
    bad = [e for e, ns in edge_normals.items() if len(ns) != 2]
    lens = [np.linalg.norm(V[a] - V[b]) for a, b in map(tuple, edge_normals)]
    print(f"faces {len(faces)} edges {len(edge_normals)} soft {len(soft)} unpaired {len(bad)} "
          f"shortest edge {min(lens):.3f} mm")
    return V, faces, soft


def fill(ents, V, faces, soft):
    geom = Ref()
    ok(api.SUGeometryInputCreate(C.byref(geom)), "SUGeometryInputCreate")
    for p in V / 25.4:                                     # mm -> SketchUp inches
        ok(api.SUGeometryInputAddVertex(geom, C.byref(Point3D(*p))), "AddVertex")
    for n, loops in faces:
        face_idx = C.c_size_t()
        for k, L in enumerate(loops):
            loop = Ref()
            ok(api.SULoopInputCreate(C.byref(loop)), "SULoopInputCreate")
            for i, a in enumerate(L):
                ok(api.SULoopInputAddVertexIndex(loop, C.c_size_t(int(a))), "AddVertexIndex")
            for i, a in enumerate(L):
                if frozenset((a, L[(i + 1) % len(L)])) in soft:
                    ok(api.SULoopInputEdgeSetSoft(loop, C.c_size_t(i), C.c_bool(True)), "EdgeSetSoft")
                    ok(api.SULoopInputEdgeSetSmooth(loop, C.c_size_t(i), C.c_bool(True)), "EdgeSetSmooth")
            if k == 0:
                ok(api.SUGeometryInputAddFace(geom, C.byref(loop), C.byref(face_idx)), "AddFace")
            else:
                ok(api.SUGeometryInputFaceAddInnerLoop(geom, face_idx, C.byref(loop)), "FaceAddInnerLoop")
    ok(api.SUEntitiesFill(ents, geom, C.c_bool(True)), "SUEntitiesFill")
    api.SUGeometryInputRelease(C.byref(geom))
    nf, ne = C.c_size_t(), C.c_size_t()
    api.SUEntitiesGetNumFaces(ents, C.byref(nf)); api.SUEntitiesGetNumEdges(ents, C.c_bool(False), C.byref(ne))
    print(f"  -> faces {nf.value} edges {ne.value}")


class Color(C.Structure):
    _fields_ = [("red", C.c_ubyte), ("green", C.c_ubyte), ("blue", C.c_ubyte), ("alpha", C.c_ubyte)]


def units_provider(m):
    om, prov = Ref(), Ref()
    ok(api.SUModelGetOptionsManager(m, C.byref(om)), "GetOptionsManager")
    ok(api.SUOptionsManagerGetOptionsProviderByName(om, b"UnitsOptions", C.byref(prov)), "GetOptionsProvider")
    return prov


def copy_settings(src_model, dst_model):
    """Units options and camera view from the template (SUEntitiesErase hangs on dirty models,
    so the template itself is not reused)."""
    sp, dp = units_provider(src_model), units_provider(dst_model)
    copied = []
    for key in [b"LengthFormat", b"LengthUnit", b"LengthPrecision", b"AnglePrecision", b"LengthSnapEnabled",
                b"LengthSnapLength", b"AngleSnapEnabled", b"SnapAngle", b"SuppressUnitsDisplay", b"ForceInchDisplay"]:
        tv = Ref()
        api.SUTypedValueCreate(C.byref(tv))
        if api.SUOptionsProviderGetValue(sp, key, C.byref(tv)) == 0 and api.SUOptionsProviderSetValue(dp, key, tv) == 0:
            copied.append(key.decode())
        api.SUTypedValueRelease(C.byref(tv))
    sc, dc = Ref(), Ref()
    ok(api.SUModelGetCamera(src_model, C.byref(sc)), "GetCamera")
    ok(api.SUModelGetCamera(dst_model, C.byref(dc)), "GetCamera")
    eye, tgt, up = Point3D(), Point3D(), Point3D()
    ok(api.SUCameraGetOrientation(sc, C.byref(eye), C.byref(tgt), C.byref(up)), "GetOrientation")
    ok(api.SUCameraSetOrientation(dc, C.byref(eye), C.byref(tgt), C.byref(up)), "SetOrientation")
    persp, val = C.c_bool(), C.c_double()
    ok(api.SUCameraGetPerspective(sc, C.byref(persp)), "GetPerspective")
    ok(api.SUCameraSetPerspective(dc, persp), "SetPerspective")
    if persp.value:
        if api.SUCameraGetPerspectiveFrustumFOV(sc, C.byref(val)) == 0:
            api.SUCameraSetPerspectiveFrustumFOV(dc, val)
    elif api.SUCameraGetOrthographicFrustumHeight(sc, C.byref(val)) == 0:
        api.SUCameraSetOrthographicFrustumHeight(dc, val)
    print("from template:", ", ".join(copied), "+ camera")


out = sys.argv[2]
template = sys.argv[3] if len(sys.argv) > 3 else None
api.SUGroupToDrawingElement.restype = Ref
api.SUInitialize()
model = Ref()
ok(api.SUModelCreate(C.byref(model)), "SUModelCreate")
if template:
    tmpl = Ref()
    ok(api.SUModelCreateFromFile(C.byref(tmpl), template.encode("utf-8")), "SUModelCreateFromFile")
    copy_settings(tmpl, model)
    api.SUModelRelease(C.byref(tmpl))
else:
    for key, val in [(b"LengthFormat", 0), (b"LengthUnit", 2)]:             # decimal, mm
        tv = Ref()
        api.SUTypedValueCreate(C.byref(tv)); api.SUTypedValueSetInt32(tv, val)
        ok(api.SUOptionsProviderSetValue(units_provider(model), key, tv), "SetValue")
        api.SUTypedValueRelease(C.byref(tv))
units = C.c_int()
ok(api.SUModelGetUnits(model, C.byref(units)), "SUModelGetUnits")
print("model units", UNITS[units.value] if 0 <= units.value < 5 else units.value)
ents = Ref()
ok(api.SUModelGetEntities(model, C.byref(ents)), "SUModelGetEntities")

def new_group(parent_ents, name):
    group, gents = Ref(), Ref()
    ok(api.SUGroupCreate(C.byref(group)), "SUGroupCreate")
    ok(api.SUEntitiesAddGroup(parent_ents, group), "SUEntitiesAddGroup")
    ok(api.SUGroupSetName(group, name.encode("utf-8")), "SUGroupSetName")
    ok(api.SUGroupGetEntities(group, C.byref(gents)), "SUGroupGetEntities")
    return group, gents


materials, parents = {}, {}
parts = sys.argv[1].split(",")                             # several meshes -> one group each
for spec in parts:
    path, _, color = spec.partition("#")
    print(os.path.basename(path))
    V, faces, soft = prepare(path)
    if len(parts) == 1:
        fill(ents, V, faces, soft)
        continue
    # "Device - part.stl" -> group "part" inside group "Device" (one parent per device)
    stem = os.path.splitext(os.path.basename(path))[0]
    parent, sep, name = stem.partition(" - ")
    where = ents
    if sep:
        if parent not in parents:
            parents[parent] = new_group(ents, parent)[1]
        where = parents[parent]
    else:
        name = stem
    group, gents = new_group(where, name)
    fill(gents, V, faces, soft)
    if color:
        if color not in materials:
            mat = Ref()
            ok(api.SUMaterialCreate(C.byref(mat)), "SUMaterialCreate")
            ok(api.SUMaterialSetName(mat, ("#" + color).encode()), "SUMaterialSetName")
            rgb = [int(color[i:i + 2], 16) for i in (0, 2, 4)]
            ok(api.SUMaterialSetColor(mat, C.byref(Color(*rgb, 255))), "SUMaterialSetColor")
            ok(api.SUModelAddMaterials(model, C.c_size_t(1), C.byref(mat)), "SUModelAddMaterials")
            materials[color] = mat
        ok(api.SUDrawingElementSetMaterial(Ref(api.SUGroupToDrawingElement(group)), materials[color]), "SetMaterial")
ok(api.SUModelSaveToFile(model, out.encode("utf-8")), "SUModelSaveToFile")
api.SUModelRelease(C.byref(model))
api.SUTerminate()
print("saved", out)
