"""Restore the source wall and use Exact self-intersection handling for touching solids."""
import bpy,bmesh,json
from pathlib import Path
s=bpy.context.scene;work=Path(s['two_storey_work'])
with bpy.data.libraries.load(str(work/'before.blend'),link=False) as (src,dst):dst.objects=['ZF_0006_Walls_Concrete']
source=dst.objects[0]
for ob in list(s.objects):
 if ob.name.startswith(('TEMP_ManifoldDoorTool','TEMP_WallSection')):bpy.data.objects.remove(ob,do_unlink=True)
for name,y,z in (('ZF_0006_Walls_Concrete',-15,1.35),('L02_AlignedWallsAndColumns',15,4.75)):
 ob=s.objects[name];mat=ob.material_slots[0].material;ob.data=source.data.copy();ob.material_slots[0].material=mat
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
 # Preserve original winding; don't recalculate across touching independent solids.
 bm.to_mesh(ob.data);bm.free()
 bpy.ops.mesh.primitive_cube_add(size=1,location=(-30.15,y,z));tool=bpy.context.object;tool.name='TEMP_WallBooleanTool';tool.scale=(1.2,5.2,2.72)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
 mod=ob.modifiers.new('Exact intersection-aware doorway','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.use_self=True;mod.use_hole_tolerant=True;mod.object=tool
 assert 'FINISHED' in bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.data.objects.remove(tool,do_unlink=True)
 print('WALL_REPAIRED',name,len(ob.data.polygons))
bpy.data.objects.remove(source,do_unlink=True)
bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
print('WALL_BOOLEAN_REPAIR_READY')
