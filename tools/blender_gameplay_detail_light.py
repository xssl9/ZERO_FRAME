"""Asymmetric fracture, assembled ventilation/fences, wall fissures and usable lighting."""
import bpy,bmesh,json,math,random
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
s=bpy.context.scene;work=Path(s['gameplay_work'])
assert s.get('gameplay_layout_ready') and not s.get('gameplay_detail_ready')
rng=random.Random(991208);CX,CY=s['breach_center']
col=bpy.data.collections.new('GAMEPLAY_VENTILATION_AND_DETAILS');s.collection.children.link(col)

def mat(name,color,rough,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 return m
zinc=mat('GP_GalvanizedSteel',(.36,.39,.40),.43,.85)
black=mat('GP_GrilleRecess',(.028,.034,.034),.85)
paint=mat('GP_FadedSafetyPaint',(.43,.28,.065),.72,.12)
crackmat=mat('GP_WallFissure',(.065,.061,.053),.96)
concrete=bpy.data.materials.get('BREACH_FreshFracturedConcrete')

# Each detail bucket is one mesh, not hundreds of extra draw calls.
buckets={}
def bm_for(key):
 if key not in buckets:buckets[key]=bmesh.new()
 return buckets[key]
def box(key,center,size,slot=0):
 bm=bm_for(key);result=bmesh.ops.create_cube(bm,size=1)
 for v in result['verts']:v.co=Vector(center)+Vector((v.co.x*size[0],v.co.y*size[1],v.co.z*size[2]))
 for f in {f for v in result['verts'] for f in v.link_faces}:f.material_index=slot

def tube(key,a,b,radius,slot=0,segments=12):
 bm=bm_for(key);a,b=Vector(a),Vector(b);direction=b-a
 result=bmesh.ops.create_cone(bm,cap_ends=True,cap_tris=False,segments=segments,radius1=radius,radius2=radius,depth=direction.length)
 rot=direction.to_track_quat('Z','Y')
 for v in result['verts']:v.co=(a+b)/2+rot@v.co
 for f in {f for v in result['verts'] for f in v.link_faces}:f.material_index=slot

# Real connected supply/extract runs under the beams; flanges, supports and grilles.
for z in (0,3.4):
 for sec,(xa,xb) in enumerate(((-29.8,-20),(-20,-10),(-10,0),(0,10),(10,20),(20,29.8))):
  key='GP_VentDuct_L%d_%d'%(int(z>0)+1,sec)
  tube(key,(xa,-7,2.42+z),(xb,-7,2.42+z),.14,0,24)
  for x in np.arange(math.ceil(xa/2)*2,xb,2):
   tube(key,(float(x)-.018,-7,2.42+z),(float(x)+.018,-7,2.42+z),.157,0,24)
 # Trapeze hangers attach to existing concrete beams, not into the aperture.
 for x in (-27,-21.6,-16.2,-10.8,-5.4,0,5.4,10.8,16.2,21.6,27):
  key='GP_VentSupports_L%d'%(int(z>0)+1)
  box(key,(x,-7,2.267+z),(.045,.42,.025))
  for y in (-7.19,-6.81):
   tube(key,(x,y,2.27+z),(x,y,2.65+z),.006)
   box(key,(x,y,2.651+z),(.075,.065,.008))
 for x in (-29.985,29.985):
  key='GP_WallVent_L%d_%s'%(int(z>0)+1,'W' if x<0 else 'E')
  box(key,(x,-7,2.25+z),(.012,.95,.62),1)
  for y in (-7.48,-6.52):box(key,(x+(.015 if x<0 else -.015),y,2.25+z),(.035,.035,.68))
  for zz in (1.92,2.58):box(key,(x+(.015 if x<0 else -.015),-7,zz+z),(.035,.99,.035))
  for zz in np.linspace(1.98,2.52,10):box(key,(x+(.035 if x<0 else -.035),-7,float(zz)+z),(.06,.9,.018))

# Assembled fence sections. Width and height are physically bounded, unlike the kit.
fence_bounds=[]
for idx,(x,y,z,yaw,width) in enumerate(((-10.65,-4.8,3.4,math.pi/2,3.3),(-8.1,-7.7,3.4,0,3.3),(44,10.3,0,0,2.8))):
 key='GP_FenceSection_%d'%idx;rot=Matrix.Rotation(yaw,4,'Z')
 def p(u,v,h):return Vector((x,y,z))+rot@Vector((u,v,h))
 for u in (-width/2,width/2):
  tube(key,p(u,0,0),p(u,0,2.1),.028)
  # Flat anchoring plates visibly sit on the slab.
  box(key,tuple(p(u,0,.012)),(.16,.16,.024))
 for h in (.12,2.05):tube(key,p(-width/2,0,h),p(width/2,0,h),.022)
 # Crossed diagonals clipped exactly to the frame rectangle.
 for slope in (-1,1):
  for intercept in np.arange(-width-2, width+2,.16):
   candidates=[]
   for u in (-width/2,width/2):
    h=slope*u+float(intercept)
    if .14<=h<=2.03:candidates.append((u,h))
   for h in (.14,2.03):
    u=(h-float(intercept))/slope
    if -width/2<=u<=width/2:candidates.append((u,h))
   if len(candidates)==2:tube(key,p(candidates[0][0],.015,candidates[0][1]),p(candidates[1][0],.015,candidates[1][1]),.0019,0,6)

# Wall cracks are tapered thin ribbons on wall planes, never cylindrical cables.
for idx,(center,U,V) in enumerate((((-14,-19.998,1.4),(1,0,0),(0,0,1)),((-29.998,-3,1.3),(0,1,0),(0,0,1)),((-18,-8.598,1.55),(1,0,0),(0,0,1)),((7,-19.998,4.8),(1,0,0),(0,0,1)))):
 bm=bm_for('GP_WallCracks_%d'%idx);c,u,v=Vector(center),Vector(U),Vector(V)
 for branch in range(5):
  start=Vector((rng.uniform(-.18,.18),rng.uniform(-.4,.4)));end=start+Vector((rng.uniform(-.35,.35),rng.choice((-1,1))*rng.uniform(.3,.9)))
  if idx==2:end.x=max(-.29,min(.29,end.x));start.x=max(-.25,min(.25,start.x))
  points=[]
  for j in range(9):
   t=j/8;uv=start.lerp(end,t)+Vector((rng.uniform(-.04,.04),rng.uniform(-.03,.03)))*math.sin(t*math.pi)
   points.append(c+u*uv.x+v*uv.y)
  for j in range(8):
   a,b=points[j:j+2];w=.0035*(1-j/9)+.0002
   verts=[bm.verts.new(q) for q in (a-u*w/2,a+u*w/2,b+u*w*.4,b-u*w*.4)]
   f=bm.faces.new(verts);f.material_index=3

# Change the fracture silhouette coherently, with long angular breaks rather than a
# regular noisy ellipse. All associated rim/aggregate/rebar coordinates follow it.
old=json.loads(s['breach_boundary']);N=len(old)
poly=[(2.03,.25),(1.35,1.12),(.75,2.12),(-.22,2.45),(-1.22,1.8),(-1.62,.62),(-1.93,-.52),(-1.5,-1.82),(-.66,-2.5),(.58,-2.13),(1.64,-1.12)]
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def radius_polygon(angle,points):
 d=(math.cos(angle),math.sin(angle));hits=[]
 for a,b in zip(points,points[1:]+points[:1]):
  edge=(b[0]-a[0],b[1]-a[1]);den=cross(d,edge)
  if abs(den)<1e-9:continue
  t=cross(a,edge)/den;u=cross(a,d)/den
  if t>0 and -.0001<=u<=1.0001:hits.append(t)
 assert hits
 return min(hits)
oldrel=[(x-CX,y-CY) for x,y in old]
new=[]
for i in range(N):
 a=i*math.tau/N;r=radius_polygon(a,poly)+.022*math.sin(a*17)
 new.append((CX+math.cos(a)*r,CY+math.sin(a)*r))
def warp(point):
 p=Vector(point);dx,dy=p.x-CX,p.y-CY;r=math.hypot(dx,dy)
 if r<1e-6:return p
 a=math.atan2(dy,dx);factor=radius_polygon(a,[(x-CX,y-CY) for x,y in new])/radius_polygon(a,oldrel)
 p.x=CX+dx*factor;p.y=CY+dy*factor
 return p
slab=s.objects['L02_InterstoreySlab']
for v in slab.data.vertices:
 p=slab.matrix_world@v.co
 for i,(x,y) in enumerate(old):
  if math.hypot(p.x-x,p.y-y)<.0001:
   p.x,p.y=new[i];v.co=slab.matrix_world.inverted()@p;break
slab.data.update()
for ob in list(s.objects):
 if ob.name=='BREACH_RebarRibs':
  ob.hide_render=True;ob.hide_set(True);ob['game_export']=False
  continue
 if not ob.name.startswith(('BREACH_LayeredSpalledRim','BREACH_ExposedAggregate','BREACH_Rebar_','BREACH_Hairline')):continue
 if ob.type=='MESH':
  for v in ob.data.vertices:v.co=ob.matrix_world.inverted()@warp(ob.matrix_world@v.co)
  ob.data.update()
 elif ob.type=='CURVE':
  for sp in ob.data.splines:
   for point in sp.points:
    q=ob.matrix_world.inverted()@warp(ob.matrix_world@Vector(point.co[:3]));point.co=(*q,1)
# Vary exposed lengths; leave a few long sagging tendons instead of identical ends.
for ob in list(s.objects):
 if ob.type!='CURVE' or not ob.name.startswith('BREACH_Rebar_'):continue
 points=ob.data.splines[0].points
 if rng.random()<.20:
  end=Vector(points[-1].co[:3]);prev=Vector(points[-2].co[:3]);end=prev.lerp(end,rng.uniform(.15,.55));points[-1].co=(*end,1)
 # Rebuild rib geometry from the actual, now bent steel polyline.
 for a,b in zip(points[1:-1],points[2:]):
  a,b=Vector(a.co[:3]),Vector(b.co[:3]);direction=b-a;steps=max(1,int(direction.length/.045));t=direction.normalized();u=t.cross(Vector((0,0,1))).normalized();v=t.cross(u)
  bm=bm_for('GP_RebarRibs')
  for j in range(steps):
   center=a.lerp(b,(j+.5)/steps);rings=[]
   for shift,r in ((-.001,.0075),(0,.009),(.001,.0075)):
    rings.append([bm.verts.new(center+t*shift+(u*math.cos(k*math.tau/6)+v*math.sin(k*math.tau/6))*r) for k in range(6)])
   for h in (0,1):
    for k in range(6):bm.faces.new((rings[h][k],rings[h][(k+1)%6],rings[h+1][(k+1)%6],rings[h+1][k]))
s['breach_boundary']=json.dumps(new)
# Break up the uniform radial rubble scatter into three lobes, grounding each piece.
ob=s.objects['BREACH_GroundedAngularRubble'];bm=bmesh.new();bm.from_mesh(ob.data);left=set(bm.verts);fragments=0
while left:
 seed=left.pop();part={seed};stack=[seed]
 while stack:
  v=stack.pop()
  for e in v.link_edges:
   q=e.other_vert(v)
   if q in left:left.remove(q);part.add(q);stack.append(q)
 center=sum((v.co for v in part),Vector())/len(part);dx,dy=rng.choice(((-.65,-.6),(.6,.45),(.6,-1.05)))
 target=Vector((CX+dx+rng.uniform(-.8,.8),CY+dy+rng.uniform(-.8,.8),0))
 rotation=Matrix.Rotation(rng.uniform(-.3,.3),4,'X')@Matrix.Rotation(rng.uniform(-math.pi,math.pi),4,'Z')
 pts=[rotation@(v.co-center) for v in part];floor=min(p.z for p in pts)
 for v,p in zip(part,pts):v.co=target+p+Vector((0,0,.002-floor))
 fragments+=1
bm.to_mesh(ob.data);bm.free();ob.data.update()

for key,bm in buckets.items():
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));me=bpy.data.meshes.new(key);bm.to_mesh(me);bm.free()
 for m in (zinc,black,paint,crackmat):me.materials.append(m)
 if key=='GP_RebarRibs':me.materials[0]=bpy.data.materials['BREACH_OxidizedRebar']
 ob=bpy.data.objects.new(key,me);col.objects.link(ob);ob['gameplay_kind']='fence' if key.startswith('GP_Fence') else 'detail'
 if key.startswith('GP_Fence'):
  points=[v.co for v in me.vertices];fence_bounds.append({'name':key,'low':[min(p[i] for p in points) for i in range(3)],'high':[max(p[i] for p in points) for i in range(3)]})

