"""Recover missing original fence IDs and reset only the incomplete fence authoring stage."""
import bpy,json
from pathlib import Path
from mathutils import Matrix
s=bpy.context.scene;work=Path(s['zoned_parking_work'])
verified=json.loads((work/'verified_source_transforms.json').read_text())['matrices']
allnames=[n for n in verified if '_modular_chainlink_' in n]
missing=[n for n in allnames if n not in s.objects]
if missing:
 with bpy.data.libraries.load(str(work/'before.blend'),link=False) as (src,dst):dst.objects=list(missing)
 for name,ob in zip(missing,dst.objects):
  assert ob is not None
  ob.name=name
  group=ob['godot_path'].split('/')[1];bpy.data.collections[group].objects.link(ob)
for name in allnames:
 ob=s.objects[name];ob.matrix_world=Matrix(verified[name]);ob.hide_render=False;ob.hide_set(False)
# Remove only named extension objects from this unfinished stage, not originals.
col=bpy.data.collections.get('ZONE_FenceExtensions')
if col:
 for ob in list(col.objects):
  assert ob.get('zoned_fence_added') and not ob.get('transfer_id'),ob.name
  bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.collections.remove(col)
bpy.context.view_layer.update()
assert all(n in s.objects for n in allnames)
print('FENCE_STAGE_RECOVERED',json.dumps({'recovered':missing,'originals':len(allnames)}))
