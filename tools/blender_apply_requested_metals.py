"""Apply user-selected Poly Haven maps using metric planar/cylindrical UVs.
Colored pipe faces and shaders are explicitly excluded from replacement.
"""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from collections import Counter
s=bpy.context.scene;work=Path(s['zoned_parking_work']);root=Path('/home/tuxpc/game/ZERO_FRAME/assets/polyhaven/textures')
assert not s.get('requested_metals_ready')

def shader_fingerprint(m):
 return hashlib.sha256(repr([(n.bl_idname,n.name,[(i.name,tuple(i.default_value) if hasattr(i.default_value,'__len__') and not isinstance(i.default_value,str) else i.default_value) for i in n.inputs if hasattr(i,'default_value')]) for n in m.node_tree.nodes]+[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]).encode()).hexdigest()
colored={m.name:shader_fingerprint(m) for m in bpy.data.materials if m.name in ('SVC_MutedRedPipeEnamel','SVC_BlueGreyPipeEnamel')}
assert len(colored)==2

def material(slug):
 m=bpy.data.materials.new('PH_'+slug);m.use_nodes=True;m['polyhaven_asset']=slug;m['license']='CC0';m['uv_metres_per_tile']=2.0
 n,l=m.node_tree.nodes,m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');l.new(bs.outputs[0],out.inputs['Surface'])
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PH_MetricUV'
 images={}
 for suffix in ('diff','arm','nor_gl'):
  path=root/slug/(slug+'_'+suffix+'_2k.jpg');assert path.is_file()
  im=bpy.data.images.load(str(path),check_existing=True);size=tuple(im.size);assert im.has_data and min(size)>=2048
  im.colorspace_settings.name='sRGB' if suffix=='diff' else 'Non-Color';im.pack()
  tex=n.new('ShaderNodeTexImage');tex.name=slug+'_'+suffix;tex.image=im;tex.extension='REPEAT';l.new(uv.outputs[0],tex.inputs['Vector']);images[suffix]=tex
 l.new(images['diff'].outputs['Color'],bs.inputs['Base Color'])
 sep=n.new('ShaderNodeSeparateColor');l.new(images['arm'].outputs['Color'],sep.inputs[0])
 l.new(sep.outputs['Green'],bs.inputs['Roughness']);l.new(sep.outputs['Blue'],bs.inputs['Metallic'])
 normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='PH_MetricUV';normal.inputs['Strength'].default_value=1
 l.new(images['nor_gl'].outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],bs.inputs['Normal'])
 m.diffuse_color=(.24,.14,.075,1);m.roughness=.72
 m['aspect']=images['diff'].image.size[1]/images['diff'].image.size[0]
 return m
sheet=material('rusty_metal_sheet');pipe=material('rusty_metal_05');records=[];color_faces={}
for ob in list(s.objects):
 if ob.type!='MESH':continue
 main=ob.name in ('ZF_0005_Services','L02_Services')
 vent=ob.name.startswith(('GP_VentDuct','GP_WallVent')) or ob.get('detail_kind')=='DuctFlanges'
 if not (main or vent):continue
 # Classify disconnected solids without modifying mesh topology.
 parent=list(range(len(ob.data.vertices)))
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for e in ob.data.edges:
  a,b=e.vertices;parent[find(a)]=find(b)
 same={}
 for v in ob.data.vertices:
  key=tuple(round(float(c),5) for c in v.co)
  if key in same:parent[find(v.index)]=find(same[key])
  else:same[key]=v.index
 groups={}
 for v in ob.data.vertices:groups.setdefault(find(v.index),[]).append(ob.matrix_world@v.co)
 dims={}
 for k,pts in groups.items():
  lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)])
  dims[k]=(hi-lo,(lo+hi)/2)
 oldslots=[slot.material for slot in ob.material_slots];oldindices=[p.material_index for p in ob.data.polygons]
 ob.data=ob.data.copy();ob.data.materials.append(sheet);sheetidx=len(ob.data.materials)-1;ob.data.materials.append(pipe);pipeidx=len(ob.data.materials)-1
 uv=ob.data.uv_layers.get('PH_MetricUV') or ob.data.uv_layers.new(name='PH_MetricUV')
 changed=Counter();colors=[]
 for face,oldindex in zip(ob.data.polygons,oldindices):
  old=oldslots[oldindex];name=old.name if old else ''
  if name in colored:
   colors.append({'face':face.index,'material':name});continue
  span,center=dims[find(face.vertices[0])]
  target=None;cylindrical=False
  if main:
   if span.x>20 and span.y>.4:target=sheet
   elif span.x>20 and span.y<.4:target=pipe;cylindrical=True
  elif name=='SVC_GalvanizedDuct':target=sheet;cylindrical=ob.name.startswith('GP_VentDuct')
  if not target:continue
  face.material_index=sheetidx if target==sheet else pipeidx
  pts=[ob.matrix_world@ob.data.vertices[ob.data.loops[i].vertex_index].co for i in face.loop_indices]
  normal=(ob.matrix_world.to_3x3().inverted().transposed()@face.normal).normalized()
  scaleu=2.0;scalev=2.0*target['aspect']
  if cylindrical and abs(normal.x)<.7:
   angles=[math.atan2(p.z-center.z,p.y-center.y) for p in pts]
   if max(angles)-min(angles)>math.pi:angles=[a+math.tau if a<0 else a for a in angles]
   radius=(span.y+span.z)/4
   coords=[(p.x/scaleu,a*radius/scalev) for p,a in zip(pts,angles)]
  else:
   axis=max(range(3),key=lambda i:abs(normal[i]));a,b=((1,2),(0,2),(0,1))[axis]
   coords=[(p[a]/scaleu,p[b]/scalev) for p in pts]
  for i,co in zip(face.loop_indices,coords):uv.data[i].uv=co
  changed[target.name]+=1
 ob.data.update()
 if colors:color_faces[ob.name]=colors
 if changed:records.append({'name':ob.name,'faces':dict(changed)})
for name,expected in colored.items():assert shader_fingerprint(bpy.data.materials[name])==expected
s['requested_metals_ready']=True
report={'objects':records,'colored_shader_fingerprints':colored,'colored_faces':color_faces,'materials':[sheet.name,pipe.name],
 'uv_layer':'PH_MetricUV','normal_space':'TANGENT with OpenGL maps','normal_map_strength':1.0,'base_tile_metres':2.0}
(work/'requested_metals.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_zoned.blend'))
print('REQUESTED_METALS_APPLIED',json.dumps({'objects':len(records),'materials':report['materials'],'colored_faces_preserved':{n:len(v) for n,v in color_faces.items()}}))