# Lighting is now explicitly authorized to change. Fixtures remain the motivation.
lights=[]
for ob in s.objects:
 if ob.type!='LIGHT':continue
 if 'LIGHT_Deck' in ob.name:
  ob.data.energy=125 if ob.location.z<3.4 else 110;ob.data.color=(1,.94,.84)
 elif ob.name.startswith('LIGHT_Corridor'):
  ob.data.energy=80;ob.data.color=(.90,.95,1)
 elif ob.name.startswith('LIGHT_Room'):
  index=int(ob.name[-2:])-50;ob.location=(48.3,(-16,-8,0,8)[index],2.75);ob.data.energy=95;ob.data.color=(1,.92,.80)
 lights.append({'name':ob.name,'energy':ob.data.energy,'position':list(ob.matrix_world.translation)})
# Broad daylight entering the actual garage entrance, not an unmotivated point lamp.
for name,pos,target,energy,size in (('GP_EntranceDaylight',(0,20.35,1.6),(0,0,1.6),650,12),('GP_RampDaylight',(-34,0,8),(-34,0,0),900,20)):
 data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='RECTANGLE';data.size=size;data.size_y=2 if 'Entrance' in name else 7;data.color=(.76,.86,1)
 ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
s.world=s.world.copy();bg=s.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.55,.64,.78,1);bg.inputs['Strength'].default_value=.16
s.view_settings.view_transform='AgX';s.view_settings.exposure=.65
# Add an inspectable second camera for the newly assembled ventilation and wall crack.
for name,pos,target in (('GP_Overview',(-23,1.5,1.62),(-4,1.5,1.55)),('GP_WallDetail',(-17,-16,1.62),(-14,-19.9,1.7))):
 data=bpy.data.cameras.new(name);data.lens=26;ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
s['gameplay_detail_ready']=True;s['gameplay_phase']='DETAIL_AND_LIGHT_READY'
(work/'detail_light_report.json').write_text(json.dumps({'added_detail_meshes':len(buckets),'fences':fence_bounds,'rubble_fragments':fragments,'lighting':lights,'exposure_stops':.65},indent=2))
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_gameplay.blend'))
print('GAMEPLAY_DETAIL_LIGHT_READY',json.dumps({'detail_meshes':len(buckets),'fences':len(fence_bounds),'rubble_fragments':fragments,'exposure':s.view_settings.exposure}))
