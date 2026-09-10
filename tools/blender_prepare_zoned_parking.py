"""Snapshot actual scene and measure complete prop/fence assemblies for authored zoning."""
import bpy,json,hashlib
import numpy as np
from pathlib import Path
from datetime import datetime,timezone
from mathutils import Vector
s=bpy.context.scene;assert s.get('service_materials_fixed') and not s.get('zoned_parking_work')
work=Path('/home/tuxpc/game/ZERO_FRAME_backups')/('parking_zoned_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(parents=True,exist_ok=False)
bpy.data.libraries.write(str(work/'before.blend'),{s},path_remap='ABSOLUTE',fake_user=True)

def bounds(ob):
 pts=[ob.matrix_world@Vector(v) for v in ob.bound_box]
 return [[float(f(p[i] for p in pts)) for i in range(3)] for f in (min,max)]
def geometry(o):
 if o.type=='MESH':
  co=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',co)
  loops=np.empty(len(o.data.loops),dtype=np.int32);o.data.loops.foreach_get('vertex_index',loops)
  return hashlib.sha256(co.tobytes()+loops.tobytes()).hexdigest()
 if o.type=='CURVE':return hashlib.sha256(repr([[tuple(p.co) for p in sp.points] for sp in o.data.splines]).encode()).hexdigest()
 return None
objects={o.name:{'matrix':[list(row) for row in o.matrix_world],'geometry':geometry(o),'hide_render':o.hide_render,'hide_set':o.hide_get(),
 'materials':[x.material.name if x.material else None for x in o.material_slots],
 'light':{'energy':o.data.energy,'color':list(o.data.color)} if o.type=='LIGHT' else None} for o in s.objects}
groups={};parts=[]
for o in s.objects:
 if o.type!='MESH':continue
 path=o.get('godot_path','')
 if path.startswith(('Props/','Cars/')):
  key='/'.join(path.split('/')[:2]);g=groups.setdefault(key,{'objects':[],'lo':[1e9]*3,'hi':[-1e9]*3})
  g['objects'].append(o.name);lo,hi=bounds(o)
  for i in range(3):g['lo'][i]=min(g['lo'][i],lo[i]);g['hi'][i]=max(g['hi'][i],hi[i])
 if path.startswith('Props/Prop90_fence/'):
  lo,hi=bounds(o);parts.append({'name':o.name,'bounds':[lo,hi],'size':[hi[i]-lo[i] for i in range(3)],'rotation':list(o.rotation_euler),'scale':list(o.scale)})
report={'objects':objects,'groups':groups,'fence_parts':parts,'world':{'name':s.world.name,'exposure':s.view_settings.exposure},'previous_file':bpy.data.filepath}
(work/'baseline.json').write_text(json.dumps(report,indent=2))
s['zoned_parking_work']=str(work)
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_zoned.blend'))
print('ZONED_PARKING_PREPARED',json.dumps({'work':str(work),'groups':{k:{'lo':v['lo'],'hi':v['hi'],'meshes':len(v['objects'])} for k,v in groups.items()},'fence_parts':parts}))
