"""Restore user-requested original fences only; no new placement or prop deletion."""
import bpy,json
from pathlib import Path
from datetime import datetime,timezone
s=bpy.context.scene
assert s.get('gameplay_work') and not s.get('fence_correction_work')
fences=[o for o in s.objects if o.type=='MESH' and o.get('godot_path','').startswith('Props/') and o.get('godot_path','').split('/')[1].endswith('_fence')]
assert len(fences)==60
work=Path('/home/tuxpc/game/ZERO_FRAME_backups')/('parking_prop_correction_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(parents=True,exist_ok=False)
previous=bpy.data.filepath
bpy.data.libraries.write(str(work/'before.blend'),{s},path_remap='ABSOLUTE',fake_user=True)
assert (work/'before.blend').stat().st_size>100000

def record(o):
 return {'matrix':[list(row) for row in o.matrix_world],'hide_render':o.hide_render,'hide_viewport':o.hide_viewport,'hide_set':o.hide_get(),
 'collections':sorted(c.name for c in o.users_collection),'data':o.data.name if o.data else None,
 'energy':o.data.energy if o.type=='LIGHT' else None,'color':list(o.data.color) if o.type=='LIGHT' else None}
untouched={o.name:record(o) for o in s.objects if o not in fences}
# Retrieve matrices by exact original object names from the pre-pattern snapshot.
sourcefile=Path(s['gameplay_work'])/'before.blend'
names=[o.name for o in fences]
with bpy.data.libraries.load(str(sourcefile),link=False) as (src,dst):
 assert all(name in src.objects for name in names)
 # Blender replaces the assigned list entries with datablocks on context exit.
 dst.objects=list(names)
source={name:ob for name,ob in zip(names,dst.objects)}
restored=[]
def source_world(ob):
 assert not ob.constraints, ob.name
 return source_world(ob.parent)@ob.matrix_parent_inverse@ob.matrix_basis if ob.parent else ob.matrix_basis.copy()
for ob in fences:
 original=source[ob.name]
 assert original is not None
 ob.matrix_world=source_world(original)
 group=ob['godot_path'].split('/')[1]
 col=bpy.data.collections.get(group)
 assert col is not None and col in bpy.data.collections['ENV_PROPS'].children[:],group
 col.objects.link(ob)
 for old in list(ob.users_collection):
  if old!=col:old.objects.unlink(ob)
 ob.hide_render=False;ob.hide_viewport=False;ob.hide_set(False)
 ob['game_export']=True
 restored.append({'name':ob.name,'group':group,'expected_matrix':[list(row) for row in source_world(original)]})
for ob in dst.objects:bpy.data.objects.remove(ob,do_unlink=True)
bpy.context.view_layer.update()
# Actual scene checks: originals back in place, visible, and all unrelated state intact.
for item in restored:
 ob=s.objects[item['name']]
 assert not ob.hide_render and not ob.hide_get() and not ob.hide_viewport
 assert max(abs(ob.matrix_world[i][j]-item['expected_matrix'][i][j]) for i in range(4) for j in range(4))<.00001
 assert ob.visible_get(),ob.name
for name,expected in untouched.items():assert record(s.objects[name])==expected,('unrelated_object_changed',name)
report={'source_before_pattern':str(sourcefile),'previous_working_file':previous,'restored_fence_meshes':len(restored),
        'restored_groups':sorted({x['group'] for x in restored}),'restored':restored,'unrelated_objects_unchanged':len(untouched),
        'unrelated_baseline':untouched,'wooden_objects_changed':False,'prop_layout_changed':False,'game_files_changed':False,
        'limitations':['Wooden object selection awaits developer clarification','Patterned non-fence props are not yet corrected','Gameplay traversal around restored fences is not yet verified']}
(work/'fence_restore_report.json').write_text(json.dumps(report,indent=2))
s['fence_correction_work']=str(work)
s['gameplay_phase']='ORIGINAL_FENCES_RESTORED_PROP_CORRECTION_PENDING'
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_props_correction.blend'))
assert Path(bpy.data.filepath).is_file()
print('REQUESTED_FENCES_RESTORED',json.dumps({k:v for k,v in report.items() if k not in ('restored','unrelated_baseline')}))
print('PROP_CORRECTION_FILE',bpy.data.filepath)
