"""Undo only the rejected prop rearrangement using the real pre-pattern snapshot."""
import bpy,json,hashlib
import numpy as np
from pathlib import Path
from datetime import datetime,timezone
s=bpy.context.scene
assert s.get('gameplay_work') and not s.get('prop_rollback_work')
sourcefile=Path(s['gameplay_work'])/'before.blend';assert sourcefile.is_file()
props=[o for o in s.objects if o.type=='MESH' and o.get('godot_path','').startswith('Props/')]
assert len(props)==343
work=Path('/home/tuxpc/game/ZERO_FRAME_backups')/('parking_props_restored_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
work.mkdir(parents=True,exist_ok=False)
bpy.data.libraries.write(str(work/'before.blend'),{s},path_remap='ABSOLUTE',fake_user=True)

def geometry(o):
 if o.type=='MESH':
  co=np.empty(len(o.data.vertices)*3,dtype=np.float32);o.data.vertices.foreach_get('co',co)
  loops=np.empty(len(o.data.loops),dtype=np.int32);o.data.loops.foreach_get('vertex_index',loops)
  return hashlib.sha256(co.tobytes()+loops.tobytes()).hexdigest()
 if o.type=='CURVE':
  return hashlib.sha256(repr([[tuple(p.co) for p in sp.points] for sp in o.data.splines]).encode()).hexdigest()
 return None
baseline={o.name:{'matrix':[list(row) for row in o.matrix_world],'geometry':geometry(o),'hide_render':o.hide_render,'hide_viewport':o.hide_viewport,'hide_set':o.hide_get(),
 'materials':[slot.material.name if slot.material else None for slot in o.material_slots],
 'light':{'energy':o.data.energy,'color':list(o.data.color)} if o.type=='LIGHT' else None} for o in s.objects}
world={'name':s.world.name,'exposure':s.view_settings.exposure,'view_transform':s.view_settings.view_transform,
 'background':[(n.name,list(n.inputs['Color'].default_value),n.inputs['Strength'].default_value) for n in s.world.node_tree.nodes if n.type=='BACKGROUND']}
(work/'baseline.json').write_text(json.dumps({'objects':baseline,'world':world,'sourcefile':str(sourcefile)},indent=2))
names=[o.name for o in props]
with bpy.data.libraries.load(str(sourcefile),link=False) as (src,dst):
 assert all(name in src.objects for name in names)
 dst.objects=list(names)
sources=dict(zip(names,dst.objects));expected={};changed=0
# Unlinked library objects have no evaluated world matrix. Compose their hierarchy.
def source_world(ob):
 assert not ob.constraints, ob.name
 return source_world(ob.parent)@ob.matrix_parent_inverse@ob.matrix_basis if ob.parent else ob.matrix_basis.copy()
for o in props:
 src=sources[o.name];assert src is not None
 transform=source_world(src)
 target=[list(row) for row in transform]
 changed+=int(max(abs(o.matrix_world[i][j]-target[i][j]) for i in range(4) for j in range(4))>1e-5)
 o.matrix_world=transform
 o.hide_render=src.hide_render;o.hide_viewport=src.hide_viewport;o.hide_set(False)
 group=o['godot_path'].split('/')[1];col=bpy.data.collections.get(group)
 assert col is not None
 if col not in o.users_collection:col.objects.link(o)
 for old in list(o.users_collection):
  if old!=col:old.objects.unlink(o)
 if group.endswith('_fence'):o['game_export']=True
 # Retire only metadata for the rejected placement; keep source IDs and materials.
 for key in ('gameplay_group','gameplay_kind'):
  if key in o:del o[key]
 expected[o.name]={'matrix':target,'group':group,'visible':not src.hide_render}
for src in dst.objects:bpy.data.objects.remove(src,do_unlink=True)
bpy.context.view_layer.update()
for name,record in expected.items():
 o=s.objects[name]
 assert max(abs(o.matrix_world[i][j]-record['matrix'][i][j]) for i in range(4) for j in range(4))<1e-5,name
 assert o.visible_get() and not o.hide_render,name
for o in s.objects:
 if o.name in expected:continue
 old=baseline[o.name]
 assert [list(row) for row in o.matrix_world]==old['matrix'],o.name
 assert o.hide_render==old['hide_render'] and o.hide_get()==old['hide_set'],o.name
s['prop_rollback_work']=str(work)
s['gameplay_phase']='PROP_PLACEMENT_ROLLED_BACK_SERVICE_MATERIALS_PENDING'
s['gameplay_layout_ready']=False
s['prop_layout_policy']='Original prop transforms restored; do not replay the rejected grid placement'
report={'restored_objects':343,'changed_transforms':changed,'restored_groups':len({r['group'] for r in expected.values()}),
 'fence_meshes_visible':sum(o['godot_path'].split('/')[1].endswith('_fence') for o in props),'expected':expected,
 'cars_repositioned':False,'architecture_changed':False,'lighting_changed':False,'new_wood_assets_added':False,
 'scope':'Restore prop transforms/scale/visibility only, not an unrelated redesign; cars retain their current placement'}
(work/'rollback_report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_restored_materials.blend'))
print('PROP_LAYOUT_ROLLED_BACK',json.dumps({k:v for k,v in report.items() if k!='expected'}))
print('RESTORED_WORK',str(work))
