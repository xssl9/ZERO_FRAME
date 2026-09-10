"""Export the visible live parking through MCP without modifying the authoring scene.
Evaluated, triangulated temporary meshes preserve modifiers and curve geometry.
Lights are recorded separately: glTF cannot represent Blender area lights.
"""
import bpy
import bmesh
import contextlib
import datetime
import hashlib
import io
import json
from pathlib import Path
from mathutils import Matrix, Vector

source = bpy.context.scene
assert source.name == 'ZERO_FRAME_Parking_FULL_REWORK', source.name
out = Path('/home/tuxpc/game/ZERO_FRAME/assets/environment/parking_rework')
conversion = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
visible = [o for o in source.objects if o.visible_get() and not o.hide_render]
report = {'scene': source.name, 'blend': bpy.data.filepath, 'unsaved_changes': bpy.data.is_dirty,
          'exported_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'excluded': [o.name for o in source.objects if o not in visible], 'meshes': [], 'lights': [],
          'light_conversion': 'Area lights require an approximate Godot lighting pass; not included in GLB.'}
for o in visible:
    if o.type != 'LIGHT' or o.data.energy <= 0:
        continue
    matrix = conversion @ o.matrix_world
    report['lights'].append({'name': o.name, 'type': o.data.type, 'energy_watts': o.data.energy,
                             'color': list(o.data.color), 'transform': [matrix[r][c] for c in range(4) for r in range(3)],
                             'size': getattr(o.data, 'size', 0.0)})

def solid(o):
    n = o.name
    path = o.get('godot_path', '')
    # Decorations and overhead services deliberately have no physics shape.
    return (n.startswith(('ZF_0000_', 'ZF_0001_', 'ZF_0003_', 'ZF_0004_', 'ZF_0006_', 'ZF_0007_',
                          'L02_RoofAndBeams', 'L02_AlignedWallsAndColumns', 'L02_EastPerimeterClosure',
                          'L02_NorthEntranceClosure', 'L02_InterstoreySlab', 'L02_EasedVehicleRamp',
                          'L02_RampParapet', 'L02_RampEndBarrier', 'L02_RampPier', 'L02_RampFoundation',
                          'GP_FenceSection_', 'ZONE_'))
            or path.startswith(('Cars/', 'Props/'))
            or ('covered_car' in n and n.startswith('L02_')))

temporary = bpy.data.scenes.new('ParkingExportTemporary')
created_objects, created_meshes = [], []
log = io.StringIO()
try:
    deps = bpy.context.evaluated_depsgraph_get()
    for original in visible:
        if original.type not in {'MESH', 'CURVE'}:
            continue
        evaluated = original.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
        created_meshes.append(mesh)
        repaired = mesh.validate(verbose=False)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(original.name + '_export', mesh)
        created_objects.append(obj)
        temporary.collection.objects.link(obj)
        obj.matrix_world = original.matrix_world.copy()
        # glTF names are patched back after export; do not rename live authoring objects.
        corners = [conversion @ (obj.matrix_world @ Vector(v)) for v in obj.bound_box]
        report['meshes'].append({'name': original.name, 'export_name': obj.name, 'solid': solid(original),
                                 'bounds_min': [min(v[i] for v in corners) for i in range(3)],
                                 'bounds_max': [max(v[i] for v in corners) for i in range(3)],
                                 'triangles': len(mesh.polygons), 'validated_copy': repaired,
                                 'materials': [m.name if m else None for m in mesh.materials]})
    bpy.context.window.scene = temporary
    with contextlib.redirect_stdout(log):
        result = bpy.ops.export_scene.gltf(filepath=str(out / 'assembly.glb'), export_format='GLB',
                                          use_active_scene=True, export_apply=False, export_yup=True,
                                          export_materials='EXPORT', export_texcoords=True, export_normals=True,
                                          export_tangents=True, export_cameras=False, export_lights=False,
                                          export_animations=False)
    assert result == {'FINISHED'}, result
finally:
    bpy.context.window.scene = source
    for o in created_objects:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(temporary)
    for mesh in created_meshes:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

# Only change glTF node names, never geometry, transforms, or material data.
import struct
path = out / 'assembly.glb'
raw = path.read_bytes()
length, kind = struct.unpack_from('<II', raw, 12)
assert kind == 0x4E4F534A
asset = json.loads(raw[20:20 + length])
names = {m['export_name']: m['name'] for m in report['meshes']}
for node in asset['nodes']:
    if node.get('name') in names:
        node['name'] = names[node['name']]
encoded = json.dumps(asset, separators=(',', ':')).encode()
encoded += b' ' * (-len(encoded) % 4)
rest = raw[20 + length:]
path.write_bytes(struct.pack('<III', 0x46546C67, 2, 20 + len(encoded) + len(rest)) +
                 struct.pack('<II', len(encoded), kind) + encoded + rest)
report['glb_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
report['warnings'] = [line for line in log.getvalue().splitlines() if 'WARNING' in line or 'Warning' in line]
(out / 'live_export.json').write_text(json.dumps(report, indent=2))
(out / 'live_export.log').write_text(log.getvalue())
print('LIVE_PARKING_EXPORTED', json.dumps({'meshes': len(report['meshes']), 'lights': len(report['lights']),
                                         'excluded': report['excluded'], 'warnings': len(report['warnings']),
                                         'triangles': sum(m['triangles'] for m in report['meshes']),
                                         'sha256': report['glb_sha256']}))
