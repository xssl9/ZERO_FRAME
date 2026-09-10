"""Render matching before/after views asynchronously through the existing Blender MCP."""
import bpy, json, traceback
from pathlib import Path

s = bpy.context.scene
work = Path(s['photoreal_finish_work'])
phase = 'after' if s.get('photoreal_finish_applied') else 'before'
folder = work / phase
folder.mkdir(exist_ok=False)
assert not bpy.app.is_job_running('RENDER')
shots = ['GP_Overview', 'REVIEW_UpperDeck', 'REVIEW_RestoredDuct']
state = {'status': 'SCHEDULED', 'phase': phase, 'completed': [], 'samples': 48, 'resolution': [1280, 720]}
previous = {'camera': s.camera, 'engine': s.render.engine, 'x': s.render.resolution_x,
    'y': s.render.resolution_y, 'percentage': s.render.resolution_percentage, 'path': s.render.filepath,
    'samples': s.cycles.samples, 'device': s.cycles.device, 'denoise': s.cycles.use_denoising,
    'format': s.render.image_settings.file_format, 'mode': s.render.image_settings.color_mode}
s.render.engine = 'CYCLES'
s.cycles.samples = 48
s.cycles.use_denoising = True
s.render.resolution_x = 1280
s.render.resolution_y = 720
s.render.resolution_percentage = 100
s.render.image_settings.file_format = 'PNG'
s.render.image_settings.color_mode = 'RGB'
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    devices = [d for d in prefs.devices if d.type == 'OPTIX']
    assert devices, 'No OptiX device'
    for d in prefs.devices:
        d.use = d.type == 'OPTIX'
    s.cycles.device = 'GPU'
    state['device'] = ', '.join(d.name for d in devices)
except Exception as error:
    s.cycles.device = 'CPU'
    state['device'] = 'CPU'
    state['gpu_setup_error'] = str(error)
status_path = folder / 'status.json'
status_path.write_text(json.dumps(state, indent=2))

def make_callback(scene, work_folder, status, status_file, views, saved):
    def restore():
        scene.camera = saved['camera']
        scene.render.engine = saved['engine']
        scene.render.resolution_x = saved['x']
        scene.render.resolution_y = saved['y']
        scene.render.resolution_percentage = saved['percentage']
        scene.render.filepath = saved['path']
        scene.cycles.samples = saved['samples']
        scene.cycles.device = saved['device']
        scene.cycles.use_denoising = saved['denoise']
        scene.render.image_settings.file_format = saved['format']
        scene.render.image_settings.color_mode = saved['mode']
    def step():
        try:
            index = len(status['completed'])
            if index == len(views):
                status['status'] = 'COMPLETE'
                restore()
                status_file.write_text(json.dumps(status, indent=2))
                return None
            name = views[index]
            status['status'] = 'RENDERING'
            status['camera'] = name
            status_file.write_text(json.dumps(status, indent=2))
            scene.camera = scene.objects[name]
            scene.render.filepath = str(work_folder / (name + '.png'))
            assert 'FINISHED' in bpy.ops.render.render(write_still=True)
            path = Path(scene.render.filepath)
            assert path.is_file() and path.stat().st_size > 10000
            status['completed'].append({'camera': name, 'path': str(path), 'bytes': path.stat().st_size})
            status_file.write_text(json.dumps(status, indent=2))
            return 0.5
        except Exception:
            status['status'] = 'FAILED'
            status['error'] = traceback.format_exc()
            restore()
            status_file.write_text(json.dumps(status, indent=2))
            return None
    return step

bpy.app.timers.register(make_callback(s, folder, state, status_path, shots, previous), first_interval=1.0)
print('PHOTOREAL_RENDER_SCHEDULED', json.dumps(state))
