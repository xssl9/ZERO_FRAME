"""Recover true prop assembly transforms, then independently verify recorded source bounds."""
import bpy,json
from pathlib import Path
from mathutils import Matrix,Vector
s=bpy.context.scene;work=Path(s['zoned_parking_work'])
d=json.loads((work/'verified_source_transforms.json').read_text())
for name,matrix in d['matrices'].items():s.objects[name].matrix_world=Matrix(matrix)
bpy.context.view_layer.update()
manifest=json.loads((Path(s['gameplay_work'])/'layout_before.json').read_text())['groups'];errors=[]
for key,rec in manifest.items():
 if '/Props/' not in key:continue
 pts=[s.objects[n].matrix_world@Vector(v) for n in rec['objects'] for v in s.objects[n].bound_box]
 low=[min(p[i] for p in pts) for i in range(3)];high=[max(p[i] for p in pts) for i in range(3)]
 errors.append(max(abs(a-b) for a,b in zip(low+high,rec['low']+rec['high'])))
assert len(errors)==114 and max(errors)<.001
parts=[]
for ob in s.objects:
 if ob.get('godot_path','').startswith('Props/Prop90_fence/'):
  pts=[ob.matrix_world@Vector(v) for v in ob.bound_box]
  parts.append({'name':ob.name,'lo':[min(p[i] for p in pts) for i in range(3)],'hi':[max(p[i] for p in pts) for i in range(3)]})
s['prop_source_hierarchy_verified']=True
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_zoned.blend'))
print('PROP_HIERARCHY_RECOVERED',json.dumps({'groups':len(errors),'max_bounds_error':max(errors),'fence_parts':parts}))
