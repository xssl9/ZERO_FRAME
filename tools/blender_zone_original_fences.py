"""Assemble the original chainlink kit into functional enclosures with open gates.
All 60 original mesh objects remain used and visible; additional spans reuse originals.
"""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
s=bpy.context.scene;work=Path(s['zoned_parking_work'])
assert s.get('prop_source_hierarchy_verified') and not s.get('zoned_fences_ready')
verified=json.loads((work/'verified_source_transforms.json').read_text())['matrices']
col=bpy.data.collections.new('ZONE_FenceExtensions');s.collection.children.link(col)
records=[];added=[]

original_names=[n for n in verified if '_modular_chainlink_' in n]
assert len(original_names)==60 and all(n in s.objects for n in original_names)

def duplicate(source,name):
 o=bpy.data.objects.new(name,source.data);col.objects.link(o)
 for slot,original_slot in zip(o.material_slots,source.material_slots):
  slot.link='OBJECT';slot.material=original_slot.material
 o['zoned_fence_added']=True;added.append(o.name)
 assert all(n in s.objects for n in original_names), 'Original fence ID disappeared while adding a span'
 return o

for number,origin,yaw,xy,depth,compact,zone in (
 (90,(44,-6.3,0),0,1.2,2.75,False,'parts_store'),
 (91,(46.7,4.8,0),0,1.2,2.7,False,'consumables_store'),
 (92,(43.5,-8.5,0),-math.pi/2,1,3.2,True,'workshop_secure_tools')):
 objects=[o for o in s.objects if o.get('godot_path','').startswith('Props/Prop%d_fence/'%number)]
 assert len(objects)==20
 parts={o.name.split('_modular_chainlink_',1)[1]:o for o in objects}
 root=Matrix.Translation(origin)@Matrix.Rotation(yaw,4,'Z')@Matrix.Diagonal((xy,xy,1,1))
 D=depth/xy;frame_u=2.99 if compact else 3.98;right=frame_u+2.99
 used=set();members=[]
 def put(key,u,v,z=0,angle=0):
  ob=parts[key];ob.matrix_world=root@Matrix.Translation((u,v,z))@Matrix.Rotation(angle,4,'Z')
  ob.hide_render=False;ob.hide_set(False);ob['game_export']=True;ob['zone']=zone;ob['role']='original_fence_hardware'
  used.add(key);members.append(ob.name);return ob
 put('fence_corner_outer',0,0)
 put('fence_corner_inner',right,0)
 put('fence_double',2.99,0)
 if not compact:put('fence',3.98,0)
 frame=put('fence_door_frame',frame_u,0)
 # Preserve actual asset hinge/latch offsets, opening the real gate rather than
 # deleting it or substituting a gap. Source hierarchy was independently measured.
 original_frame=Matrix(verified[parts['fence_door_frame'].name])
 original_gate=Matrix(verified[parts['fence_door_gate'].name])
 original_latch=Matrix(verified[parts['fence_door_latch'].name])
 relative=original_frame.inverted()@original_gate
 gate=parts['fence_door_gate'];gate.matrix_world=frame.matrix_world@Matrix.Translation(relative.translation)@Matrix.Rotation(math.radians(100),4,'Z')@relative.to_3x3().to_4x4()
 latch=parts['fence_door_latch'];latch.matrix_world=gate.matrix_world@original_gate.inverted()@original_latch
 for key in ('fence_door_gate','fence_door_latch'):
  ob=parts[key];ob.hide_render=False;ob.hide_set(False);ob['game_export']=True;ob['zone']=zone;ob['role']='open_service_gate';used.add(key);members.append(ob.name)
 post_positions={
 'fence_start_01_corner_01':(1,0),'post_middle':(2.99,0),
 'fence_end_01':(0,1),'fence_end_02':(0,D),
 'fence_post':(right,D),'fence_start_01_corner_02':(right,1)}
 for key,(u,v) in post_positions.items():put(key,u,v)
 for key,u,v,z in (
  ('fence_bar_bracket_01',1,0,2.42),('fence_post_bracket_02',1,0,1.2),
  ('fence_bar_bracket_02',2.99,0,.08),('fence_post_bracket_01',2.99,0,2.42),
  ('fence_post_bracket_03',0,0,.08),('fence_bar_bracket_03',right,0,1.2)):
  put(key,u,v,z)
 put('fence_corner_support',0,0,.92,math.pi/2)
 # Extend side/back spans to close actual storage zones; no display-kit parts left loose.
 panel_source=parts['fence'];post_source=parts['fence_post'];span_count=0
 def span(a,b,original=False):
  nonlocal_dummy=None
  A,B=Vector((*a,0)),Vector((*b,0));direction=B-A;length=direction.length
  ob=panel_source if original else duplicate(panel_source,'ZONE_%s_panel_%d'%(zone,len(added)))
  low=min(v.co.x for v in ob.data.vertices);high=max(v.co.x for v in ob.data.vertices);sx=(length-.075)/(high-low)
  ob.matrix_world=root@Matrix.Translation(A)@Matrix.Rotation(math.atan2(direction.y,direction.x),4,'Z')@Matrix.Translation((.0375-low*sx,0,0))@Matrix.Diagonal((sx,1,1,1))
  ob['zone']=zone;ob['role']='storage_fence_span';ob.hide_render=False;ob.hide_set(False)
  members.append(ob.name)
  if original:used.add('fence')
 def post(u,v):
  ob=duplicate(post_source,'ZONE_%s_post_%d'%(zone,len(added)));ob.matrix_world=root@Matrix.Translation((u,v,0));ob['zone']=zone;ob['role']='storage_fence_post';members.append(ob.name)
 for side in (0,right):
  remaining=D-1;count=max(1,math.ceil(remaining/1.99))
  for i in range(count):
   a=1+remaining*i/count;b=1+remaining*(i+1)/count
   span((side,a),(side,b),original=compact and side==0 and i==0)
   if i<count-1:post(side,b)
 count=math.ceil(right/1.99)
 for i in range(count):
  a=right*i/count;b=right*(i+1)/count;span((a,D),(b,D))
  if i<count-1:post(b,D)
 assert used==set(parts),(zone,set(parts)-used)
 gatecenter=root@Vector((frame_u+1.03,0,0))
 inward=root.to_3x3()@Vector((0,1,0));inward.normalize()
 corners=[root@Vector((u,v,0)) for u,v in ((0,0),(right,0),(right,D),(0,D))]
 records.append({'zone':zone,'original_group':'Prop%d_fence'%number,'original_meshes':[o.name for o in objects],
 'members':members,'gate_center':list(gatecenter),'gate_inward':list(inward),'gate_angle_degrees':100,
 'inside_bounds':[[min(p[i] for p in corners) for i in range(3)],[max(p[i] for p in corners) for i in range(3)]],
 'nominal_gate_width':xy,'frame':frame.name,'gate':gate.name})
