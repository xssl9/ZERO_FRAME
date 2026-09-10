"""Inspect invalid tangent UV triangles without touching geometry."""
import bpy, json
from pathlib import Path
s=bpy.context.scene
report=json.loads((Path(s['photoreal_finish_work'])/'finish_report.json').read_text())
failures=[]
for name in report['objects']:
    ob=s.objects[name];uv=ob.data.uv_layers['PF_MetricSurface'];ob.data.calc_loop_triangles()
    for tri in ob.data.loop_triangles:
        if tri.area < 1e-10: continue
        a,b,c=[uv.data[i].uv for i in tri.loops]
        det=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
        if abs(det)<=1e-12:
            failures.append({'object':name,'polygon':tri.polygon_index,'area':tri.area,'normal':list(tri.normal),
              'face_normal':list(ob.data.polygons[tri.polygon_index].normal),'uv':[list(a),list(b),list(c)],
              'positions':[list(ob.matrix_world@ob.data.vertices[i].co) for i in tri.vertices]})
print('UV_DIAGNOSTIC',json.dumps({'failures':len(failures),'examples':failures[:16]}))
print('PHOTOREAL_UV_AUDIT_OK')
