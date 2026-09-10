"""Read-only live state and service-material audit before the requested rollback."""
import bpy,json
from pathlib import Path
s=bpy.context.scene
out={'scene':s.name,'file':bpy.data.filepath,'gameplay_work':s.get('gameplay_work'),'fence_work':s.get('fence_correction_work'),'services':[],'viewport':[]}
for ob in s.objects:
 if ob.type!='MESH':continue
 if not (ob.get('godot_path')=='Garage/Services' or ob.name=='L02_Services' or ob.name.startswith(('GP_Vent','GP_WallVent')) or ob.get('detail_kind') in ('PipeFlanges','DuctFlanges','DuctSupports','PipeSupports')):continue
 mats=[]
 for slot in ob.material_slots:
  m=slot.material
  item={'material':m.name if m else None,'slot_link':slot.link}
  if m:
   item['nodes']=m.use_nodes;item['viewport_color']=list(m.diffuse_color)
   if m.use_nodes:
    bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs:item.update({'base_color':list(bs.inputs['Base Color'].default_value),'metal':bs.inputs['Metallic'].default_value,'rough':bs.inputs['Roughness'].default_value})
    item['images']=[n.image.name for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
    item['links']=[(l.from_node.type,l.to_node.type,l.to_socket.name) for l in m.node_tree.links]
  mats.append(item)
 out['services'].append({'name':ob.name,'polygons':len(ob.data.polygons),'slots_used':sorted({p.material_index for p in ob.data.polygons}),'materials':mats})
for a in bpy.context.screen.areas:
 if a.type=='VIEW_3D':out['viewport'].append({'mode':a.spaces.active.shading.type,'color_type':a.spaces.active.shading.color_type,'scene_lights':a.spaces.active.shading.use_scene_lights,'scene_world':a.spaces.active.shading.use_scene_world})
print('ROLLBACK_SERVICE_AUDIT',json.dumps(out))
