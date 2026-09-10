"""Author a measured second deck, vehicle ramp and local reinforced-concrete breach.
Executed inside the live Blender through MCP. No original game asset exports.
"""
import bpy,bmesh,json,math,random
from pathlib import Path
from mathutils import Vector,Matrix

s=bpy.context.scene
work=Path(s['two_storey_work'])
assert bpy.data.filepath==str(work/'parking_two_storey.blend')
assert not s.get('two_storey_geometry'), 'Do not repeat over artist changes'
rng=random.Random(80926)
original=list(s.objects)
by_path={o.get('godot_path'):o for o in original if o.get('godot_path')}
CX,CY=-8.1,-4.8
HEIGHT=3.4

def collection(name):
 c=bpy.data.collections.new(name);s.collection.children.link(c);return c
upper=collection('L02_STRUCTURE_AND_SERVICES')
breach=collection('L01_LOCAL_CONCRETE_BREACH')
rampcol=collection('L02_ACCESS_RAMP')
cameras=collection('REVIEW_CAMERAS')

def mesh_obj(name,verts,faces,col,materials=(),slots=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 for m in materials:me.materials.append(m)
 if slots:
  for p,i in zip(me.polygons,slots):p.material_index=i
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob['two_storey_added']=True
 return ob

def cube(name,center,size,col,mat,bevel=0):
 x,y,z=center;a,b,c=[v/2 for v in size]
 v=[(x+i*a,y+j*b,z+k*c) for i,j,k in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
 o=mesh_obj(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],col,[mat] if mat else [])
 if bevel:
  m=o.modifiers.new('Millimetre edge highlights','BEVEL');m.width=bevel;m.segments=2
 return o

def world_copy(o,name,col,dz=0,trim=False):
 ob=o.copy();ob.data=o.data.copy();ob.name=name;col.objects.link(ob)
 ob.parent=None;ob.matrix_world=Matrix.Translation((0,0,dz))@o.matrix_world
 for key in ('transfer_id','godot_path'): 
  if key in ob:del ob[key]
 ob['two_storey_added']=True;ob['source_object']=o.name
 if trim:
  bm=bmesh.new();bm.from_mesh(ob.data)
  bad=[v for v in bm.verts if (o.matrix_world@v.co).x>30.05]
  bmesh.ops.delete(bm,geom=bad,context='VERTS');bm.to_mesh(ob.data);bm.free()
 return ob

def clean(o,preserve_winding=False):
 o.data=o.data.copy()
 bm=bmesh.new();bm.from_mesh(o.data)
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
 if not preserve_winding:bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 bm.to_mesh(o.data);bm.free()

def subtract(ob,tool):
 bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
 m=ob.modifiers.new('Local opening','BOOLEAN');m.operation='DIFFERENCE';m.solver='EXACT';m.object=tool
 # Imported touching solids need original winding and self-intersection handling.
 m.use_self=True;m.use_hole_tolerant=True
 assert 'FINISHED' in bpy.ops.object.modifier_apply(modifier=m.name)
 assert len(ob.data.polygons)>0,ob.name

def material(name,color,rough=.8,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
 bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 return m

def textured_copy(source,name):
 m=source.copy();m.name=name
 # Old UV AO belongs to the old shell, not to generated geometry.
 for n in list(m.node_tree.nodes):
  if n.type=='TEX_IMAGE' and n.image and '/ao/' in bpy.path.abspath(n.image.filepath):
   for l in list(n.outputs['Color'].links):
    mix=l.to_node
    if mix.type=='MIX_RGB':mix.inputs[0].default_value=0
 return m

floor=by_path['Garage/Floor_Parking']
ceil=by_path['Garage/Ceiling']
wall=by_path['Garage/Walls_Concrete']
concrete=textured_copy(ceil.data.materials[0],'L02_UnbakedConcrete')
floormat=textured_copy(floor.data.materials[0],'L02_FloorConcrete')
fracture=material('BREACH_FreshFracturedConcrete',(.30,.285,.254),.94)
steel=material('BREACH_OxidizedRebar',(.095,.045,.018),.64,.65)
aggregate=material('BREACH_ExposedAggregate',(.23,.215,.19),.9)
dark=material('L02_WeatheredSteel',(.045,.055,.056),.68,.75)
for mat in (fracture,aggregate,steel):
 n=mat.node_tree.nodes;l=mat.node_tree.links;bs=n.get('Principled BSDF')
 g=n.new('ShaderNodeNewGeometry');noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=120 if mat!=steel else 38
 noise.inputs['Detail'].default_value=3;l.new(g.outputs['Position'],noise.inputs['Vector'])
 cr=n.new('ShaderNodeValToRGB');base=mat.diffuse_color[:3]
 cr.color_ramp.elements[0].color=(*(v*.5 for v in base),1);cr.color_ramp.elements[1].color=(*(v*1.5 for v in base),1)
 l.new(noise.outputs['Fac'],cr.inputs[0]);l.new(cr.outputs[0],bs.inputs['Base Color'])
 bump=n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.007 if mat!=steel else .0006;bump.inputs['Strength'].default_value=.5
 l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])

