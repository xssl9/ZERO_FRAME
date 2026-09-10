import bpy
import json
from mathutils import Vector
from pathlib import Path
scene = bpy.data.scenes['ZERO_FRAME_Parking_FULL_REWORK']
manifest = json.loads(Path('/home/tuxpc/game/ZERO_FRAME_backups/parking_full_rework_20260908/manifest.json').read_text())
records = {r['name']: r for r in manifest['meshes']}
report = []
for obj in scene.objects:
    if obj.type != 'MESH' or not obj.get('godot_path','').startswith('Garage/'):
        continue
    coords = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mats = []
    for mat in obj.data.materials:
        bs = next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if mat and mat.use_nodes else None
        mats.append({'name':mat.name,'parameters':json.loads(mat.get('godot_material_parameters','{}')),
                     'color':list(bs.inputs['Base Color'].default_value) if bs else None,
                     'emission':bs.inputs['Emission Strength'].default_value if bs else None})
    report.append({'name':obj.name,'world_min':[min(v[i] for v in coords) for i in range(3)],
                   'world_max':[max(v[i] for v in coords) for i in range(3)],
                   'matrix':[list(row) for row in obj.matrix_world],
                   'manifest_bounds': [records[obj['transfer_id']]['bounds_low'],records[obj['transfer_id']]['bounds_high']],
                   'materials':mats})
print('PARKING_SURFACE_AUDIT',json.dumps(report))
