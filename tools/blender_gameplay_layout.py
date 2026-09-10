"""Deterministic measured placement: preserve complete assemblies, reserve FPS routes."""
import bpy,json,math
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
s=bpy.context.scene;work=Path(s['gameplay_work'])
assert not s.get('prop_rollback_work'), 'This grid layout was rejected and rolled back; do not reapply it'
assert not s.get('gameplay_layout_ready')
source=json.loads((work/'layout_before.json').read_text())['groups']
base=json.loads((Path(s['two_storey_work'])/'baseline.json').read_text())

routes=[]
for z in (0,3.4):
 for y in (-12,1.5,12):routes.append({'name':'longitudinal','low':[-25.8,y-1.4,z],'high':[28.5,y+1.4,z+1.85]})
 for x in (-23,-4.5,13.5):routes.append({'name':'cross','low':[x-1.1,-14,z],'high':[x+1.1,14,z+1.85]})
 y=-15 if z==0 else 15
 routes.append({'name':'ramp_approach','low':[-31,y-1,z],'high':[-22,y+1,z+1.85]})
# The usable annex corridor runs between its real partitions.
routes.append({'name':'annex_corridor','low':[35.25,-19,0],'high':[37.3,19,1.85]})
structures=[]
for rec in base['structures']:
 if rec['path'] not in ('Garage/Walls_Concrete','Garage/Walls_Plaster'):continue
 for c in rec['components']:
  lo,hi=c['bounds']
  # Connected perimeter's AABB encloses empty space; it is not an obstacle box.
  if hi[0]-lo[0]>50 and hi[1]-lo[1]>30:continue
  structures.append({'low':lo,'high':hi})
  if rec['path']=='Garage/Walls_Concrete':structures.append({'low':[lo[0],lo[1],lo[2]+3.4],'high':[hi[0],hi[1],hi[2]+3.4]})

def bounds(obs):
 pts=[o.matrix_world@Vector(v) for o in obs for v in o.bound_box]
 return [min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]

def overlap(a,b,pad=.06):
 return all(a['low'][i]<b['high'][i]+(pad if i<2 else -.008) and a['high'][i]>b['low'][i]-(pad if i<2 else -.008) for i in range(3))

occupied=[];placements={}

def transform_group(key,target,angle=None,scale=1):
 obs=[s.objects[n] for n in source[key]['objects']]
 lo,hi=bounds(obs);center=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
 delta=0
 if angle is not None:
  # Estimate assembly direction from all its mesh bounds, not individual wheels.
  pts=np.array([[p.x,p.y] for o in obs for p in [o.matrix_world@Vector(v) for v in o.bound_box]])
  vals,vecs=np.linalg.eigh(np.cov(pts.T));axis=vecs[:,np.argmax(vals)]
  current=math.atan2(axis[1],axis[0]);delta=angle-current
 transform=Matrix.Translation(center)@Matrix.Rotation(delta,4,'Z')@Matrix.Scale(scale,4)@Matrix.Translation(-center)
 for o in obs:o.matrix_world=transform@o.matrix_world
 bpy.context.view_layer.update();lo,hi=bounds(obs)
 translation=Vector((target[0]-(lo[0]+hi[0])/2,target[1]-(lo[1]+hi[1])/2,target[2]-lo[2]))
 for o in obs:
  o.matrix_world=Matrix.Translation(translation)@o.matrix_world
  o['gameplay_group']=key;o['gameplay_kind']='car' if '/Cars/' in key else key.rsplit('_',1)[-1]
 bpy.context.view_layer.update();lo,hi=bounds(obs)
 return {'low':lo,'high':hi,'objects':[o.name for o in obs],'kind':obs[0]['gameplay_kind']}

xs=(-24.8,-19.6,-11.4,-3.6,4.2,12,19.8,25)
for i in range(20):
 key='L01/Cars/Car%02d'%i
 if i<8:target=(xs[i],17.2,0);angle=math.pi/2
 elif i<16:target=(xs[i-8],-17.2,0);angle=math.pi/2
 else:
  target=((-18,-4.0,0),(-1,5.5,0),(8,-4.5,0),(21,5.5,0))[i-16];angle=0
 if i==8:target=(-24.8,-17.2,3.4)
 placed=transform_group(key,target,angle)
 assert not any(overlap(placed,r,0) for r in routes),('car_blocks_route',key,placed)
 assert not any(overlap(placed,r,0) for r in structures),('car_hits_structure',key)
 occupied.append(placed);placements[key]=placed
