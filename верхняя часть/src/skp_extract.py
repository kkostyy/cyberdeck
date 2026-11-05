"""Read a .skp via SketchUp 2017 C API (ctypes), dump triangles in mm to .npz."""
import ctypes as C
import os
import sys

import numpy as np

SU_DIR = r"C:\Program Files\SketchUp\SketchUp 2017"
os.add_dll_directory(SU_DIR)
api = C.CDLL(os.path.join(SU_DIR, "SketchUpAPI.dll"))

Ref = C.c_void_p  # every SU*Ref is a struct holding one pointer


class Point3D(C.Structure):
    _fields_ = [("x", C.c_double), ("y", C.c_double), ("z", C.c_double)]


class Transform(C.Structure):
    _fields_ = [("v", C.c_double * 16)]


def ok(res, what):
    if res != 0:
        raise RuntimeError(f"{what} failed: SUResult={res}")


def hidden(elem_ref):
    """Hidden flag of a drawing element (face/group/instance)."""
    b = C.c_bool()
    ok(api.SUDrawingElementGetHidden(Ref(elem_ref), C.byref(b)), "GetHidden")
    return b.value


def layer_visible(elem_ref):
    layer = Ref()
    if api.SUDrawingElementGetLayer(Ref(elem_ref), C.byref(layer)) != 0 or not layer.value:
        return True
    b = C.c_bool(True)
    if api.SULayerGetVisibility(layer, C.byref(b)) != 0:
        return True
    return b.value


def get_list(count_fn, get_fn, ents):
    n = C.c_size_t()
    ok(count_fn(ents, C.byref(n)), count_fn.__name__)
    if n.value == 0:
        return []
    arr = (Ref * n.value)()
    got = C.c_size_t()
    ok(get_fn(ents, n.value, arr, C.byref(got)), get_fn.__name__)
    return [arr[i] for i in range(got.value)]


def to_mat(t):
    return np.array(t.v, dtype=float).reshape(4, 4).T  # SU stores column-major


stats = {"faces": 0, "tris": 0, "groups": 0, "instances": 0, "skipped_hidden": 0}
tris = []


def walk(ents, xf, depth=0):
    for f in get_list(api.SUEntitiesGetNumFaces, api.SUEntitiesGetFaces, ents):
        elem = api.SUFaceToDrawingElement(Ref(f))
        if hidden(elem) or not layer_visible(elem):
            stats["skipped_hidden"] += 1
            continue
        mh = Ref()
        ok(api.SUMeshHelperCreate(C.byref(mh), Ref(f)), "SUMeshHelperCreate")
        nt, nv = C.c_size_t(), C.c_size_t()
        api.SUMeshHelperGetNumTriangles(mh, C.byref(nt))
        api.SUMeshHelperGetNumVertices(mh, C.byref(nv))
        idx = (C.c_size_t * (nt.value * 3))()
        pts = (Point3D * nv.value)()
        got = C.c_size_t()
        ok(api.SUMeshHelperGetVertexIndices(mh, nt.value * 3, idx, C.byref(got)), "GetVertexIndices")
        ok(api.SUMeshHelperGetVertices(mh, nv.value, pts, C.byref(got)), "GetVertices")
        P = np.array([[p.x, p.y, p.z, 1.0] for p in pts])
        P = (xf @ P.T).T[:, :3]
        I = np.array(idx[:], dtype=np.int64).reshape(-1, 3)
        tris.append(P[I])
        api.SUMeshHelperRelease(C.byref(mh))
        stats["faces"] += 1
        stats["tris"] += nt.value

    for g in get_list(api.SUEntitiesGetNumGroups, api.SUEntitiesGetGroups, ents):
        elem = api.SUGroupToDrawingElement(Ref(g))
        if hidden(elem) or not layer_visible(elem):
            stats["skipped_hidden"] += 1
            continue
        stats["groups"] += 1
        t = Transform()
        ok(api.SUGroupGetTransform(Ref(g), C.byref(t)), "SUGroupGetTransform")
        sub = Ref()
        ok(api.SUGroupGetEntities(Ref(g), C.byref(sub)), "SUGroupGetEntities")
        walk(sub, xf @ to_mat(t), depth + 1)

    for inst in get_list(api.SUEntitiesGetNumInstances, api.SUEntitiesGetInstances, ents):
        elem = api.SUComponentInstanceToDrawingElement(Ref(inst))
        if hidden(elem) or not layer_visible(elem):
            stats["skipped_hidden"] += 1
            continue
        stats["instances"] += 1
        t = Transform()
        ok(api.SUComponentInstanceGetTransform(Ref(inst), C.byref(t)), "GetTransform")
        d = Ref()
        ok(api.SUComponentInstanceGetDefinition(Ref(inst), C.byref(d)), "GetDefinition")
        sub = Ref()
        ok(api.SUComponentDefinitionGetEntities(d, C.byref(sub)), "DefGetEntities")
        walk(sub, xf @ to_mat(t), depth + 1)


for name in ["SUFaceToDrawingElement", "SUGroupToDrawingElement", "SUComponentInstanceToDrawingElement"]:
    getattr(api, name).restype = Ref

src, out = sys.argv[1], sys.argv[2]
api.SUInitialize()
model = Ref()
ok(api.SUModelCreateFromFile(C.byref(model), src.encode("utf-8")), "SUModelCreateFromFile")
ents = Ref()
ok(api.SUModelGetEntities(model, C.byref(ents)), "SUModelGetEntities")
walk(ents, np.eye(4))
api.SUModelRelease(C.byref(model))
api.SUTerminate()

T = np.concatenate(tris) * 25.4  # SketchUp internal units are inches -> mm
np.savez(out, tris=T)
print(stats)
print("bounds mm:", T.reshape(-1, 3).min(0).round(3), T.reshape(-1, 3).max(0).round(3))
