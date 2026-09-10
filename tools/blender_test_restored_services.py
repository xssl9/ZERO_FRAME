"""Live integration checks for the exact rollback and effective service surface shaders."""
import bpy,json,hashlib,math
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
s=bpy.context.scene;work=Path(s['prop_rollback_work'])
base=json.loads((work/'baseline.json').read_text());rollback=json.loads((work/'rollback_report.json').read_text());services=json.loads((work/'service_material_report.json').read_text())
service_names={r['name'] for r in services['objects']};expected=rollback['expected'];checks=0

def verify(condition,message):
 global checks
 assert condition,message
 checks+=1

def geometry(o):
 if o.type=='MESH':
  co=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',co)
  loops=np.empty(len(o.data.loops),dtype=np.int32);o.data.loops.foreach_get('vertex_index',loops)
  return hashlib.sha256(co.tobytes()+loops.tobytes()).hexdigest()
 if o.type=='CURVE':return hashlib.sha256(repr([[tuple(p.co) for p in sp.points] for sp in o.data.splines]).encode()).hexdigest()
 return None
for name,old in base['objects'].items():
 o=s.objects.get(name);verify(o is not None,'missing '+name)
 verify(geometry(o)==old['geometry'],'geometry drift '+name)
 matrix=expected[name]['matrix'] if name in expected else old['matrix']
 verify(max(abs(o.matrix_world[i][j]-matrix[i][j]) for i in range(4) for j in range(4))<1e-5,'transform drift '+name)
 if name in expected:
  verify(o.visible_get() and not o.hide_render,'hidden restored prop '+name)
  verify(sorted(c.name for c in o.users_collection)==[expected[name]['group']],'wrong prop collection '+name)
 else:verify(o.hide_render==old['hide_render'] and o.hide_get()==old['hide_set'],'visibility drift '+name)
 if name not in service_names:
  verify([slot.material.name if slot.material else None for slot in o.material_slots]==old['materials'],'unrelated material changed '+name)
 if o.type=='LIGHT':
  verify({'energy':o.data.energy,'color':list(o.data.color)}==old['light'],'lighting drift '+name)
for name in service_names:
 o=s.objects[name];verify(o.get('service_material_pass')=='SVC_PBR_V1','missing material pass '+name)
 verify(all(0<=p.material_index<len(o.material_slots) for p in o.data.polygons),'invalid face slot '+name)
 for idx in {p.material_index for p in o.data.polygons}:
  m=o.material_slots[idx].material;verify(m is not None and m.name.startswith('SVC_'),'masked material override '+name)
  n=m.node_tree.nodes
  out=next(x for x in n if x.type=='OUTPUT_MATERIAL');bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
  verify(out.inputs['Surface'].is_linked and out.inputs['Surface'].links[0].from_node==bs,'disconnected surface '+m.name)
  for socket in ('Base Color','Roughness','Normal'):verify(bs.inputs[socket].is_linked,'flat/missing '+socket+' '+m.name)
  verify(any(x.type=='TEX_NOISE' for x in n),'missing micro detail '+m.name)
for name in ('ZF_0005_Services','L02_Services'):
 used={s.objects[name].material_slots[p.material_index].material.name for p in s.objects[name].data.polygons}
 verify({'SVC_GalvanizedDuct','SVC_MutedRedPipeEnamel','SVC_BlueGreyPipeEnamel','SVC_AgedSteelFixings'}<=used,'undifferentiated services '+name)
world=base['world'];verify(s.world.name==world['name'] and s.view_settings.exposure==world['exposure'] and s.view_settings.view_transform==world['view_transform'],'world/exposure drift')
verify([(n.name,list(n.inputs['Color'].default_value),n.inputs['Strength'].default_value) for n in s.world.node_tree.nodes if n.type=='BACKGROUND']==[(x[0],x[1],x[2]) for x in world['background']],'world shader changed')
verify(sum(o.get('godot_path','').startswith('Props/') for o in s.objects)==343,'prop count')
# Execute the actual legacy authoring entry point: it MUST refuse a rejected grid.
try:
 exec(compile(Path('/home/tuxpc/game/ZERO_FRAME/tools/blender_gameplay_layout.py').read_text(),'blender_gameplay_layout.py','exec'),{})
except AssertionError as error:verify('rejected and rolled back' in str(error),'wrong replay guard failure')
else:raise AssertionError('Rejected grid was allowed to run')
# Detect possible interactions with cars retained from the later layout. Do not
# silently move props again. Report actual triangle contacts separately from AABBs.
def bounds(ob):
 pts=[ob.matrix_world@Vector(p) for p in ob.bound_box]
 return [min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]
props=[s.objects[n] for n in expected]
cars=[o for o in s.objects if o.type=='MESH' and (o.get('godot_path','').startswith('Cars/') or o.name.startswith('L02_') and o.get('source_object') and bpy.data.objects.get(o['source_object']) and bpy.data.objects[o['source_object']].get('godot_path','').startswith('Cars/'))]
cache={};bb={o.name:bounds(o) for o in props+cars};contacts=set();candidates=0
for a in props:
 for b in cars:
  al,ah=bb[a.name];bl,bh=bb[b.name]
  if not all(al[i]<bh[i]-.025 and ah[i]>bl[i]+.025 for i in range(3)):continue
  candidates+=1
  for ob in (a,b):
   if ob.name not in cache:
    cache[ob.name]=BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(p.vertices) for p in ob.data.polygons],all_triangles=False)
  if cache[a.name].overlap(cache[b.name]):contacts.add((a['godot_path'].split('/')[1],b.get('godot_path',b.name).split('/')[1] if b.get('godot_path') else b.name))
result={'status':'PASS','checks':checks,'props_restored':343,'service_objects':len(service_names),'prop_car_aabb_candidates':candidates,
 'prop_car_triangle_contacts':sorted(contacts),'full_gameplay_traversal':'UNVERIFIED; no export performed','visual_approval':'PENDING'}
(work/'validation.json').write_text(json.dumps(result,indent=2))
s['restored_services_validation']='PASS'
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_restored_materials.blend'))
print('RESTORED_SERVICES_TESTS_PASS',json.dumps(result))
