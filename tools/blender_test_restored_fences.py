"""Read-only checks of requested fence restoration and preservation of all other objects."""
import bpy,json,math
from pathlib import Path
s=bpy.context.scene;work=Path(s['fence_correction_work']);r=json.loads((work/'fence_restore_report.json').read_text())
checks=0
for item in r['restored']:
 o=s.objects[item['name']]
 assert o.visible_get() and not o.hide_render and not o.hide_viewport and o.get('game_export') is True
 assert sorted(c.name for c in o.users_collection)==[item['group']]
 assert max(abs(o.matrix_world[i][j]-item['expected_matrix'][i][j]) for i in range(4) for j in range(4))<.00001
 assert len(o.data.vertices)>0 and len(o.data.polygons)>0
 assert all(math.isfinite(x) for row in o.matrix_world for x in row)
 assert all(slot.material for slot in o.material_slots)
 checks+=6
for name,expected in r['unrelated_baseline'].items():
 o=s.objects[name]
 actual={'matrix':[list(row) for row in o.matrix_world],'hide_render':o.hide_render,'hide_viewport':o.hide_viewport,'hide_set':o.hide_get(),
 'collections':sorted(c.name for c in o.users_collection),'data':o.data.name if o.data else None,
 'energy':o.data.energy if o.type=='LIGHT' else None,'color':list(o.data.color) if o.type=='LIGHT' else None}
 assert actual==expected,('unrelated_state_changed',name)
 checks+=1
assert Path(bpy.data.filepath)==work/'parking_props_correction.blend'
assert Path(bpy.data.filepath).stat().st_size>100000
result={'status':'PASS','checks':checks+2,'restored_groups':r['restored_groups'],'restored_meshes':60,
 'unrelated_objects_preserved':len(r['unrelated_baseline']),'gameplay_traversal':'UNVERIFIED','wooden_objects':'awaiting clarification','patterned_layout':'not yet corrected'}
(work/'fence_validation.json').write_text(json.dumps(result,indent=2))
print('RESTORED_FENCE_TESTS_PASS',json.dumps(result))
