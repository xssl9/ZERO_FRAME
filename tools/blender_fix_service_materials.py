"""Explicit multi-material service surfaces, scoped to ducts/pipes and their supports.
Procedural world-space detail needs no missing texture downloads or UV guessing.
"""
import bpy,json,math
from pathlib import Path
from collections import Counter
from mathutils import Vector
s=bpy.context.scene;work=Path(s['prop_rollback_work'])
assert not s.get('service_materials_fixed')

def math_node(n,l,op,a,b):
 node=n.new('ShaderNodeMath');node.operation=op
 for i,x in enumerate((a,b)):
  if hasattr(x,'node'):l.new(x,node.inputs[i])
  else:node.inputs[i].default_value=x
 return node.outputs[0]

def noise(n,l,pos,scale,detail=2):
 node=n.new('ShaderNodeTexNoise');node.inputs['Scale'].default_value=scale;node.inputs['Detail'].default_value=detail
 l.new(pos,node.inputs['Vector']);return node.outputs['Fac']

def ramp(n,l,value,lo,hi,a,b):
 node=n.new('ShaderNodeValToRGB');node.color_ramp.elements[0].position=lo;node.color_ramp.elements[1].position=hi
 node.color_ramp.elements[0].color=(*a,1);node.color_ramp.elements[1].color=(*b,1)
 l.new(value,node.inputs[0]);return node.outputs[0]

def make_material(name,kind,color):
 mat=bpy.data.materials.new('SVC_'+name);mat.use_nodes=True;mat.diffuse_color=(*color,1);mat['service_surface']=kind
 n,l=mat.node_tree.nodes,mat.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');out.location=(900,0)
 bs=n.new('ShaderNodeBsdfPrincipled');bs.location=(600,0);l.new(bs.outputs[0],out.inputs['Surface'])
 geo=n.new('ShaderNodeNewGeometry');geo.location=(-900,0);pos=geo.outputs['Position']
 micro=noise(n,l,pos,720,2)
 fine=noise(n,l,pos,62,3)
 broad=noise(n,l,pos,3.5,2)
 bs.inputs['Base Color'].default_value=(*color,1)
 if kind=='galvanized':
  crystals=n.new('ShaderNodeTexVoronoi');crystals.inputs['Scale'].default_value=95;crystals.inputs['Randomness'].default_value=.88
  l.new(pos,crystals.inputs['Vector']);grey=n.new('ShaderNodeRGBToBW');l.new(crystals.outputs['Color'],grey.inputs[0])
  pigment=ramp(n,l,grey.outputs[0],.12,.88,(.25,.29,.31),(.46,.49,.50))
  bs.inputs['Metallic'].default_value=1
  rough=math_node(n,l,'ADD',.28,math_node(n,l,'MULTIPLY',fine,.19))
  height=math_node(n,l,'ADD',math_node(n,l,'MULTIPLY',crystals.outputs['Distance'],.22),math_node(n,l,'MULTIPLY',micro,.78))
  distance=.00015
 elif kind=='paint':
  chips=ramp(n,l,fine,.72,.79,(0,0,0),(1,1,1))
  paintshade=ramp(n,l,broad,.15,.85,tuple(x*.85 for x in color),tuple(x*1.12 for x in color))
  mix=n.new('ShaderNodeMixRGB');l.new(chips,mix.inputs[0]);l.new(paintshade,mix.inputs[1]);mix.inputs[2].default_value=(.19,.20,.20,1);pigment=mix.outputs[0]
  l.new(math_node(n,l,'MULTIPLY',chips,.85),bs.inputs['Metallic'])
  rough=math_node(n,l,'ADD',.45,math_node(n,l,'MULTIPLY',fine,.20))
  height=micro;distance=.0003
  bs.inputs['Coat Weight'].default_value=.12;bs.inputs['Coat Roughness'].default_value=.38
 elif kind=='steel':
  pigment=ramp(n,l,fine,.12,.88,tuple(x*.65 for x in color),tuple(x*1.25 for x in color))
  bs.inputs['Metallic'].default_value=.85
  rough=math_node(n,l,'ADD',.37,math_node(n,l,'MULTIPLY',broad,.21))
  height=micro;distance=.00017
 else:
  pigment=ramp(n,l,fine,.1,.9,tuple(x*.8 for x in color),tuple(x*1.1 for x in color))
  bs.inputs['Metallic'].default_value=0
  rough=math_node(n,l,'ADD',.76,math_node(n,l,'MULTIPLY',fine,.12))
  height=micro;distance=.0001
 # A trace of settled dust follows upward normals, not random full-surface dirt.
 sep=n.new('ShaderNodeSeparateXYZ');l.new(geo.outputs['Normal'],sep.inputs[0])
 dust=math_node(n,l,'MULTIPLY',math_node(n,l,'MAXIMUM',sep.outputs['Z'],0),.075)
 mix=n.new('ShaderNodeMixRGB');l.new(dust,mix.inputs[0]);l.new(pigment,mix.inputs[1]);mix.inputs[2].default_value=(.23,.215,.185,1)
 l.new(mix.outputs[0],bs.inputs['Base Color']);l.new(rough,bs.inputs['Roughness'])
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.3;bump.inputs['Distance'].default_value=distance
 l.new(height,bump.inputs['Height']);l.new(bump.outputs['Normal'],bs.inputs['Normal'])
 mat.roughness=.42 if kind=='galvanized' else .58;mat.metallic=1 if kind=='galvanized' else .85 if kind=='steel' else 0
 return mat
