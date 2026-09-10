"""Render the checked scene asynchronously in the existing Blender via MCP.
Status is written to the work directory; scheduled does NOT mean rendered.
"""
import bpy,json,traceback
from pathlib import Path
s=bpy.context.scene;work=Path(s['two_storey_work'])
assert s.get('two_storey_validation')=='PASS'
statuspath=work/'render_status.json'
revision=int(s.get('render_revision',1))
if statuspath.exists():
 assert s.get('render_needs_refresh') and json.loads(statuspath.read_text())['status']=='COMPLETE', 'Inspect prior render state before starting again'
 archive=work/('render_status_before_revision_%d.json'%revision)
 assert not archive.exists()
 archive.write_text(statuspath.read_text())
 s['render_needs_refresh']=False
renderdir=work/('renders' if revision==1 else 'renders_v%d'%revision);renderdir.mkdir(exist_ok=True)
shots=[('REVIEW_Breach','01_breach'),('REVIEW_UpperDeck','02_upper_deck'),('REVIEW_Ramp','03_access_ramp')]
state={'status':'SCHEDULED','completed':[],'engine':'CYCLES','device':'CPU','samples':64,'resolution':[1280,720]}
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 devices=[d for d in prefs.devices if d.type=='OPTIX']
 if devices:
  for d in prefs.devices:d.use=d.type=='OPTIX'
  s.cycles.device='GPU';state['device']=', '.join(d.name for d in devices)
 else:s.cycles.device='CPU'
except Exception as error:
 state['gpu_setup_error']=str(error);s.cycles.device='CPU'
s.render.engine='CYCLES';s.cycles.samples=64;s.cycles.use_denoising=True
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB'
# These caps overlap the existing upper perimeter where it is intact. Set them
# just outboard to avoid coincident surfaces, keeping the inner original wall.
if not s.get('upper_closure_offsets'):
 for name,axis,shift in (('L02_EastPerimeterClosure',0,.20),('L02_NorthEntranceClosure',1,.15)):
  ob=s.objects[name]
  for v in ob.data.vertices:v.co[axis]+=shift
  ob.data.update()
 s['upper_closure_offsets']=True
s.camera=bpy.data.objects['REVIEW_Breach'];s.render.filepath=str(renderdir/'01_breach.png')
bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
statuspath.write_text(json.dumps(state,indent=2))

def render_next():
 try:
  i=len(state['completed'])
  if i>=len(shots):
   state['status']='COMPLETE';s.camera=bpy.data.objects['REVIEW_Breach'];s.render.filepath=str(renderdir/'01_breach.png')
   s['two_storey_phase']='RENDERED_TECHNICALLY_CHECKED_VISUAL_APPROVAL_PENDING'
   bpy.ops.wm.save_as_mainfile(filepath=str(work/'parking_two_storey.blend'))
   statuspath.write_text(json.dumps(state,indent=2))
   return None
  name,filename=shots[i];state['status']='RENDERING';state['current']=name;statuspath.write_text(json.dumps(state,indent=2))
  s.camera=bpy.data.objects[name];s.render.filepath=str(renderdir/(filename+'.png'))
  assert 'FINISHED' in bpy.ops.render.render(write_still=True)
  path=Path(s.render.filepath);assert path.is_file() and path.stat().st_size>10000
  state['completed'].append({'camera':name,'path':str(path),'bytes':path.stat().st_size})
  statuspath.write_text(json.dumps(state,indent=2))
  return 1.0
 except Exception:
  state['status']='FAILED';state['error']=traceback.format_exc();statuspath.write_text(json.dumps(state,indent=2))
  return None
bpy.app.timers.register(render_next,first_interval=2.0)
print('TWO_STOREY_RENDER_SCHEDULED',json.dumps(state))
