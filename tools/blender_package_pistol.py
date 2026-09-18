"""Package the isolated scene library as an editable .blend without touching live Blender.

blender --background --factory-startup --python-exit-code 1 --python tools/blender_package_pistol.py
"""
import bpy
from pathlib import Path

assert bpy.app.background, 'Use a separate factory-startup background process'
ROOT = Path(__file__).resolve().parents[1]
library = ROOT / 'build/pistol_uniform/pistol_uniform_library.blend'
with bpy.data.libraries.load(str(library), link=False) as (source, target):
    assert source.scenes == ['PistolUniform'], source.scenes
    target.scenes = source.scenes
scene = target.scenes[0]
bpy.context.window.scene = scene
# Only the factory-startup scene is removed in this isolated background process.
for other in list(bpy.data.scenes):
    if other != scene:
        bpy.data.scenes.remove(other)
scene.frame_set(0)
scene.render.fps = 24
arms = scene.objects['Object_9']
for obj in scene.objects:
    obj.select_set(obj.type == 'MESH' and obj.name != 'Icosphere')
bpy.context.view_layer.objects.active = arms
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        area.spaces.active.shading.type = 'MATERIAL'
        with bpy.context.temp_override(area=area, region=next(r for r in area.regions if r.type == 'WINDOW')):
            bpy.ops.view3d.view_selected()
# Material previews should resolve both new external and original packed images.
for image in bpy.data.images:
    if image.filepath and not image.packed_file:
        image.reload()
bpy.context.preferences.filepaths.save_version = 0
path = ROOT / 'assets/weapons/pistol/uniform/pistol_uniform.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
print('PISTOL_BLEND_PACKAGED', path)