zinc=make_material('GalvanizedDuct','galvanized',(.36,.40,.42))
red=make_material('MutedRedPipeEnamel','paint',(.19,.037,.024))
grey=make_material('BlueGreyPipeEnamel','paint',(.075,.12,.135))
steel=make_material('AgedSteelFixings','steel',(.13,.15,.16))
recess=make_material('GrilleInterior','matte',(.016,.022,.024))
seal=make_material('GasketRubber','matte',(.022,.025,.026))
allmaterials=[zinc,red,grey,steel,recess,seal]
records=[];classified={}
for ob in list(s.objects):
 if ob.type!='MESH':continue
 base=ob.get('godot_path')=='Garage/Services' or ob.name=='L02_Services'
 detail=ob.get('detail_kind') in ('PipeFlanges','DuctFlanges','DuctSupports','PipeSupports')
 new=ob.name.startswith(('GP_Vent','GP_WallVent'))
 if not (base or detail or new):continue
 previous=[slot.material for slot in ob.material_slots]
 oldindices=[p.material_index for p in ob.data.polygons]
 ob.data=ob.data.copy()
 # Remove old object-linked overrides, which would otherwise mask data assignments.
 for slot in ob.material_slots:slot.link='DATA'
 ob.data.materials.clear()
 for mat in allmaterials:ob.data.materials.append(mat)
 if base:
  # Connectivity is used only to classify components, never to weld/change topology.
  parent=list(range(len(ob.data.vertices)))
  def root(i):
   while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
   return i
  for edge in ob.data.edges:
   a,b=edge.vertices;parent[root(a)]=root(b)
  same={}
  for v in ob.data.vertices:
   key=tuple(round(float(x),5) for x in v.co)
   if key in same:parent[root(v.index)]=root(same[key])
   else:same[key]=v.index
  groups={}
  for v in ob.data.vertices:groups.setdefault(root(v.index),[]).append(ob.matrix_world@v.co)
  slots={};components=[]
  for k,points in groups.items():
   lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
   span=[hi[i]-lo[i] for i in range(3)];y=(lo[1]+hi[1])/2
   if span[0]>20 and span[1]>.4:slot=0;kind='rectangular_duct'
   elif span[0]>20:
    if abs(y+11)<.15:slot=1
    elif abs(y+10.5)<.15:slot=2
    else:slot=3
    kind='pipe'
   else:slot=3;kind='support'
   slots[k]=slot;components.append({'bounds':[lo,hi],'kind':kind,'material':allmaterials[slot].name})
  for p in ob.data.polygons:
   slot=slots[root(p.vertices[0])];p.material_index=slot
   # Smooth circumferential pipe faces, preserving their end caps and the box duct.
   normal=ob.matrix_world.to_3x3()@p.normal
   if slot in (1,2,3) and any(c['kind']=='pipe' and c['material']==allmaterials[slot].name for c in components):
    points=groups[root(p.vertices[0])]
    if max(v.x for v in points)-min(v.x for v in points)>20:p.use_smooth=abs(normal.x)<.8
  classified[ob.name]=components
 else:
  for p,idx in zip(ob.data.polygons,oldindices):
   old=previous[idx].name if idx<len(previous) and previous[idx] else ''
   if 'Recess' in old:slot=4
   elif 'Seal' in old:slot=5
   elif 'ClampPaint' in old:slot=3
   else:slot=0
   p.material_index=slot
   if ob.name.startswith('GP_VentDuct'):p.use_smooth=abs(p.normal.x)<.8
 ob.data.update();ob['service_material_pass']='SVC_PBR_V1'
 usage=Counter(ob.material_slots[p.material_index].material.name for p in ob.data.polygons)
 records.append({'name':ob.name,'faces':len(ob.data.polygons),'materials':dict(usage)})
assert records and len(classified)==2
for name,components in classified.items():
 assert any(c['kind']=='rectangular_duct' for c in components)
 assert sum(c['kind']=='pipe' for c in components)>=3
# Save preview mode explicitly; Solid mode cannot display shader texture detail.
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  area.spaces.active.shading.type='MATERIAL';area.spaces.active.shading.use_scene_lights=True;area.spaces.active.shading.use_scene_world=True
s['service_materials_fixed']=True;s['gameplay_phase']='PROPS_RESTORED_SERVICES_MATERIALIZED_AWAITING_CHECKS'
report={'objects':records,'components':classified,'materials':[m.name for m in allmaterials],
 'images_required':False,'mapping':'world-space, metres','geometry_changed':False,'light_changed':False,'game_export':'not performed'}
(work/'service_material_report.json').write_text(json.dumps(report,indent=2))
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_restored_materials.blend'))
print('SERVICE_MATERIALS_FIXED',json.dumps({'objects':len(records),'materials':report['materials'],'components':{k:len(v) for k,v in classified.items()}}))