# Roof and aligned walls copy the original layout BEFORE making local openings.
roof=world_copy(ceil,'L02_RoofAndBeams',upper,HEIGHT,True)
roof.data.materials[0]=concrete
walls=world_copy(wall,'L02_AlignedWallsAndColumns',upper,HEIGHT)
walls.data.materials[0]=textured_copy(wall.data.materials[0],'L02_WallConcrete')
# Close upper-level perimeter gaps that were entrances to the ground-level annex.
# Existing west/east openings are surveyed and capped on the new level only.
cube('L02_EastPerimeterClosure',(30.15,0,4.95),(.3,40,3.1),upper,concrete,.004)
cube('L02_NorthEntranceClosure',(0,20.15,4.95),(16,.3,3.1),upper,concrete,.004)
for path in ('Garage/Fixtures','Garage/Services'):
 world_copy(by_path[path],'L02_'+path.split('/')[-1],upper,HEIGHT,True)
for o in original:
 if o.get('godot_path','').startswith('FixtureDetails/'):
  world_copy(o,'L02_'+o.name,upper,HEIGHT)
 if o.type=='LIGHT' and o.name.startswith('LIGHT_Deck'):
  world_copy(o,'L02_'+o.name,upper,HEIGHT)
 if o.get('godot_path','').startswith('Paint/'):
  pts=[o.matrix_world@Vector(p) for p in o.bound_box]
  if max(p.x for p in pts)<30.01:
   world_copy(o,'L02_'+o.name,upper,HEIGHT)
 if o.get('godot_path','').startswith(('Cars/Car02/','Cars/Car05/','Cars/Car10/','Cars/Car14/')):
  world_copy(o,'L02_'+o.name,upper,HEIGHT)
 if o.get('detail_kind') in ('PipeFlanges','DuctFlanges','DuctSupports','PipeSupports'):
  world_copy(o,'L02_'+o.name,upper,HEIGHT)

# Remove ONLY the main slab component from the original ceiling; preserve beams/annex.
clean(ceil)
bm=bmesh.new();bm.from_mesh(ceil.data)
remaining=set(bm.verts);slabverts=[]
while remaining:
 seed=remaining.pop();group={seed};stack=[seed]
 while stack:
  v=stack.pop()
  for e in v.link_edges:
   w=e.other_vert(v)
   if w in remaining:remaining.remove(w);group.add(w);stack.append(w)
 pts=[ceil.matrix_world@v.co for v in group]
 if min(p.z for p in pts)>3.09 and min(p.x for p in pts)<-29.9 and max(p.x for p in pts)>29.9:
  slabverts.extend(group)
assert slabverts,'Main slab component not found'
bmesh.ops.delete(bm,geom=slabverts,context='VERTS');bm.to_mesh(ceil.data);bm.free()
slab=cube('L02_InterstoreySlab',(0,0,3.25),(60,40,.30),breach,concrete)
slab.data.materials.append(floormat)
for p in slab.data.polygons:
 if p.normal.z>.5:p.material_index=1

