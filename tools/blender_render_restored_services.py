"""Render the real scene under its unchanged lighting; report completion separately."""
import bpy,json,traceback
import numpy as np
from pathlib import Path
from mathutils import Vector
s=bpy.context.scene;work=Path(s['prop_rollback_work'])
assert s.get('restored_services_validation')=='PASS'
statusfile=work/'render_status.json';assert not statusfile.exists()
renderdir=work/'renders';renderdir.mkdir(exist_ok=True)
col=bpy.data.collections.new('REVIEW_RestoredServices');s.collection.children.link(col)
for name,pos,target in (
 ('REVIEW_RestoredPipes',(-12.5,-13.4,1.7),(-9,-10.7,2.45)),
 ('REVIEW_RestoredDuct',(-12,-9.6,1.7),(-8.7,-7,2.42))):
 data=bpy.data.cameras.new(name);data.lens=35;data.clip_start=.03;data.clip_end=200
 ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
shots=[('GP_Overview','01_restored_layout'),('REVIEW_RestoredPipes','02_pipe_materials'),('REVIEW_RestoredDuct','03_ventilation_materials')]
for name,_ in shots:
 cam=s.objects[name];direction=cam.matrix_world.to_quaternion()@Vector((0,0,-1))
 result=s.ray_cast(dg,cam.matrix_world.translation,direction,distance=.3)
 assert not result[0],('camera_occluded',name,result[4].name if result[0] else None)
state={'status':'SCHEDULED','completed':[],'device':'CPU','samples':64,'resolution':[1280,720],'lighting_changed':False,'visual_approval':'PENDING'}
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 gpu=[d for d in prefs.devices if d.type=='OPTIX']
 if gpu:
  for d in prefs.devices:d.use=d.type=='OPTIX'
  s.cycles.device='GPU';state['device']=', '.join(d.name for d in gpu)
 else:s.cycles.device='CPU'
except Exception as error:
 s.cycles.device='CPU';state['gpu_error']=str(error)
s.render.engine='CYCLES';s.cycles.samples=64;s.cycles.use_denoising=True
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB'
statusfile.write_text(json.dumps(state,indent=2))

def step():
 try:
  i=len(state['completed'])
  if i==len(shots):
   s.camera=s.objects['GP_Overview'];s.render.filepath=str(renderdir/'01_restored_layout.png')
   s['gameplay_phase']='PROPS_ROLLED_BACK_SERVICES_RENDERED_VISUAL_REVIEW_PENDING'
   bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_restored_materials.blend'))
   state['status']='COMPLETE';statusfile.write_text(json.dumps(state,indent=2));return None
  name,filename=shots[i];state['status']='RENDERING';state['current']=name;statusfile.write_text(json.dumps(state,indent=2))
  s.camera=s.objects[name];s.render.filepath=str(renderdir/(filename+'.png'))
  assert 'FINISHED' in bpy.ops.render.render(write_still=True)
  path=Path(s.render.filepath);assert path.is_file() and path.stat().st_size>10000
  image=bpy.data.images.load(str(path),check_existing=False)
  size=tuple(image.size);data=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(data)
  assert image.has_data and size==(1280,720) and data.size==1280*720*4
  rgb=data.reshape(-1,4)[:,:3];assert np.isfinite(rgb).all()
  lum=rgb@np.array([.2126,.7152,.0722]);assert lum.std()>.01 and lum.max()>.1,('flat_or_dark_render',filename)
  state['completed'].append({'file':str(path),'bytes':path.stat().st_size,'mean_luminance_linear':float(lum.mean()),'stddev_linear':float(lum.std())})
  bpy.data.images.remove(image);statusfile.write_text(json.dumps(state,indent=2));return 1.0
 except Exception:
  state['status']='FAILED';state['error']=traceback.format_exc();statusfile.write_text(json.dumps(state,indent=2));return None
bpy.app.timers.register(step,first_interval=2)
print('RESTORED_SERVICES_RENDER_SCHEDULED',json.dumps(state))
