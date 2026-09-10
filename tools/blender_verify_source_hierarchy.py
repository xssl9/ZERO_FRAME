"""Evaluate source hierarchy explicitly, never trust unevaluated library matrix_world."""
import bpy,json
from pathlib import Path
from mathutils import Matrix,Vector
s=bpy.context.scene;work=Path(s['zoned_parking_work']);sourcepath=Path(s['gameplay_work'])/'before.blend'
manifest=json.loads((Path(s['gameplay_work'])/'layout_before.json').read_text())['groups']
names=[o.name for o in s.objects if o.get('godot_path','').startswith('Props/')]
with bpy.data.libraries.load(str(sourcepath),link=False) as (src,dst):dst.objects=list(names)
loaded=dict(zip(names,dst.objects));memo={}
def world(o):
 if o not in memo:
  assert not o.constraints, ('source_constraint',o.name)
  memo[o]=world(o.parent)@o.matrix_parent_inverse@o.matrix_basis if o.parent else o.matrix_basis.copy()
 return memo[o]
expected={name:[list(row) for row in world(o)] for name,o in loaded.items()}
errors=[];report={}
for key,rec in manifest.items():
 if '/Props/' not in key:continue
 pts=[world(loaded[name])@Vector(v) for name in rec['objects'] for v in loaded[name].bound_box]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 err=max(abs(a-b) for a,b in zip(lo+hi,rec['low']+rec['high']))
 errors.append(err)
 if key.endswith(('_fence','_shelves','_toolchest')):report[key]={'lo':lo,'hi':hi,'error':err}
assert max(errors)<.001, max(errors)
(work/'verified_source_transforms.json').write_text(json.dumps({'matrices':expected,'max_bounds_error':max(errors),'groups_checked':len(errors)},indent=2))
for o in dst.objects:bpy.data.objects.remove(o,do_unlink=True)
print('SOURCE_HIERARCHY_VERIFIED',json.dumps({'groups_checked':len(errors),'max_error_m':max(errors),'selected':report}))
