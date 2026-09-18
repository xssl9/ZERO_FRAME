"""Run in the saved .blend to verify editable source and the packaged game asset.

blender --background assets/weapons/pistol/uniform/pistol_uniform.blend \
    --python-exit-code 1 --python tools/blender_verify_pistol_authoring.py
"""
import bpy
import json
import hashlib
import numpy as np
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(PROJECT_ROOT) if 'PROJECT_ROOT' in globals() else Path(__file__).resolve().parents[1]
asset = ROOT / 'assets/weapons/pistol'
original = json.loads((asset / 'scene.gltf').read_text())
uniform = json.loads((asset / 'pistol_uniform.gltf').read_text())
manifest = json.loads((asset / 'uniform/manifest.json').read_text())
for key in ('nodes', 'meshes', 'skins', 'animations', 'accessors', 'bufferViews', 'buffers', 'scenes', 'scene'):
    assert original.get(key) == uniform.get(key), key
assert original['materials'][1:] == uniform['materials'][1:]
assert hashlib.sha256((asset / 'scene.gltf').read_bytes()).hexdigest() == manifest['source_gltf_sha256']
assert hashlib.sha256((asset / 'scene.bin').read_bytes()).hexdigest() == manifest['shared_binary_sha256']
assert hashlib.sha256((ROOT / manifest['palette_reference']).read_bytes()).hexdigest() == manifest['reference_sha256']
for image in uniform['images']:
    assert (asset / unquote(image['uri'])).is_file(), image
scene = bpy.data.scenes['PistolUniform']
rig = scene.objects['Object_6']
clips = {strip.action.name for track in rig.animation_data.nla_tracks for strip in track.strips}
assert clips == {a['name'] for a in original['animations']}, clips
arms = scene.objects['Object_9']
assert len(arms.data.vertices) == 8193
assert any(mod.type == 'ARMATURE' and mod.object == rig for mod in arms.modifiers)
material = arms.data.materials[0]
assert material.name == 'SoldierUniformArms'
for obj in scene.objects:
    if obj.type != 'MESH':
        continue
    for mat in obj.data.materials:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                assert node.image.packed_file or Path(bpy.path.abspath(node.image.filepath)).is_file(), node.image.filepath
                # Opening a .blend loads image datablocks lazily. Force a real
                # disk read before checking, rather than only checking the path.
                if not node.image.packed_file:
                    node.image.reload()
                assert len(node.image.pixels) > 0 and node.image.has_data, node.image.name
albedo = bpy.data.images.load(str(asset / 'uniform/pistol_uniform_albedo.png'), check_existing=False)
pixels = np.array(albedo.pixels[:]).reshape(-1,4)
assert tuple(albedo.size) == (2048,2048)
assert np.max(np.abs(pixels[:,0]-pixels[:,1])) < .005, 'neutral charcoal, not sandy dye'
assert np.quantile(pixels[:,:3],.9) < .16, 'dark uniform palette'
assert pixels[:,:3].std() > .005, 'retain authored surface detail, not flat black'
print('AUTHORING_VERIFY_OK clips=', len(clips), 'vertices=', len(arms.data.vertices), 'palette_quantiles=', np.quantile(pixels[:,:3],[.1,.5,.9]).tolist())