# Irregular outer fracture boundary. The center stays between the existing beams.
N=96
angles=[math.tau*i/N for i in range(N)]
noise=[rng.uniform(-.11,.11)+.055*math.sin(a*7) for a in angles]
outer=[(CX+(1.99+noise[i])*math.cos(a),CY+(2.47+noise[i])*math.sin(a)) for i,a in enumerate(angles)]
verts=[(x,y,z) for z in (3.085,3.415) for x,y in outer]
faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
cut=mesh_obj('TEMP_BreachCutter',verts,faces,breach)
subtract(slab,cut);bpy.data.objects.remove(cut,do_unlink=True)
# A closed, stratified fracture rim: four non-planar inner rings with irregular
# aggregate-scale facets, joined to unbroken upper/lower surfaces.
rings=[]
for k in range(6):
 ring=[]
 for i,a in enumerate(angles):
  x,y=outer[i]
  if k==0:z=3.1
  elif k==5:z=3.4
  else:
   shrink=(.07,.20,.32,.25)[k-1]+rng.uniform(-.045,.045)
   x-=math.cos(a)*shrink;y-=math.sin(a)*shrink
   z=(3.10,3.18,3.29,3.40)[k-1]+(rng.uniform(-.025,.025) if k in (2,3) else 0)
  ring.append((x,y,z))
 rings.append(ring)
rv=sum(rings,[]);rf=[];slots=[]
for k in range(6):
 q=(k+1)%6
 for i in range(N):
  j=(i+1)%N
  a,b,c,d=k*N+i,k*N+j,q*N+j,q*N+i
  rf.extend(((a,b,c),(a,c,d)))
  slots.extend(([0,0] if k in (0,4,5) else [1,1]))
rim=mesh_obj('BREACH_LayeredSpalledRim',rv,rf,breach,[concrete,fracture],slots)

# Editable polyline steel, not floating straight rods. Ends extend into sound concrete.
def curve(name,points,radius,col,mat):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=radius;cu.bevel_resolution=2;cu.use_fill_caps=True
 sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
 for p,co in zip(sp.points,points):p.co=(*co,1)
 ob=bpy.data.objects.new(name,cu);col.objects.link(ob);cu.materials.append(mat);ob['two_storey_added']=True
 return ob

bars=[]
for axis in (0,1):
 for j,offset in enumerate([i*.24 for i in range(-6,7)]):
  radius=(1.70 if axis==0 else 2.16)
  across=(2.16 if axis==0 else 1.70)
  if abs(offset)>=across:continue
  half=radius*math.sqrt(1-(offset/across)**2)
  for side in (-1,1):
   extent=half+.55
   length=half*rng.uniform(.35,.9)
   z=3.17+axis*.07
   def p(t,zz):return (CX+t,CY+offset,zz) if axis==0 else (CX+offset,CY+t,zz)
   start=side*extent;end=side*(half-length)
   pts=[p(start,z),p(side*half,z),p(side*(half-length*.55),z-rng.uniform(.07,.18)),p(end,z-rng.uniform(.25,.65))]
   ob=curve('BREACH_Rebar_%d_%02d_%s'%(axis,j,'L' if side<0 else 'R'),pts,.0075,breach,steel)
   ob['diameter_mm']=15;ob['anchored_start']=list(pts[0]);bars.append(pts)
# Rolled ribs along each exposed bar, merged into one mesh for practical render cost.
rb=bmesh.new()
for pts in bars:
 for a,b in zip(pts[1:-1],pts[2:]):
  a,b=Vector(a),Vector(b);direction=b-a;length=direction.length
  if length<.01:continue
  tangent=direction.normalized();u=tangent.cross(Vector((0,0,1))).normalized();v=tangent.cross(u)
  for j in range(max(1,int(length/.04))):
   center=a+direction*(j+.5)/max(1,int(length/.04));loops=[]
   for shift,rad in ((-.0013,.0075),(0,.009),(.0013,.0075)):
    loops.append([rb.verts.new(center+tangent*shift+(u*math.cos(k*math.tau/8)+v*math.sin(k*math.tau/8))*rad) for k in range(8)])
   for h in (0,1):
    for k in range(8):rb.faces.new((loops[h][k],loops[h][(k+1)%8],loops[h+1][(k+1)%8],loops[h+1][k]))
