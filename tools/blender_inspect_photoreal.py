"""Inspect live geometry and snapshot the complete scene, without editing it."""
import bpy
import json
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone

scene = bpy.data.scenes['ZERO_FRAME_Parking_FULL_REWORK']
work = Path('/home/tuxpc/game/ZERO_FRAME_backups') / ('parking_photoreal_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(exist_ok=False)
report = {'work': str(work), 'objects': len(scene.objects), 'structures': [], 'materials': []}
for obj in scene.objects:
    if obj.type != 'MESH' or not obj.get('godot_path', '').startswith('Garage/'):
        continue
    mesh = obj.data
    parent = list(range(len(mesh.vertices)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for edge in mesh.edges:
        a,b = edge.vertices
        parent[root(a)] = root(b)
    # glTF splits vertices at normals/UV seams. Join coincident vertices for inspection only.
    same = {}
    for v in mesh.vertices:
        key = tuple(round(float(x),5) for x in v.co)
        if key in same:
            parent[root(v.index)] = root(same[key])
        else:
            same[key] = v.index
    groups = {}
    for v in mesh.vertices:
        groups.setdefault(root(v.index), []).append(obj.matrix_world @ v.co)
    components = []
    for vertices in groups.values():
        low = [min(p[i] for p in vertices) for i in range(3)]
        high = [max(p[i] for p in vertices) for i in range(3)]
        components.append({'low': low, 'high': high, 'vertices': len(vertices)})
    report['structures'].append({'path': obj['godot_path'], 'vertices': len(mesh.vertices), 'polygons':len(mesh.polygons), 'components':components})
usage = {}
for obj in scene.objects:
    if obj.type == 'MESH':
        for mat in obj.data.materials:
            if mat:
                usage.setdefault(mat, []).append(obj.get('godot_path',obj.name))
for mat, users in usage.items():
    nodes = mat.node_tree.nodes if mat.use_nodes else []
    bs = next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
    report['materials'].append({'name':mat.name, 'users':len(users), 'example':users[:3],
        'roughness':float(bs.inputs['Roughness'].default_value) if bs else None,
        'metallic':float(bs.inputs['Metallic'].default_value) if bs else None,
        'images':[{'name':n.image.name,'path':bpy.path.abspath(n.image.filepath),'loaded':n.image.has_data} for n in nodes if n.type=='TEX_IMAGE' and n.image],
        'links':[(l.from_node.type,l.from_socket.name,l.to_node.type,l.to_socket.name) for l in mat.node_tree.links] if mat.use_nodes else []})
report['mesh_groups'] = dict(Counter(o.get('godot_path','').split('/')[0] for o in scene.objects if o.get('transfer_id')))
bpy.data.libraries.write(str(work/'before.blend'), {scene}, path_remap='ABSOLUTE', fake_user=True)
(work/'inspection.json').write_text(json.dumps(report,indent=2)+'\n')
assert (work/'before.blend').stat().st_size > 100000
print('PHOTOREAL_SNAPSHOT_READY',json.dumps({'work':str(work),'objects':len(scene.objects),'mesh_groups':report['mesh_groups'],'structure_components':{x['path']:len(x['components']) for x in report['structures']}}))
