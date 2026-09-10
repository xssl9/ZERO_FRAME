"""Subtle context-aware wear; no changes to original lights, world or exposure."""
import bpy,json,math,random
import numpy as np
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene;work=Path(s['two_storey_work'])
assert s.get('two_storey_geometry') and not s.get('two_storey_wear')
rng=random.Random(801926)
col=bpy.data.collections.new('SURFACE_SUBTLE_ABANDONMENT');s.collection.children.link(col)
texdir=work/'textures';texdir.mkdir(exist_ok=True)

def mathnode(nodes,links,op,a,b):
 n=nodes.new('ShaderNodeMath');n.operation=op
 for i,v in enumerate((a,b)):
  if hasattr(v,'node'):links.new(v,n.inputs[i])
  else:n.inputs[i].default_value=v
 return n.outputs[0]

def noise(nodes,links,vector,scale,detail=2):
 n=nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=detail
 links.new(vector,n.inputs['Vector']);return n.outputs['Fac']

def mix_color(nodes,links,bs,fac,color):
 previous=bs.inputs['Base Color'].links[0].from_socket if bs.inputs['Base Color'].is_linked else tuple(bs.inputs['Base Color'].default_value)
 n=nodes.new('ShaderNodeMixRGB');n.label='Subtle pigment only; retain underlying PBR'
 links.new(fac,n.inputs[0]);n.inputs[2].default_value=(*color,1)
 if hasattr(previous,'node'):links.new(previous,n.inputs[1])
 else:n.inputs[1].default_value=previous
 links.new(n.outputs[0],bs.inputs['Base Color'])

copies={};counts={}
for ob in list(s.objects):
 if ob.type!='MESH':continue
 path=ob.get('godot_path','');source=ob.get('source_object','')
 origin=bpy.data.objects.get(source) if source else ob
 group=origin.get('godot_path','') if origin else path
 name=ob.name
 if group.startswith('Paint/'):
  kind='paint'
 elif group.startswith(('Props/','Cars/')):
  kind='dust'
 elif group in ('Garage/Walls_Concrete','Garage/Walls_Plaster') or name=='L02_AlignedWallsAndColumns':
  kind='wall'
 elif group in ('Garage/Floor_Parking','Garage/Floor_Annex') or name in ('L02_InterstoreySlab','L02_EasedVehicleRamp'):
  kind='floor'
 elif group=='Garage/Services':kind='service'
 else:continue
 for slot in ob.material_slots:
  old=slot.material
  if not old or not old.use_nodes:continue
  # Do not dust emissive glass/signs or transmissive surfaces.
  bs=next((n for n in old.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if not bs or (kind=='dust' and (bs.inputs['Transmission Weight'].default_value>.2 or bs.inputs['Emission Strength'].default_value>0)):continue
  key=(old.name,kind)
  # Shared geometry can already point at a processed material.
  if old.get('subtle_wear_kind'):continue
  if key not in copies:
   m=old.copy();m.name='WEAR_'+old.name;m['subtle_wear_kind']=kind
   n,l=m.node_tree.nodes,m.node_tree.links;bs=next(n for n in n if n.type=='BSDF_PRINCIPLED')
   geo=n.new('ShaderNodeNewGeometry');pos=geo.outputs['Position']
   ns=noise(n,l,pos,2.4)
   if kind=='paint':
    # Preserve all existing alpha artwork, multiplying rather than replacing it.
    fine=noise(n,l,pos,55,3)
    ramp=n.new('ShaderNodeValToRGB');ramp.label='Abraded paint islands'
    ramp.color_ramp.elements[0].position=.33;ramp.color_ramp.elements[0].color=(.08,.08,.08,1)
    ramp.color_ramp.elements[1].position=.53;ramp.color_ramp.elements[1].color=(.88,.88,.88,1)
    l.new(fine,ramp.inputs[0])
    oldalpha=bs.inputs['Alpha'].links[0].from_socket if bs.inputs['Alpha'].is_linked else bs.inputs['Alpha'].default_value
    l.new(mathnode(n,l,'MULTIPLY',oldalpha,ramp.outputs[0]),bs.inputs['Alpha'])
    mix_color(n,l,bs,mathnode(n,l,'MULTIPLY',ns,.12),(.31,.30,.26))
    bs.inputs['Roughness'].default_value=.88
   elif kind=='wall':
    sep=n.new('ShaderNodeSeparateXYZ');l.new(pos,sep.inputs[0])
    height=mathnode(n,l,'MODULO',sep.outputs['Z'],3.4)
    base=mathnode(n,l,'MAXIMUM',mathnode(n,l,'SUBTRACT',1,mathnode(n,l,'MULTIPLY',height,1.8)),0)
    fac=mathnode(n,l,'MULTIPLY',mathnode(n,l,'MULTIPLY',base,ns),.20)
    mix_color(n,l,bs,fac,(.10,.087,.068))
   elif kind=='service':
    # Small rust freckles, not uniformly orange infrastructure.
    speck=noise(n,l,pos,19,3)
    threshold=mathnode(n,l,'MAXIMUM',mathnode(n,l,'SUBTRACT',speck,.67),0)
    fac=mathnode(n,l,'MINIMUM',mathnode(n,l,'MULTIPLY',threshold,2.8),.24)
    mix_color(n,l,bs,fac,(.17,.052,.016))
   else:
    normal=n.new('ShaderNodeSeparateXYZ');l.new(geo.outputs['Normal'],normal.inputs[0])
    up=mathnode(n,l,'MAXIMUM',normal.outputs['Z'],0)
    fac=mathnode(n,l,'MULTIPLY',mathnode(n,l,'MULTIPLY',ns,up),.09 if kind=='dust' else .05)
    mix_color(n,l,bs,fac,(.28,.255,.215))
    oldrough=bs.inputs['Roughness'].links[0].from_socket if bs.inputs['Roughness'].is_linked else bs.inputs['Roughness'].default_value
    if kind=='floor':l.new(mathnode(n,l,'MAXIMUM',oldrough,.66),bs.inputs['Roughness'])
   copies[key]=m;counts[kind]=counts.get(kind,0)+1
  slot.link='OBJECT';slot.material=copies[key]

# Transparent radial decals: zero coverage at all edges; oil is residual, not water.
def decal_material(kind,pigment,rough,opacity):
 m=bpy.data.materials.new('WEAR_Decal_'+kind);m.use_nodes=True
 n,l=m.node_tree.nodes,m.node_tree.links;bs=n.get('Principled BSDF')
 bs.inputs['Base Color'].default_value=(*pigment,1);bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeTexCoord');v=n.new('ShaderNodeVectorMath');v.operation='SUBTRACT';v.inputs[1].default_value=(.5,.5,0);l.new(uv.outputs['UV'],v.inputs[0])
 length=n.new('ShaderNodeVectorMath');length.operation='LENGTH';l.new(v.outputs[0],length.inputs[0])
 broad=noise(n,l,uv.outputs['UV'],7,3)
 edge=mathnode(n,l,'SUBTRACT',.43,length.outputs['Value'])
 edge=mathnode(n,l,'ADD',edge,mathnode(n,l,'MULTIPLY',mathnode(n,l,'SUBTRACT',broad,.5),.10))
 alpha=mathnode(n,l,'MINIMUM',mathnode(n,l,'MAXIMUM',mathnode(n,l,'MULTIPLY',edge,8),0),1)
 l.new(mathnode(n,l,'MULTIPLY',alpha,opacity),bs.inputs['Alpha'])
 return m

def plane(name,center,u,v,mat):
 c,U,V=Vector(center),Vector(u),Vector(v)
 verts=[c-U/2-V/2,c+U/2-V/2,c+U/2+V/2,c-U/2+V/2]
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],[(0,1,2,3)]);me.materials.append(mat);me.update()
 uv=me.uv_layers.new()
 for loop,coord in zip(uv.data,((0,0),(1,0),(1,1),(0,1))):loop.uv=coord
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.visible_shadow=False;ob['two_storey_added']=True
 return ob

