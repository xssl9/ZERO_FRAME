"""Read-only audit of live prop groups, archived fences and actual model materials."""
import bpy,json
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene
out={'scene':s.name,'filepath':bpy.data.filepath,'gameplay_work':s.get('gameplay_work'),'gameplay_phase':s.get('gameplay_phase'),'groups':{},'replacement_fences':[]}
for o in s.objects:
 path=o.get('godot_path','')
 if o.type!='MESH':continue
 if path.startswith('Props/'):
  key='/'.join(path.split('/')[:2]);g=out['groups'].setdefault(key,{'objects':[],'lo':[1e9]*3,'hi':[-1e9]*3,'materials':set(),'hidden':0,'collections':set()})
  g['objects'].append(o.name);g['hidden']+=int(o.hide_render or o.hide_get())
  g['materials'].update(m.name for m in o.data.materials if m)
  g['collections'].update(c.name for c in o.users_collection)
  for v in o.bound_box:
   p=o.matrix_world@Vector(v)
   for i in range(3):g['lo'][i]=min(g['lo'][i],p[i]);g['hi'][i]=max(g['hi'][i],p[i])
 if o.name.startswith('GP_Fence'):
  out['replacement_fences'].append({'name':o.name,'hidden':o.hide_render,'collections':[c.name for c in o.users_collection]})
for g in out['groups'].values():g['materials']=sorted(g['materials']);g['collections']=sorted(g['collections'])
print('PROP_CORRECTION_AUDIT',json.dumps(out))
