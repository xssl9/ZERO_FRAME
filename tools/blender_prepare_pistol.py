"""Import pistol and soldier into separate authoring scenes; never clear existing scenes."""
import bpy
import json
from pathlib import Path

ROOT = Path(PROJECT_ROOT) if 'PROJECT_ROOT' in globals() else Path(__file__).resolve().parents[1]
assert not bpy.data.scenes.get('PistolUniform'), 'Authoring scene already exists'
scene = bpy.data.scenes.new('PistolUniform')
bpy.context.window.scene = scene
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/weapons/pistol/scene.gltf'))
pistol_objects = list(scene.objects)
print('PISTOL_OBJECTS', json.dumps([{
    'name': o.name, 'type': o.type,
    'vertices': len(o.data.vertices) if o.type == 'MESH' else None,
    'materials': [m.name for m in o.data.materials] if o.type == 'MESH' else [],
    'groups': [g.name for g in o.vertex_groups] if o.type == 'MESH' else [],
} for o in pistol_objects]))
print('PISTOL_ACTIONS', [(a.name, list(a.frame_range)) for a in bpy.data.actions])
reference = bpy.data.scenes.new('SoldierUniformReference')
bpy.context.window.scene = reference
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb'))
print('SOLDIER_OBJECTS', json.dumps([{
    'name': o.name, 'type': o.type,
    'vertices': len(o.data.vertices) if o.type == 'MESH' else None,
    'materials': [m.name for m in o.data.materials] if o.type == 'MESH' else [],
} for o in reference.objects]))
bpy.context.window.scene = scene
print('PISTOL_IMPORT_READY')
