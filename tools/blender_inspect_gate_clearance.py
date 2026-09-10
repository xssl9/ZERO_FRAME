import bpy,json
s=bpy.context.scene
out={}
for name in ('ZF_0326_modular_chainlink_fence_door_frame','ZF_0320_modular_chainlink_fence_door_gate','ZF_0321_modular_chainlink_fence_corner_outer'):
 o=s.objects[name];rows={}
 for z in (.2,1.,1.8,2.3):
  row=[]
  for i in range(1,20):
   x=i*.1;hit,loc,n,idx=o.ray_cast((x,-.5,z),(0,1,0),distance=1.8)
   row.append(o.material_slots[o.data.polygons[idx].material_index].material.name if hit else '-')
  rows[str(z)]=row
 out[name]={'samples_x':'0.1 to 1.9','rows':rows,'polygons':len(o.data.polygons)}
print('GATE_GEOMETRY_SCAN',json.dumps(out))
