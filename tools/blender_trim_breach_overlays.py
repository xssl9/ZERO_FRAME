"""Trim ceiling seal strips and L02 paint at the actual fracture boundary."""
import bpy,bmesh,json
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene;work=Path(s['two_storey_work']);outer=json.loads(s['breach_boundary']);N=len(outer)
assert not s.get('breach_overlays_trimmed')
verts=[(x,y,z) for z in (3.05,3.44) for x,y in outer]
faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
me=bpy.data.meshes.new('TEMP_OverlayCutter');me.from_pydata(verts,[],faces);me.update()
bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
cut=bpy.data.objects.new(me.name,me);s.collection.objects.link(cut)
trimmed=[]
for ob in list(s.objects):
 if ob.type!='MESH':continue
 if not (ob.get('detail_kind')=='CeilingReveals' or ob.name.startswith('L02_ZF_')):continue
 pts=[ob.matrix_world@Vector(p) for p in ob.bound_box]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 if not (lo[0]<-5.9 and hi[0]>-10.3 and lo[1]<-2.1 and hi[1]>-7.5 and lo[2]<3.43 and hi[2]>3.05):continue
 bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
 mod=ob.modifiers.new('Overlay follows broken slab','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cut
 assert 'FINISHED' in bpy.ops.object.modifier_apply(modifier=mod.name)
 trimmed.append(ob.name)
bpy.data.objects.remove(cut,do_unlink=True)
bpy.context.view_layer.update()
# Real rays against both overlays: no stripe/seal suspended across the aperture.
for name,x,y,z in (('RW_CeilingReveals_2',-8.1,-4.5,3.0),('L02_ZF_0563_Bay107',-7.9,-5.0,3.35)):
 ob=s.objects[name];inv=ob.matrix_world.inverted()
 assert not ob.ray_cast(inv@Vector((x,y,z)),Vector((0,0,1)),distance=.1)[0],name
s['breach_overlays_trimmed']=True;s['render_needs_refresh']=True;s['render_revision']=2
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
print('BREACH_OVERLAYS_TRIMMED',json.dumps(trimmed))
