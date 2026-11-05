import bpy, sys, json
from mathutils import Vector
argv = sys.argv[sys.argv.index("--")+1:]
items, out, views = json.loads(argv[0]), argv[1], json.loads(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
for path, col in items:
    bpy.ops.wm.stl_import(filepath=path)
    bpy.context.selected_objects[0].color = col
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "OBJECT"
sh.show_cavity = True; sh.cavity_type = "BOTH"; sh.show_object_outline = True
sc.render.resolution_x, sc.render.resolution_y = 1200, 900
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.13, 0.13, 0.14)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.clip_end = 3000
for name, tgt, d, scale in views:
    d = Vector(d).normalized()
    cam.location = Vector(tgt) + d * 800
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = scale
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
