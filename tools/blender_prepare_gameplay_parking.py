"""Snapshot and measure the actual live parking before the gameplay/lighting revision."""
import bpy,json
from pathlib import Path
from datetime import datetime,timezone
from mathutils import Vector
s=bpy.context.scene
assert s.get('two_storey_geometry') and not s.get('gameplay_work'), 'Inspect the current revision before repeating'
work=Path('/home/tuxpc/game/ZERO_FRAME_backups')/('parking_gameplay_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(parents=True,exist_ok=False)
bpy.data.libraries.write(str(work/'before.blend'),{s},path_remap='ABSOLUTE',fake_user=True)
sourcefile=bpy.data.filepath
groups={}
for ob in s.objects:
 if ob.type!='MESH':continue
 path=ob.get('godot_path','')
 if ob.name.startswith('L02_') and ob.get('source_object'):
  source=bpy.data.objects.get(ob['source_object'])
  if source:path=source.get('godot_path','')
  prefix='L02/'
 else:prefix='L01/'
 if not path.startswith(('Cars/','Props/')):continue
 parts=path.split('/');key=prefix+'/'.join(parts[:2])
 group=groups.setdefault(key,{'objects':[],'low':[1e10]*3,'high':[-1e10]*3})
 group['objects'].append(ob.name)
 for point in [ob.matrix_world@Vector(v) for v in ob.bound_box]:
  for i in range(3):group['low'][i]=min(group['low'][i],point[i]);group['high'][i]=max(group['high'][i],point[i])
report={'work':str(work),'source_blend':sourcefile,'objects':len(s.objects),'groups':groups,'lights':[{'name':o.name,'pos':list(o.matrix_world.translation),'energy':o.data.energy} for o in s.objects if o.type=='LIGHT']}
(work/'layout_before.json').write_text(json.dumps(report,indent=2))
s['gameplay_work']=str(work);s['gameplay_phase']='MEASURED_BEFORE_REVISION'
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_gameplay.blend'))
print('GAMEPLAY_PARKING_PREPARED',json.dumps({'work':str(work),'groups':{k:{'count':len(v['objects']),'low':v['low'],'high':v['high']} for k,v in groups.items()}}))