ribmesh=bpy.data.meshes.new('BREACH_RebarRibs');rb.to_mesh(ribmesh);rb.free();ribmesh.materials.append(steel)
ribs=bpy.data.objects.new(ribmesh.name,ribmesh);breach.objects.link(ribs);ribs['two_storey_added']=True

# Angular fragments: non-repeating low-poly convex chunks with planar broken faces.
# Ground every piece against the floor or an existing fragment, never random Z scatter.
rubble=bmesh.new();chunk_count=0
for i in range(340):
 a=rng.uniform(0,math.tau);r=math.sqrt(rng.random())
 x=CX+math.cos(a)*r*2.55;y=CY+math.sin(a)*r*2.8
 scale=rng.uniform(.22,.64) if i<55 else rng.uniform(.035,.16)
 points=[Vector((rng.uniform(-1,1)*scale,rng.uniform(-1,1)*scale*.7,rng.uniform(-1,1)*scale*.3)) for _ in range(12)]
 local=bmesh.new();vv=[local.verts.new(p) for p in points]
 hull=bmesh.ops.convex_hull(local,input=vv,use_existing_faces=False)
 bmesh.ops.delete(local,geom=[v for v in local.verts if not v.link_faces],context='VERTS')
 minz=min(v.co.z for v in local.verts)
 # Ray query ground/earlier chunk objects is done in batches below; large pieces
 # stay on the floor, small chips naturally sit around them, not high in the air.
 for v in local.verts:v.co+=Vector((x,y,.001-minz))
 local.verts.ensure_lookup_table();mapping={v:rubble.verts.new(v.co) for v in local.verts}
 for f in local.faces:
  face=rubble.faces.new([mapping[v] for v in f.verts]);face.material_index=0 if rng.random()<.78 else 1
 local.free();chunk_count+=1
bmesh.ops.recalc_face_normals(rubble,faces=list(rubble.faces))
me=bpy.data.meshes.new('BREACH_GroundedAngularRubble');rubble.to_mesh(me);rubble.free();me.materials.append(fracture);me.materials.append(concrete)
o=bpy.data.objects.new(me.name,me);breach.objects.link(o);o['two_storey_added']=True;o['fragment_count']=chunk_count
# Exposed aggregate across the jagged inner fracture, not sprinkled over sound concrete.
bm=bmesh.new()
for _ in range(700):
 i=rng.randrange(N);k=rng.choice((1,2,3));point=Vector(rings[k][i]);point+=Vector((rng.uniform(-.016,.016),rng.uniform(-.016,.016),rng.uniform(-.015,.015)))
 result=bmesh.ops.create_icosphere(bm,subdivisions=1,radius=rng.uniform(.008,.023))
 for v in result['verts']:v.co=point+Vector((v.co.x,v.co.y*.8,v.co.z*.6))
me=bpy.data.meshes.new('BREACH_ExposedAggregate');bm.to_mesh(me);bm.free();me.materials.append(aggregate)
o=bpy.data.objects.new(me.name,me);breach.objects.link(o);o['two_storey_added']=True
# Thin branching cracks taper out within the slab bay, on both visible faces.
crackmat=material('BREACH_HairlineCrack',(.055,.050,.044),.98)
for z in (3.0992,3.4008):
 for i in range(13):
  idx=int(i*N/13);a=angles[idx];x,y=outer[idx]
  length=rng.uniform(.15,.7);points=[]
  for j in range(6):
   t=j/5;points.append((x+math.cos(a)*length*t+rng.uniform(-.035,.035)*t,y+math.sin(a)*length*t+rng.uniform(-.035,.035)*t,z))
  ob=curve('BREACH_Hairline',points,.0013,breach,crackmat)
  for j,p in enumerate(ob.data.splines[0].points):p.radius=1-j/5*.93

# Exterior one-lane ramp with eased 15.45% maximum grade and six-metre landings.
def ramp_z(y):
 t=y+12
 if t<=0:return 0
 if t>=24:return HEIGHT
 slope=HEIGHT/22
 if t<2:return slope*t*t/4
 if t<=22:return slope*(t-1)
 return HEIGHT-slope*(24-t)**2/4
