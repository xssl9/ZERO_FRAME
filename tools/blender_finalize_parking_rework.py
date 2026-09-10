"""Re-export only the active rework collection, validate GLB, save full authoring copy.
Run in Blender through the local MCP runner; does not replace the original level.
"""
import bpy
import json
import struct
from pathlib import Path

ROOT = Path('/home/tuxpc/game/ZERO_FRAME')
WORK = ROOT.parent / 'ZERO_FRAME_backups/parking_full_rework_20260908'
OUT = ROOT / 'assets/environment/parking_rework'
scene = bpy.data.scenes['ZERO_FRAME_Parking_FULL_REWORK']
assert scene['phase'] == 'ARCHITECTURAL_SERVICE_WEAR_PASS_NOT_VISUALLY_APPROVED'
bpy.context.window.scene = scene
collection = next(c for c in scene.collection.children if c.name.startswith('ENV_REWORK_ARCHITECTURE_AND_WEAR'))
objects = list(collection.all_objects)
assert len(objects)==86 and all(o.type=='MESH' and o.name.startswith('RW_') for o in objects)
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
path = OUT/'architectural_rework.glb'
assert 'FINISHED' in bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',
    use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',
    export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
raw = path.read_bytes()
length = struct.unpack_from('<I',raw,12)[0]
gltf = json.loads(raw[20:20+length])
assert len(gltf['scenes'])==1 and len(gltf['meshes'])==86
assert all(n['name'].startswith('RW_') for n in gltf['nodes'] if 'mesh' in n)
assert all(s.get('wrapS',10497)==10497 and s.get('wrapT',10497)==10497 for s in gltf.get('samplers',[]))
source_objects = [o for o in scene.objects if o.get('transfer_id')]
assert len(source_objects)==601
for mat in bpy.data.materials:
    if mat.name.startswith('RW_') and mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE':
                assert node.image is not None and node.image.has_data
bpy.ops.object.select_all(action='DESELECT')
# Prefer the existing GPU, without downloading or installing anything.
device = 'CPU'
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    devices = [d for d in prefs.devices if d.type=='OPTIX']
    if devices:
        for d in prefs.devices:
            d.use = d.type=='OPTIX'
        scene.cycles.device = 'GPU'
        device = ', '.join(d.name for d in devices)
except Exception as error:
    print('CYCLES_GPU_UNAVAILABLE',type(error).__name__,str(error),'using CPU')
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.cycles.use_preview_denoising = True
scene.render.filepath = str(WORK/'parking_rework_preview.png')
bpy.data.libraries.write(str(WORK/'parking_complete_reworked.blend'),{scene},path_remap='ABSOLUTE',fake_user=True)
print('PARKING_FINAL_EXPORT_VALIDATED',json.dumps({'scenes':1,'new_meshes':86,'source_meshes':601,'render_device':device}))
assert 'FINISHED' in bpy.ops.render.render(write_still=True)
assert Path(scene.render.filepath).is_file()
print('PARKING_CYCLES_PREVIEW_SAVED',scene.render.filepath)
