"""Snapshot the live scene before a non-destructive material/lighting pass. Run via MCP."""
import bpy
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
import numpy as np

s = bpy.context.scene
assert s.name == 'ZERO_FRAME_Parking_FULL_REWORK', 'Unexpected active scene'
assert not bpy.app.is_job_running('RENDER'), 'Do not interrupt an active render'
work = Path('/home/tuxpc/game/ZERO_FRAME_backups') / ('parking_finish_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(exist_ok=False)
backup = work / 'before.blend'
bpy.data.libraries.write(str(backup), {s}, path_remap='ABSOLUTE', fake_user=True)
assert backup.stat().st_size > 100000

def geometry(o):
    if o.type != 'MESH':
        return None
    co = np.empty(len(o.data.vertices) * 3, dtype=np.float32)
    indices = np.empty(len(o.data.loops), dtype=np.int32)
    o.data.vertices.foreach_get('co', co)
    o.data.loops.foreach_get('vertex_index', indices)
    return hashlib.sha256(co.tobytes() + indices.tobytes()).hexdigest()

objects = {}
usage = Counter()
for o in s.objects:
    objects[o.name] = {'type': o.type, 'matrix': [list(r) for r in o.matrix_world],
        'geometry': geometry(o), 'hide_render': o.hide_render, 'hide_get': o.hide_get(),
        'visible': o.visible_get(), 'export': o.get('game_export', True),
        'materials': [slot.material.name if slot.material else None for slot in o.material_slots],
        'godot_path': o.get('godot_path', ''), 'collections': [c.name for c in o.users_collection]}
    if o.type == 'MESH' and o.visible_get() and not o.hide_render:
        usage.update(slot.material.name for slot in o.material_slots if slot.material)
materials = []
for name, count in usage.most_common():
    m = bpy.data.materials[name]
    bs = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if m.use_nodes else None
    materials.append({'name': name, 'users': count,
        'bsdf': None if bs is None else {k: {'value': list(bs.inputs[k].default_value) if k == 'Base Color' else bs.inputs[k].default_value,
            'links': [(l.from_node.name, l.from_socket.name) for l in bs.inputs[k].links]}
            for k in ('Base Color', 'Roughness', 'Metallic', 'Normal', 'Emission Strength') if k != 'Normal'},
        'nodes': [n.type for n in m.node_tree.nodes] if m.use_nodes else [],
        'images': [{'name': n.image.name, 'path': bpy.path.abspath(n.image.filepath), 'loaded': n.image.has_data,
                    'colorspace': n.image.colorspace_settings.name, 'packed': bool(n.image.packed_file)}
                   for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image] if m.use_nodes else []})
lights = [{'name': o.name, 'type': o.data.type, 'energy': o.data.energy, 'color': list(o.data.color),
           'position': list(o.matrix_world.translation), 'visible': o.visible_get() and not o.hide_render}
          for o in s.objects if o.type == 'LIGHT']
report = {'work': str(work), 'previous_file': bpy.data.filepath, 'backup_bytes': backup.stat().st_size,
    'backup_sha256': hashlib.sha256(backup.read_bytes()).hexdigest(), 'objects': objects, 'materials': materials, 'lights': lights,
    'collections': {c.name: len(c.all_objects) for c in s.collection.children},
    'cameras': [{'name': o.name, 'position': list(o.matrix_world.translation)} for o in s.objects if o.type == 'CAMERA'],
    'render': {'engine': s.render.engine, 'exposure': s.view_settings.exposure, 'world': s.world.name if s.world else None}}
(work / 'baseline.json').write_text(json.dumps(report, indent=2))
s['photoreal_finish_work'] = str(work)
print('PHOTOREAL_CHECKPOINT_OK', json.dumps({k: v for k, v in report.items() if k not in ('objects', 'materials', 'lights')}))
print('MATERIAL_AUDIT', json.dumps(materials))
print('LIGHT_AUDIT', json.dumps(lights))