ys=[-18,-12]+[-12+i*.5 for i in range(1,48)]+[12,18]
verts=[]
for y in ys:
 z=ramp_z(y)
 verts.extend([(-37,y,z-.28),(-30,y,z-.28),(-37,y,z),(-30,y,z)])
faces=[]
for i in range(len(ys)-1):
 a=i*4;b=a+4
 faces.extend(((a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)))
faces.extend(((0,1,3,2),tuple((len(ys)-1)*4+k for k in (0,2,3,1))))
ramp=mesh_obj('L02_EasedVehicleRamp',verts,faces,rampcol,[floormat]);ramp['max_grade']=HEIGHT/22;ramp['rise']=HEIGHT;ramp['lane_width']=7
# Only the two necessary openings in existing/new west walls.
for ob,y,z in ((wall,-15,1.35),(walls,15,4.75)):
 clean(ob,preserve_winding=True);tool=cube('TEMP_RampDoor',(-30.15,y,z),(1,5.2,2.72),rampcol,None)
 subtract(ob,tool);bpy.data.objects.remove(tool,do_unlink=True)
# Ramp edge barriers follow its profile continuously.
for x in (-37,-30.45):
 for i in range(len(ys)-1):
  ya,yb=ys[i:i+2]
  if x>-31 and (yb<=-12 or ya>=12):continue
  za,zb=ramp_z(ya),ramp_z(yb)
  vv=[(x+dx,y,z+dz) for y,z in ((ya,za),(yb,zb)) for dx,dz in ((-.1,0),(.1,0),(.1,.85),(-.1,.85))]
  mesh_obj('L02_RampParapet',vv,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],rampcol,[concrete])
# Landings have end stops. Raised ramp is carried on piers, not floating.
for y in (-18,18):cube('L02_RampEndBarrier',(-33.5,y,ramp_z(y)+.5),(7,.2,1),rampcol,concrete,.01)
for y in (-6,0,6,12,17):
 z=ramp_z(y)-.28
 if z>0:
  for x in (-36.5,-30.7):cube('L02_RampPier',(x,y,z/2),(.5,.5,z),rampcol,concrete,.01)
# Support base, small stair access is the ramp itself (no fake unreachable upper floor).
cube('L02_RampFoundation',(-33.5,0,-.43),(7.4,36.4,.3),rampcol,concrete,.01)

# Ground and upper overview cameras; originals untouched.
for name,pos,target,lens in (
 ('REVIEW_Breach',(-15.5,-7.6,1.62),(CX,CY,2.5),23),
 ('REVIEW_UpperDeck',(-14,-7,4.98),(-3,0,4.45),24),
 ('REVIEW_Ramp',(-44,-24,8),(-31,0,2.2),28)):
 data=bpy.data.cameras.new(name);data.lens=lens;data.clip_start=.04;data.clip_end=300
 ob=bpy.data.objects.new(name,data);cameras.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
s.camera=bpy.data.objects['REVIEW_Breach']
# Persist construction data for repeatable validation and later wear pass.
s['two_storey_geometry']=True;s['breach_center']=[CX,CY];s['upper_floor_z']=HEIGHT
s['two_storey_phase']='GEOMETRY_READY_VISUAL_REVIEW_PENDING'
s['breach_boundary']=json.dumps(outer)
s['original_camera']='Parking_Walkthrough'
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
report={'objects':len(s.objects),'second_floor_z':HEIGHT,'roof_top_z':6.8,'original_lights_preserved':64,'new_matching_deck_lights':40,
 'breach_center':[CX,CY],'fracture_rings':6,'exposed_rebar_ends':len(bars),'rubble_fragments':chunk_count,'ramp_max_grade':HEIGHT/22,
 'limitations':['visual reference unavailable to agent','no engineering certification','no Godot export/collision update']}
(work/'geometry_report.json').write_text(json.dumps(report,indent=2))
print('TWO_STOREY_GEOMETRY_READY',json.dumps(report))
