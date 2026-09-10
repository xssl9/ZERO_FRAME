"""Independent real-scene assertions for the MCP material pass, including ramp rays."""
import bpy, json, hashlib, math
import numpy as np
from pathlib import Path
from mathutils import Vector

s = bpy.context.scene
work = Path(s['photoreal_finish_work'])
baseline = json.loads((work / 'baseline.json').read_text())
finish = json.loads((work / 'finish_report.json').read_text())
assert s.get('photoreal_finish_applied')
assert set(s.objects.keys()) == set(baseline['objects']), 'No missing or added scene objects'
checks = 0

def check(value, label):
    global checks
    assert value, label
    checks += 1

def geometry(o):
    co = np.empty(len(o.data.vertices) * 3, dtype=np.float32)
    indices = np.empty(len(o.data.loops), dtype=np.int32)
    o.data.vertices.foreach_get('co', co)
    o.data.loops.foreach_get('vertex_index', indices)
    return hashlib.sha256(co.tobytes() + indices.tobytes()).hexdigest()

changed = set(finish['objects'])
for name, old in baseline['objects'].items():
    ob = s.objects[name]
    check([list(r) for r in ob.matrix_world] == old['matrix'], 'transform preserved:' + name)
    check(ob.hide_render == old['hide_render'] and ob.hide_get() == old['hide_get'], 'visibility:' + name)
    check([c.name for c in ob.users_collection] == old['collections'], 'collections:' + name)
    if ob.type == 'MESH':
        check(geometry(ob) == old['geometry'], 'original geometry:' + name)
    slots = [slot.material.name if slot.material else None for slot in ob.material_slots]
    if name not in changed:
        check(slots == old['materials'], 'protected material assignment:' + name)
    else:
        uv = ob.data.uv_layers.get('PF_MetricSurface')
        check(uv is not None and len(uv.data) == len(ob.data.loops), 'metric UV coverage:' + name)
        check(all(math.isfinite(c) for item in uv.data for c in item.uv), 'finite UV:' + name)
        ob.data.calc_loop_triangles()
        for tri in ob.data.loop_triangles:
            if tri.area < 1e-10: continue
            a, b, c = [uv.data[i].uv for i in tri.loops]
            det = (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
            check(abs(det) > 1e-12, 'nondegenerate tangent UV:' + name)
        for slot, old_name in zip(ob.material_slots, old['materials']):
            mat = slot.material
            check((mat is None and old_name is None) or (mat is not None and (mat.name == old_name or mat.get('photoreal_finish_source') == old_name)), 'correct material source:' + name)

for record in finish['materials']:
    mat = bpy.data.materials[record['material']]
    nodes = mat.node_tree.nodes
    bs = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    maps = [n for n in nodes if n.type == 'NORMAL_MAP' and n.name.startswith('PF_Normal_')]
    check(len(maps) == record['normal_maps'], 'normal map count:' + mat.name)
    for node in maps:
        tex = node.inputs['Color'].links[0].from_node
        check(node.space == 'TANGENT' and node.uv_map == 'PF_MetricSurface', 'normal space:' + mat.name)
        check(tex.image.has_data and tex.image.colorspace_settings.name == 'Non-Color', 'normal decoded as data:' + mat.name)
        check(bool(tex.image.packed_file), 'normal included in blend:' + mat.name)
    check(bs.inputs['Metallic'].default_value == 0 and not bs.inputs['Metallic'].is_linked, 'dielectric structure:' + mat.name)
    check(bs.inputs['Normal'].is_linked and bs.inputs['Roughness'].is_linked, 'complete PBR:' + mat.name)
    if len(maps) == 2:
        normal_mask = nodes['PF_PatchNormals'].inputs[0].links[0].from_socket
        rough_mask = nodes['PF_PatchRoughness'].inputs[0].links[0].from_socket
        check(normal_mask == rough_mask, 'shared patch mask:' + mat.name)

light_changes = {r['name']: r for r in finish['lights']}
for old in baseline['lights']:
    ob = s.objects[old['name']]
    record = light_changes.get(ob.name)
    if record:
        check(ob.data.energy == record['after_energy'] and list(ob.data.color) == record['after_color'], 'light readback:' + ob.name)
        check(0.93 <= ob.data.energy / old['energy'] <= 1.07, 'bounded lamp variation:' + ob.name)
    else:
        check(ob.data.energy == old['energy'] and list(ob.data.color) == old['color'], 'other lights preserved:' + ob.name)
check(s.view_settings.exposure == baseline['render']['exposure'], 'no exposure cheat')
check(s.world.name == baseline['render']['world'], 'original world retained')

# Evaluate real mesh rays, not just counts. Nothing was remeshed but these verify
# the ramp surface and upper floor are still present at the expected world heights.
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
for name, samples in [('L02_EasedVehicleRamp', [(-33.5, -15, 0), (-33.5, 0, 1.7), (-33.5, 15, 3.4)]),
                      ('L02_InterstoreySlab', [(4, 5, 3.4), (22, -13, 3.4)])]:
    ob = s.objects[name]
    inv = ob.matrix_world.inverted()
    for x, y, height in samples:
        origin = inv @ Vector((x, y, 8))
        direction = inv.to_3x3() @ Vector((0, 0, -1))
        hit, point, normal, index = ob.ray_cast(origin, direction.normalized(), distance=10*direction.length, depsgraph=dg)
        check(hit and abs((ob.matrix_world @ point).z-height) < 0.001, 'floor/ramp ray:' + str((name,x,y)))
check(hashlib.sha256((work / 'before.blend').read_bytes()).hexdigest() == baseline['backup_sha256'], 'backup unchanged')
check((work / 'parking_photoreal.blend').stat().st_size > 100000, 'new scene saved')
# Blender refuses to open its current file as a library. Read a byte-identical
# temporary copy instead, without switching/reloading the user's live scene.
import tempfile, shutil
with tempfile.TemporaryDirectory(prefix='saved_readback_', dir=work) as temporary:
    copy = Path(temporary) / 'readback.blend'
    shutil.copyfile(work / 'parking_photoreal.blend', copy)
    check(hashlib.sha256(copy.read_bytes()).digest() == hashlib.sha256((work / 'parking_photoreal.blend').read_bytes()).digest(), 'readback copy byte identical')
    with bpy.data.libraries.load(str(copy)) as (source, target):
        check(s.name in source.scenes, 'saved scene readable')
report = {'result': 'PASS', 'checks': checks, 'objects_preserved': len(s.objects),
          'architectural_objects': len(changed), 'materials': len(finish['materials']), 'lamps': len(light_changes),
          'visual_approval': 'PENDING', 'godot_integration': 'NOT_PERFORMED'}
(work / 'validation.json').write_text(json.dumps(report, indent=2))
print('PHOTOREAL_VALIDATION_PASS', json.dumps(report))