# Existing temporary protection remains at the breach. Extend its two short sides
# to meet corners, then add missing sides using the original chainlink material.
def stretch_existing(name,center,length,axis):
 ob=s.objects[name];pts=[ob.matrix_world@Vector(v) for v in ob.bound_box]
 lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);pivot=(lo+hi)/2;pivot.z=lo.z
 factors=[1,1,1,1];factors[axis]=length/(hi[axis]-lo[axis])
 ob.matrix_world=Matrix.Translation(center)@Matrix.Diagonal(factors)@Matrix.Translation(-pivot)@ob.matrix_world
 ob['zone']='upper_breach_exclusion';ob['role']='existing_temporary_guard'
stretch_existing('GP_FenceSection_0',(-10.8,-4.75,3.4),6.3,1)
stretch_existing('GP_FenceSection_1',(-8.05,-7.9,3.4),5.5,0)
# Added north/east full panels run between posts, all on intact slab.
source=next(o for o in s.objects if o.get('godot_path','').startswith('Props/Prop90_fence/') and o.name.endswith('_modular_chainlink_fence'))
postsrc=next(o for o in s.objects if o.get('godot_path','').startswith('Props/Prop90_fence/') and o.name.endswith('_modular_chainlink_fence_post'))
for name,A,B in (('north',(-10.8,-1.6,3.4),(-5.3,-1.6,3.4)),('east',(-5.3,-7.9,3.4),(-5.3,-1.6,3.4))):
 A,B=Vector(A),Vector(B);delta=B-A;count=math.ceil(delta.length/1.99)
 for i in range(count):
  start=A+delta*i/count;end=A+delta*(i+1)/count;ob=duplicate(source,'ZONE_Breach_'+name+'_panel_'+str(i))
  low=min(v.co.x for v in ob.data.vertices);high=max(v.co.x for v in ob.data.vertices);sx=((end-start).length-.075)/(high-low)
  ob.matrix_world=Matrix.Translation(start)@Matrix.Rotation(math.atan2(delta.y,delta.x),4,'Z')@Matrix.Translation((.0375-low*sx,0,0))@Matrix.Diagonal((sx,1,.83,1))
  ob['zone']='upper_breach_exclusion';ob['role']='guard_span'
  for j,p in enumerate((start,end)):
   if j==1 and i<count-1:continue
   post=duplicate(postsrc,'ZONE_Breach_'+name+'_post_'+str(i)+'_'+str(j));post.matrix_world=Matrix.Translation(p)@Matrix.Diagonal((1,1,.83,1));post['zone']='upper_breach_exclusion';post['role']='guard_post'
# Use the retained short receiving fence as a dock-edge separator, not a random room divider.
stretch_existing('GP_FenceSection_2',(48,12.6,0),2.8,0)
s['zoned_fences_ready']=True
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_zoned.blend'))
(work/'fence_zones.json').write_text(json.dumps({'zones':records,'added_objects':added,'original_meshes_used':60},indent=2))
print('LOGICAL_FENCES_ASSEMBLED',json.dumps({'zones':[r['zone'] for r in records],'original_meshes_used':60,'extensions':len(added)}))
