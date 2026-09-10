"""Stable metric tangent coordinates for thin imported bevel/Boolean polygons.
Only reprojects UVs of degenerate islands. Original mesh vertices and indices stay intact.
"""
import bpy, json
import numpy as np
from pathlib import Path
s=bpy.context.scene
work=Path(s['photoreal_finish_work'])
report=json.loads((work/'finish_report.json').read_text())
repairs=[]
for name in report['objects']:
    ob=s.objects[name]
    uv=ob.data.uv_layers['PF_MetricSurface']
    ob.data.calc_loop_triangles()
    affected=set()
    for tri in ob.data.loop_triangles:
        if tri.area<1e-10: continue
        a,b,c=[uv.data[i].uv for i in tri.loops]
        det=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
        if abs(det)<=1e-12: affected.add(tri.polygon_index)
    matrix=np.array([list(row) for row in ob.matrix_world],dtype=np.float64)
    for index in affected:
        face=ob.data.polygons[index]
        # Transform relative coordinates in float64. World-space float32 rounding
        # at +/-30 m erased sub-micron bevel differences before UV assignment.
        local=np.array([list(ob.data.vertices[ob.data.loops[i].vertex_index].co) for i in face.loop_indices],dtype=np.float64)
        points=local@matrix[:3,:3].T
        points-=points.mean(axis=0)
        _,_,basis=np.linalg.svd(points,full_matrices=False)
        coordinates=points@basis[:2].T
        for loop,co in zip(face.loop_indices,coordinates): uv.data[loop].uv=tuple(co)
        repairs.append({'object':name,'polygon':index,'method':'face-local metric SVD projection, float64 transform'})
    ob.data.update()
(work/'uv_precision_report.json').write_text(json.dumps({'reprojected_polygons':len(repairs),'repairs':repairs},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_photoreal.blend'))
print('PHOTOREAL_UV_PRECISION_OK',json.dumps({'polygons':len(repairs)}))
