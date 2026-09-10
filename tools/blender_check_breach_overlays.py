"""Inspect original ceiling joints and upper overlays around the new opening."""
import bpy,json
from mathutils import Vector
out=[]
for ob in bpy.context.scene.objects:
 if ob.type!='MESH':continue
 if not (ob.get('detail_kind')=='CeilingReveals' or ob.name.startswith('L02_ZF_')):continue
 pts=[ob.matrix_world@Vector(p) for p in ob.bound_box]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 if lo[0]<-5.9 and hi[0]>-10.3 and lo[1]<-2.1 and hi[1]>-7.5 and lo[2]<3.43 and hi[2]>3.05:
  out.append({'name':ob.name,'kind':ob.get('detail_kind'),'lo':lo,'hi':hi})
print('BREACH_OVERLAY_AUDIT',json.dumps(out))