dust=decal_material('SettledDust',(.22,.20,.16),.97,.18)
oil=decal_material('OldOil',(.028,.026,.019),.48,.28)
rust=decal_material('RustRunoff',(.18,.061,.024),.91,.18)
# Sparse traces around the local fall, leaving main traffic lanes readable.
plane('WEAR_BreachDust',(-8.1,-4.8,.0025),(7,0,0),(0,7.8,0),dust)
for i,(x,y) in enumerate(((-19,12),(12,-12),(21,5),(-13,-1))):
 plane('WEAR_ThinDust_%02d'%i,(x,y,.003),(rng.uniform(1,2),0,0),(0,rng.uniform(.5,1.1),0),dust)
# A few new oil stains on L02 underneath the actual selected car bays.
for i,(x,y) in enumerate(((-11.3,17),(6.6,17),(-11.6,-17),(16.2,-17))):
 plane('WEAR_L02_Oil_%02d'%i,(x,y,3.402),(.85,0,0),(0,.60,0),oil)
# Rust runoff below real service entries on the east/west boundary.
for side in (-1,1):
 for y in (-11,-10.5,9.5):
  plane('WEAR_LocalRunoff',(side*29.995,y,2.0),(0,side*.28,0),(0,0,1.15),rust)

# Four physically small shallow puddles; the surrounding floor remains rough/dry.
water=bpy.data.materials.new('WEAR_ShallowStillWater');water.use_nodes=True
bs=water.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.13,.145,.12,1)
bs.inputs['Roughness'].default_value=.10;bs.inputs['IOR'].default_value=1.333;bs.inputs['Transmission Weight'].default_value=.78
puddle_area=0
for i,(x,y,rx,ry) in enumerate(((-5.2,-5.8,.55,.30),(14,18.9,.40,.25),(-22,-19.0,.48,.28),(24,18.9,.35,.21))):
 N=64;verts=[(x,y,.004)]
 for j in range(N):
  a=math.tau*j/N;r=1+.10*math.sin(5*a+i)+.045*math.sin(11*a)
  verts.append((x+rx*r*math.cos(a),y+ry*r*math.sin(a),.004))
 faces=[(0,j+1,(j+1)%N+1) for j in range(N)]
 me=bpy.data.meshes.new('WEAR_Puddle_%02d'%i);me.from_pydata(verts,[],faces);me.materials.append(water);me.update()
 ob=bpy.data.objects.new(me.name,me);col.objects.link(ob);ob['two_storey_added']=True;ob['depth_mm']=4
 puddle_area+=sum(p.area for p in me.polygons)
 plane('WEAR_PuddleDarkenedConcrete_%d'%i,(x,y,.002),(rx*2.5,0,0),(0,ry*2.5,0),decal_material('DampMargin_%d'%i,(.11,.104,.084),.60,.23))

