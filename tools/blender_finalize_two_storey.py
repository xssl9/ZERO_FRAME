"""Decode real rendered PNGs, preserve the reference as reference-only and save UI view."""
import bpy,json
import numpy as np
from pathlib import Path
s=bpy.context.scene;work=Path(s['two_storey_work'])
status=json.loads((work/'render_status.json').read_text())
assert status['status']=='COMPLETE' and len(status['completed'])==3,status
stats=[]
for shot in status['completed']:
 path=Path(shot['path']);image=bpy.data.images.load(str(path),check_existing=False)
 # Blender loads file pixels lazily: access size/pixels before checking has_data.
 size=tuple(image.size)
 pixels=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pixels)
 assert image.has_data and size==(1280,720) and pixels.size==1280*720*4,str(path)
 pixels=pixels.reshape(-1,4);rgb=pixels[:,:3]
 assert np.isfinite(rgb).all()
 lum=rgb@np.array([.2126,.7152,.0722])
 row={'file':str(path),'size':list(image.size),'mean_luminance_linear':float(lum.mean()),'stddev_linear':float(lum.std()),
      'near_black_fraction':float(np.mean(lum<.001)),'near_white_fraction':float(np.mean(lum>.99))}
 assert lum.std()>.01 and lum.max()>.1,('unexpected_uniform_or_dark_render',row)
 stats.append(row);bpy.data.images.remove(image)
# No material/compositor/image plane uses this image. It is kept in the Image
# Editor image selector solely so the developer can compare it to the render.
ref=bpy.data.images.load(s['reference_image'],check_existing=True);ref.name='REFERENCE_ONLY_ChatGPT_08_Sept';ref.use_fake_user=True;ref.pack()
ref['purpose']='Visual reference only; never assigned as a texture'
s['reference_image_datablock']=ref.name
s.camera=bpy.data.objects['REVIEW_Breach']
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  space=area.spaces.active;space.region_3d.view_perspective='CAMERA';space.clip_end=300
  space.shading.use_scene_lights=True;space.shading.use_scene_world=True
report={'render_status':'COMPLETE','pixel_checks':'PASS','renders':stats,'reference_visual_match':'UNVERIFIED',
 'visual_acceptance':'PENDING_USER_REVIEW','original_scene_snapshot':str(work/'before.blend'),'working_blend':str(work/'parking_two_storey.blend'),
 'scope':'Blender authoring only; original Godot files, collisions and exports unchanged'}
(work/'final_report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
assert Path(bpy.data.filepath).stat().st_size>100000
print('TWO_STOREY_FINAL_SAVED',json.dumps(report))
