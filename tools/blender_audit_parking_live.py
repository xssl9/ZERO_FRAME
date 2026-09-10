"""Read-only inspection of the live authoring scene via local MCP."""
import bpy
import json
from pathlib import Path
from collections import Counter
report = {'active_scene': bpy.context.scene.name, 'file': bpy.data.filepath, 'dirty': bpy.data.is_dirty,
          'scenes': [{'name': s.name, 'objects': len(s.objects), 'phase': s.get('phase')} for s in bpy.data.scenes]}
scene = bpy.data.scenes.get('ZERO_FRAME_Parking_FULL_REWORK')
if scene:
    report['groups'] = {c.name: len(c.all_objects) for c in scene.collection.children}
    report['source_groups'] = dict(Counter(o.get('godot_path', '').split('/')[0] for o in scene.objects if o.get('transfer_id')))
    report['structure'] = [{'name': o.name, 'path': o.get('godot_path'), 'dimensions': list(o.dimensions),
                            'materials': [m.name if m else None for m in o.data.materials],
                            'modifiers': [m.type for m in o.modifiers]}
                           for o in scene.objects if o.type == 'MESH' and o.get('godot_path', '').startswith('Garage/')]
    report['camera'] = {'name': scene.camera.name, 'position': list(scene.camera.location)} if scene.camera else None
    report['lights'] = [{'name': o.name, 'type': o.data.type, 'energy': o.data.energy, 'position': list(o.location)} for o in scene.objects if o.type=='LIGHT']
print('PARKING_LIVE_AUDIT', json.dumps(report))
