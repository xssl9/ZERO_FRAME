"""Real Blender integration checks, including actual evaluated ray casts.
Run through MCP on the saved scene; raises on missing data, blocked openings or drift.
"""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene;work=Path(s['two_storey_work']);baseline=json.loads((work/'baseline.json').read_text())
assert s.get('two_storey_geometry') and s.get('two_storey_wear')
bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
checks=[]
def check(name,condition,detail=None):
 assert condition, (name,detail)
 checks.append({'check':name,'result':'PASS','detail':detail})
# Every original light and its transform are bitwise unchanged (no tolerance masking).
for old in baseline['lights']:
 ob=s.objects.get(old['name']);check('light:'+old['name'],ob is not None)
 check('light_photometry:'+old['name'],ob.data.energy==old['energy'] and list(ob.data.color)==old['color'] and [list(row) for row in ob.matrix_world]==old['matrix'])
check('world_unchanged',s.world.name==baseline['render']['world'])
check('exposure_unchanged',s.view_settings.exposure==baseline['render']['exposure'])
for name,count in (('ENV_CARS',100),('ENV_PROPS',343),('ENV_PAINT',145)):
 check('original_collection:'+name,len(bpy.data.collections[name].all_objects)==count)
check('original_transfer_count',len([o for o in s.objects if o.get('transfer_id')])==601)
for name in ('L02_InterstoreySlab','BREACH_LayeredSpalledRim','L02_EasedVehicleRamp'):
 ob=s.objects[name];bm=bmesh.new();bm.from_mesh(ob.data)
 bad=[e for e in bm.edges if not e.is_manifold]
 check('closed_manifold:'+name,len(bad)==0,len(bad));bm.free()
 check('finite_vertices:'+name,all(math.isfinite(c) for v in ob.data.vertices for c in v.co))

def local_ray(ob,origin,direction,distance):
 inv=ob.matrix_world.inverted();origin=inv@Vector(origin);direction=inv.to_3x3()@Vector(direction)
 scale=direction.length
 hit,loc,normal,idx=ob.ray_cast(origin,direction.normalized(),distance=distance*scale,depsgraph=dg)
 return hit,ob.matrix_world@loc if hit else None
# Tests include center, off-center, intact slab and the roof above, not just mesh counts.
slab=s.objects['L02_InterstoreySlab'];rim=s.objects['BREACH_LayeredSpalledRim']
for x,y in ((-8.1,-4.8),(-8.5,-4.8),(-7.7,-4.8),(-8.1,-4.4),(-8.1,-5.2)):
 for ob in (slab,rim):
  hit,loc=local_ray(ob,(x,y,2.9),(0,0,1),.7)
  check('breach_clear:'+ob.name+':'+str((x,y)),not hit, list(loc) if hit else None)
for x,y in ((-14,-4.8),(4,5),(22,-13)):
 hit,loc=local_ray(slab,(x,y,4),(0,0,-1),1)
 check('solid_upper_floor:'+str((x,y)),hit and abs(loc.z-3.4)<.0001,list(loc) if hit else None)
hit,loc=local_ray(s.objects['L02_RoofAndBeams'],(-8.1,-4.8,4.5),(0,0,1),3)
check('upper_roof_over_breach',hit and abs(loc.z-6.5)<.001,list(loc) if hit else None)
# Beams around the damaged slab remain in their measured positions.
ceiling=s.objects['ZF_0000_Ceiling']
for x in (-10.8,-5.4):
 hit,loc=local_ray(ceiling,(x,-4.8,2.1),(0,0,1),1)
 check('original_beam_preserved:'+str(x),hit and abs(loc.z-2.655)<.001,list(loc) if hit else None)
# Integrated overlay checks: paint and ceiling seals must end at the broken edge,
# but remain present over the sound part of the same slab.
for name,x,y,z,expected in (
 ('RW_CeilingReveals_2',-8.1,-4.5,3.0,False),
 ('RW_CeilingReveals_2',-4,-4.5,3.0,True),
 ('L02_ZF_0563_Bay107',-7.9,-5.0,3.35,False),
 ('L02_ZF_0563_Bay107',-7.9,-8.0,3.35,True)):
 hit,loc=local_ray(s.objects[name],(x,y,z),(0,0,1),.1)
 check('overlay_matches_slab:'+name+':'+str((x,y)),hit==expected,list(loc) if hit else None)
# Floor/ramp contacts and both connecting wall doorways.
ramp=s.objects['L02_EasedVehicleRamp']
for y,z in ((-15,0),(0,1.7),(15,3.4)):
 hit,loc=local_ray(ramp,(-33.5,y,7),(0,0,-1),8)
 check('ramp_contact:'+str(y),hit and abs(loc.z-z)<.0001,list(loc) if hit else None)
for name,y,z in (('ZF_0006_Walls_Concrete',-15,1.4),('L02_AlignedWallsAndColumns',15,4.8)):
 hit,loc=local_ray(s.objects[name],(-31,y,z),(1,0,0),2)
 check('ramp_door_open:'+name,not hit,list(loc) if hit else None)
check('ramp_grade',0<float(ramp['max_grade'])<.16,ramp['max_grade'])
check('small_puddle_coverage',0<s['added_puddle_area_m2']<2,s['added_puddle_area_m2'])
check('no_reference_texture',not any(n.type=='TEX_IMAGE' and n.image and n.image.filepath==s['reference_image'] for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes))
# Verify every image actually referenced by the current scene is available.
images=set()
for ob in s.objects:
 for slot in ob.material_slots:
  m=slot.material
  if m and m.use_nodes:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and n.image:images.add(n.image)
for im in images:
 check('image_loaded:'+im.name,im.has_data and im.size[0]>0)
 if im.source=='FILE' and not im.packed_file:
  check('image_exists:'+im.name,Path(bpy.path.abspath(im.filepath)).is_file())
# Check each camera's near foreground ray to prevent rendering from inside geometry.
for name in ('REVIEW_Breach','REVIEW_UpperDeck','REVIEW_Ramp'):
 cam=s.objects[name];forward=cam.matrix_world.to_quaternion()@Vector((0,0,-1))
 result=s.ray_cast(dg,cam.location,forward,distance=.3)
 check('camera_clear:'+name,not result[0],result[4].name if result[0] else None)
# Save complete individual results for audit, without treating these as visual approval.
report={'status':'PASS','checks':len(checks),'results':checks,'images_checked':len(images),'reference_match':'UNVERIFIED','artistic_quality':'VISUAL_REVIEW_PENDING'}
(work/'validation.json').write_text(json.dumps(report,indent=2))
s['two_storey_validation']='PASS';bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
print('TWO_STOREY_TESTS_PASS',json.dumps({k:v for k,v in report.items() if k!='results'}))