# Hand-authored original spray tags, rasterized with pigment wear and slight overspray.
# Image reference is NOT sampled, embedded or used as a surface texture.
paths=[[(.08,.18),(.13,.85),(.40,.22),(.42,.85)],[(.40,.25),(.48,.78),(.59,.86),(.69,.72),(.68,.32),(.58,.18),(.48,.25)],[(.73,.82),(.76,.2),(.92,.85)],[(.07,.12),(.92,.10)]]
N=768;yy,xx=np.mgrid[0:N,0:N].astype(np.float32);xx=(xx+.5)/N;yy=(yy+.5)/N
np_rng=np.random.default_rng(804926)
for tag in range(4):
 mask=np.zeros((N,N),np.float32)
 for path in paths:
  p=[(x+rng.uniform(-.018,.018),y+rng.uniform(-.035,.035)) for x,y in path]
  for (ax,ay),(bx,by) in zip(p,p[1:]):
   t=np.clip(((xx-ax)*(bx-ax)+(yy-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2),0,1)
   dist=np.sqrt((xx-ax-t*(bx-ax))**2+(yy-ay-t*(by-ay))**2)
   stroke=np.exp(-(dist/.009)**2)*.47+np.exp(-(dist/.021)**2)*.055
   mask=np.maximum(mask,stroke)
 mask*=np_rng.uniform(.55,1,(N,N));mask[np_rng.random((N,N))<.16]*=.12
 # A handful of drips hang from stroke bottoms, not from arbitrary wall points.
 for ax,ay in ((.12,.21),(.57,.20),(.77,.22)):
  mask=np.maximum(mask,np.exp(-((xx-ax)/.0018)**2)*np.clip((ay-yy)*15,0,1)*np.clip((yy-ay+.13)*30,0,1)*.2)
 rgba=np.empty((N,N,4),np.float32)
 pigment=((.035,.045,.042),(.13,.065,.047),(.07,.085,.10),(.14,.12,.06))[tag]
 rgba[:,:,:3]=pigment;rgba[:,:,3]=mask
 image=bpy.data.images.new('WEAR_SprayTag_%d'%tag,width=N,height=N,alpha=True);image.pixels.foreach_set(rgba.ravel());image.filepath_raw=str(texdir/('spray_tag_%d.png'%tag));image.file_format='PNG';image.save();image.pack()
 m=bpy.data.materials.new('WEAR_SprayPigment_%d'%tag);m.use_nodes=True
 ns,ls=m.node_tree.nodes,m.node_tree.links;bs=ns.get('Principled BSDF');bs.inputs['Roughness'].default_value=.92
 tex=ns.new('ShaderNodeTexImage');tex.image=image;ls.new(tex.outputs['Color'],bs.inputs['Base Color']);ls.new(tex.outputs['Alpha'],bs.inputs['Alpha'])
 x,y,z=(( -14,-19.995,1.1),(18,-19.995,1.3),(-29.995,5,1.1),(8,-19.995,4.6))[tag]
 u=(1.5,0,0) if tag!=2 else (0,-1.35,0)
 plane('WEAR_ScatteredGraffiti_%d'%tag,(x,y,z),u,(0,0,.8),m)

# Tiny paper litter only near perimeter, settled flat instead of airborne confetti.
paper=bpy.data.materials.new('WEAR_DustyPaper');paper.use_nodes=True
bs=paper.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.29,.265,.215,1);bs.inputs['Roughness'].default_value=.97
for i in range(9):
 x=rng.uniform(-25,25);y=rng.choice((-19.5,19.5));a=rng.uniform(0,math.tau)
 plane('WEAR_Paper_%d'%i,(x,y,.003),(.14*math.cos(a),.14*math.sin(a),0),(-.09*math.sin(a),.09*math.cos(a),0),paper)

# Sparse chipped safety paint on accessible columns, not new geometry throughout.
s['two_storey_wear']=True;s['two_storey_phase']='READY_FOR_GEOMETRY_AND_RENDER_CHECKS'
s['added_puddle_area_m2']=puddle_area
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
report={'material_variants':counts,'new_puddles':4,'new_puddle_area_m2':puddle_area,'main_floor_wet_percentage':puddle_area/2400*100,
        'new_graffiti':4,'old_lighting_changed':False,'reference_used_as_texture':False,'reference_visual_match':'UNVERIFIED'}
(work/'wear_report.json').write_text(json.dumps(report,indent=2))
print('TWO_STOREY_WEAR_READY',json.dumps(report))