for key,target in zip(sorted(k for k in source if k.startswith('L02/Cars/')),((-19.6,17.2,3.4),(-3.6,-17.2,3.4),(12,17.2,3.4),(25,-17.2,3.4))):
 placed=transform_group(key,target,math.pi/2)
 assert not any(overlap(placed,r,0) for r in routes),key
 occupied.append(placed);placements[key]=placed

# Keep incomplete kit assets in the working file, not in the render/game.
archive=bpy.data.collections.new('ARCHIVE_UnassembledFenceKits_NOT_EXPORTED');s.collection.children.link(archive)
archived=[]
for key,record in source.items():
 if key.endswith('_fence'):
  for name in record['objects']:
   ob=s.objects[name];archive.objects.link(ob)
   for c in list(ob.users_collection):
    if c!=archive:c.objects.unlink(ob)
   ob.hide_render=True;ob.hide_set(True);ob['game_export']=False;archived.append(name)

# Measured placement candidates: maintenance islands around columns, service-room
# back walls, and upper-level equipment bays. No random corridor scattering.
islands=[]
for z in (3.4,0):
 for y in (-6.8,6.8):
  for x in (-18,-9,0,9,18,25):
   for dx in (-.8,.8):
    for dy in (-.65,.65):islands.append((x+dx,y+dy,z))
annex=[(x,y,0) for y in (-18.6,-10.6,-2.6,5.4,10.5) for x in (39.2,41.4,43.6,45.8,48,50.2,52.4,54.6)]
upperwall=[(x,y,3.4) for y in (-18.7,18.7) for x in (-27,-21,-15,-9,-3,3,9,15,21,27)]
keepout={'low':[-11.4,-8.4,0],'high':[-4.8,-1.2,6.0]}
props=sorted((k for k in source if '/Props/' in k and not k.endswith('_fence')),key=lambda k:-(source[k]['high'][0]-source[k]['low'][0])*(source[k]['high'][1]-source[k]['low'][1]))
for key in props:
 kind=key.rsplit('_',1)[-1];obs=[s.objects[n] for n in source[key]['objects']]
 scale=1.45 if kind=='shelves' else (1.25 if kind=='toolchest' else 1)
 # Square up complete groups once; placement then uses the measured oriented bounds.
 transform_group(key,(0,0,0),0,scale)
 lo,hi=bounds(obs);size=[hi[i]-lo[i] for i in range(3)]
 candidates=(annex+upperwall+islands) if kind in ('shelves','cardboard','cement','container') else (islands+annex+upperwall)
 found=None
 for x,y,z in candidates:
  box={'low':[x-size[0]/2,y-size[1]/2,z],'high':[x+size[0]/2,y+size[1]/2,z+size[2]]}
  if x<30 and (box['low'][0]<-29.5 or box['high'][0]>29.5 or box['low'][1]<-19.7 or box['high'][1]>19.7):continue
  if overlap(box,keepout,0):continue
  if any(overlap(box,r,0) for r in routes):continue
  if any(overlap(box,r,.12) for r in structures+occupied):continue
  found=(x,y,z);break
 assert found is not None,('no_clear_position',key,size)
 placed=transform_group(key,found);occupied.append(placed);placements[key]=placed
# Oil residue follows the moved assemblies instead of remaining in now-empty lanes.
for key,placed in placements.items():
 if '/Cars/' not in key or not key.startswith('L01/'):continue
 car=key.split('/')[-1]
 for ob in s.objects:
  if ob.name=='RW_Oil_'+car:
   lo,hi=placed['low'],placed['high'];oldlo,oldhi=bounds([ob]);dx=(lo[0]+hi[0]-oldlo[0]-oldhi[0])/2;dy=(lo[1]+hi[1]-oldlo[1]-oldhi[1])/2
   ob.location+=Vector((dx,dy,lo[2]+.005-oldlo[2]))
for ob in s.objects:
 if ob.name.startswith('WEAR_L02_Oil_'):ob.hide_render=True;ob.hide_set(True);ob['game_export']=False
report={'routes':routes,'placements':placements,'archived_kit_meshes':archived,'car_assemblies':24,'prop_assemblies':len(props),'clearance':'measured AABB rejection; real Godot capsule traversal still required'}
(work/'gameplay_layout.json').write_text(json.dumps(report,indent=2))
s['gameplay_layout_ready']=True;s['gameplay_phase']='MEASURED_LAYOUT_READY'
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_gameplay.blend'))
print('GAMEPLAY_LAYOUT_READY',json.dumps({'car_assemblies':24,'prop_assemblies':len(props),'routes':len(routes),'archived_kit_meshes':len(archived)}))
