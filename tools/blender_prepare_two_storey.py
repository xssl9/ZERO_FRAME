"""Snapshot the live parking scene and audit measured world-space geometry via MCP."""
import bpy
import json
from pathlib import Path
from datetime import datetime, timezone
from mathutils import Vector
from collections import Counter

scene = bpy.context.scene
assert scene.name == 'ZERO_FRAME_Parking_FULL_REWORK', scene.name
assert not scene.get('two_storey_work'), 'Already prepared; inspect rather than repeating'
work = Path('/home/tuxpc/game/ZERO_FRAME_backups') / ('parking_two_storey_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(parents=True, exist_ok=False)
reference = Path('/home/tuxpc/Загрузки/ChatGPT Image 8 сент. 2026 г., 21_38_24.png')
assert reference.is_file()
bpy.data.libraries.write(str(work/'before.blend'), {scene}, path_remap='ABSOLUTE', fake_user=True)
assert (work/'before.blend').stat().st_size > 100000

def bounds(o):
    points = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return [[round(f(p[i] for p in points),4) for i in range(3)] for f in (min,max)]

def components(o):
    parent = list(range(len(o.data.vertices)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in o.data.edges:
        a,b = e.vertices
        parent[root(a)] = root(b)
    same = {}
    for v in o.data.vertices:
        key = tuple(round(x,5) for x in v.co)
        if key in same: parent[root(v.index)] = root(same[key])
        else: same[key] = v.index
    groups = {}
    for v in o.data.vertices: groups.setdefault(root(v.index),[]).append(o.matrix_world @ v.co)
    return [{'bounds':[[round(f(p[i] for p in pts),4) for i in range(3)] for f in (min,max)],'verts':len(pts)} for pts in groups.values()]

report = {'work':str(work),'original_filepath':bpy.data.filepath,'scene':scene.name,'objects':len(scene.objects),
          'reference':str(reference),'reference_visually_reviewed':False,'structures':[], 'lights':[], 'cameras':[],
          'collections':[{ 'name':c.name,'objects':len(c.all_objects)} for c in scene.collection.children],
          'groups':dict(Counter(o.get('godot_path','').split('/')[0] for o in scene.objects if o.type=='MESH')),
          'render':{'engine':scene.render.engine,'resolution':[scene.render.resolution_x,scene.render.resolution_y],
                    'percentage':scene.render.resolution_percentage,'exposure':scene.view_settings.exposure,'world':scene.world.name if scene.world else None}}
for o in scene.objects:
    path = o.get('godot_path','')
    if o.type == 'MESH' and path.startswith('Garage/'):
        report['structures'].append({'name':o.name,'path':path,'bounds':bounds(o),'polygons':len(o.data.polygons),
             'components':components(o),'materials':[m.name if m else None for m in o.data.materials]})
    elif o.type == 'LIGHT':
        report['lights'].append({'name':o.name,'type':o.data.type,'energy':o.data.energy,'color':list(o.data.color),'matrix':[list(row) for row in o.matrix_world]})
    elif o.type == 'CAMERA':
        report['cameras'].append({'name':o.name,'location':list(o.matrix_world.translation),'lens':o.data.lens,'active':o==scene.camera})
report['floor_materials'] = []
for o in scene.objects:
    if o.get('godot_path','') in ('Garage/Floor_Parking','Garage/Ceiling','Garage/Walls_Concrete','Garage/Pillars','Garage/Markings'):
        for m in o.data.materials:
            if m and m.use_nodes:
                report['floor_materials'].append({'object':o.name,'material':m.name,
                    'nodes':[{'name':n.name,'type':n.type,'image':bpy.path.abspath(n.image.filepath) if n.type=='TEX_IMAGE' and n.image else None} for n in m.node_tree.nodes],
                    'links':[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]})
(work/'baseline.json').write_text(json.dumps(report,indent=2))
scene['two_storey_work'] = str(work)
scene['reference_image'] = str(reference)
scene['reference_visually_reviewed'] = False
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
print('TWO_STOREY_PREPARED',json.dumps(report))
