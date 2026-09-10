"""Executed INSIDE existing Blender via parking_blender_mcp.py, not standalone Python.
Full gameplay assembly with props. Keeps prior Blender scenes and opens the new one.
Procedural world PBR is reconstructed for authoring, not claimed pixel-identical.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix

WORK = Path('/home/tuxpc/game/ZERO_FRAME_backups/parking_full_rework_20260908')
DEST = WORK / 'parking_complete_baseline.blend'
NAME = 'ZERO_FRAME_Parking_FULL_REWORK'
assert not DEST.exists() and bpy.data.scenes.get(NAME) is None, 'Refusing to replace artist work'
manifest = json.loads((WORK / 'manifest.json').read_text())
previous = bpy.context.window.scene
scene = bpy.data.scenes.new(NAME)
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene['godot_source_sha256'] = manifest['scene_sha256']
scene['source_triangles'] = manifest['triangles']
scene['phase'] = 'COMPLETE_ASSEMBLY_IMPORTED_NOT_FINAL'
bpy.context.window.scene = scene
assert 'FINISHED' in bpy.ops.import_scene.gltf(filepath=str(WORK / 'assembly.glb'))
bpy.context.view_layer.update()
by_name = {obj.name: obj for obj in scene.objects}
assert all(record['name'] in by_name for record in manifest['meshes']), 'Missing export nodes'

collections = {}
for key, name in {'Garage': 'ENV_STRUCTURE', 'Cars': 'ENV_CARS', 'Props': 'ENV_PROPS',
                  'Paint': 'ENV_PAINT', 'FixtureDetails': 'ENV_FIXTURE_DETAILS',
                  'Lights': 'ENV_LIGHTS', 'Cameras': 'ENV_CAMERAS'}.items():
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    collections[key] = col
subcollections = {}

def child(group, name):
    key = (group, name)
    if key not in subcollections:
        col = bpy.data.collections.new(name)
        collections[group].children.link(col)
        subcollections[key] = col
    return subcollections[key]

# Blender world-space box-projected PBR. Godot shader-only terms (rain mask,
# whiteout normal blending, screen water, flash light) have no direct glTF form.
def world_material(obj, config):
    p = config['parameters']
    mat = bpy.data.materials.new('WORLD_PBR_' + obj.name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Metallic'].default_value = 0.0
    geometry = nodes.new('ShaderNodeNewGeometry')
    scale = nodes.new('ShaderNodeVectorMath')
    scale.operation = 'SCALE'
    scale.inputs['Scale'].default_value = p['texture_scale']
    links.new(geometry.outputs['Position'], scale.inputs[0])

    def image(path, vector, data=False):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(path, check_existing=True)
        if data:
            node.image.colorspace_settings.name = 'Non-Color'
        node.projection = 'BOX'
        node.projection_blend = 0.18
        links.new(vector, node.inputs['Vector'])
        return node

    albedo = image(p['albedo_texture'], scale.outputs['Vector'])
    arm = image(p['arm_texture'], scale.outputs['Vector'], True)
    rgb = nodes.new('ShaderNodeSeparateColor')
    links.new(arm.outputs['Color'], rgb.inputs[0])
    links.new(rgb.outputs['Green'], bsdf.inputs['Roughness'])
    color = albedo.outputs['Color']
    if p.get('variant_amount', 0) > 0 and p.get('variant_albedo_texture'):
        varscale = nodes.new('ShaderNodeVectorMath')
        varscale.operation = 'SCALE'
        varscale.inputs['Scale'].default_value = p['variant_scale']
        links.new(geometry.outputs['Position'], varscale.inputs[0])
        variant = image(p['variant_albedo_texture'], varscale.outputs['Vector'])
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 1.0 / p['variant_patch_size']
        noise.inputs['Detail'].default_value = 2.0
        links.new(geometry.outputs['Position'], noise.inputs['Vector'])
        amount = nodes.new('ShaderNodeMath')
        amount.operation = 'MULTIPLY'
        amount.inputs[1].default_value = p['variant_amount']
        links.new(noise.outputs['Fac'], amount.inputs[0])
        mix = nodes.new('ShaderNodeMixRGB')
        links.new(amount.outputs[0], mix.inputs[0])
        links.new(color, mix.inputs[1])
        links.new(variant.outputs['Color'], mix.inputs[2])
        color = mix.outputs[0]
    if p.get('unique_ao_texture') and p.get('unique_ao_strength', 0) > 0:
        ao = nodes.new('ShaderNodeTexImage')
        ao.image = bpy.data.images.load(p['unique_ao_texture'], check_existing=True)
        ao.image.colorspace_settings.name = 'Non-Color'
        mix = nodes.new('ShaderNodeMixRGB')
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = p['unique_ao_strength'] * p.get('unique_ao_albedo', 0.3)
        links.new(color, mix.inputs[1])
        links.new(ao.outputs['Color'], mix.inputs[2])
        color = mix.outputs[0]
    links.new(color, bsdf.inputs['Base Color'])
    # Small authoring-only geometric micro-bump; do not reinterpret an RGB normal
    # map as height or feed world box normals into a tangent-space normal node.
    micro = nodes.new('ShaderNodeTexNoise')
    micro.inputs['Scale'].default_value = 160.0
    micro.inputs['Detail'].default_value = 2.0
    links.new(geometry.outputs['Position'], micro.inputs['Vector'])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.16
    bump.inputs['Distance'].default_value = 0.001
    links.new(micro.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    obj.data.materials[config['surface']] = mat
    mat['godot_material_parameters'] = json.dumps(p)
    mat['authoring_approximation'] = 'world PBR preview; Godot retains original triplanar normal/weather shader'

max_error = 0.0
triangles = 0
for record in manifest['meshes']:
    obj = by_name[record['name']]
    assert obj.type == 'MESH', record['name']
    points = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
    points = [(p.x, p.z, -p.y) for p in points]
    for axis in range(3):
        max_error = max(max_error, abs(min(p[axis] for p in points) - record['bounds_low'][axis]),
                        abs(max(p[axis] for p in points) - record['bounds_high'][axis]))
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
    path = record['path'].split('/')
    group = record['group']
    destination = child(group, path[1]) if group in ('Cars', 'Props') else collections[group]
    if record['path'] == 'Garage/Ceiling':
        destination = child('Garage', 'CEILING_hide_for_overview')
    destination.objects.link(obj)
    for col in list(obj.users_collection):
        if col != destination:
            col.objects.unlink(obj)
    obj.name = record['name'] + '_' + path[-1]
    obj['godot_path'] = record['path']
    obj['transfer_id'] = record['name']
    for config in record['shaders']:
        if config['shader'].endswith('dev_grid.gdshader'):
            world_material(obj, config)
assert max_error < 0.003, max_error
assert triangles == manifest['triangles'], (triangles, manifest['triangles'])

# Explicit authoring lights. Existing out-of-bounds lamps are preserved with zero
# preview energy, not silently brought back into rooms they may have been removed from.
inactive = 0
for item in manifest['lights']:
    pos = item['transform'][9:12]
    name = item['name']
    active = -0.1 < pos[1] < 3.4 and item['visible']
    is_fixture = name.startswith(('Deck', 'Room', 'Corridor'))
    light = bpy.data.lights.new('LIGHT_' + name, 'AREA' if is_fixture else 'POINT')
    light.color = item['color'][:3]
    light.energy = (36.0 if is_fixture else item['energy'] * 8.0) if active else 0.0
    if is_fixture:
        light.shape = 'RECTANGLE'
        light.size = 1.65 if name.startswith('Deck') else 1.45
        light.size_y = 0.12
    else:
        light.shadow_soft_size = 0.12
    obj = bpy.data.objects.new(light.name, light)
    collections['Lights'].objects.link(obj)
    obj.location = (pos[0], -pos[2], pos[1])
    if name.startswith('Corridor'):
        obj.rotation_euler.z = math.pi * 0.5
    obj['godot_light'] = json.dumps(item)
    obj['authoring_photometry'] = 'approximate radiant watts, not calibrated Godot energy conversion'
    if not active:
        inactive += 1
        obj['inactive_reason'] = 'original source outside building; awaiting author decision'

world = bpy.data.worlds.new('Parking_InteriorWorld')
world.use_nodes = True
world.node_tree.nodes.get('Background').inputs['Color'].default_value = (0.28, 0.32, 0.40, 1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value = 0.04
scene.world = world
camera_data = bpy.data.cameras.new('Parking_Walkthrough')
camera_data.lens = 24.0
camera_data.clip_start = 0.05
camera_data.clip_end = 300.0
camera = bpy.data.objects.new('Parking_Walkthrough', camera_data)
collections['Cameras'].objects.link(camera)
camera.location = (-26, 2, 1.65)
camera.rotation_euler = (Vector((-10, 2, 1.45)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.preview_samples = 8
scene.cycles.use_denoising = True
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = 0.0
scene['phase'] = 'FULL_ASSEMBLY_READY_FOR_REWORK'
scene['transfer_meshes'] = len(manifest['meshes'])
scene['transfer_max_bounds_error_m'] = max_error

# Only the new scene, not unrelated open scenes. Keep the complete assembly ACTIVE.
bpy.data.libraries.write(str(DEST), {scene}, path_remap='ABSOLUTE', fake_user=True)
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        area.spaces.active.clip_end = 400
        area.spaces.active.shading.type = 'MATERIAL'
        area.spaces.active.shading.use_scene_lights = False
        area.spaces.active.shading.use_scene_world = False
        area.spaces.active.region_3d.view_perspective = 'CAMERA'
report = {'scene': scene.name, 'previous_scene_preserved': previous.name, 'mesh_count': len(manifest['meshes']),
          'triangles': triangles, 'max_bounds_error_m': max_error, 'lights': len(manifest['lights']),
          'inactive_outlier_lights': inactive, 'groups': manifest['counts'], 'blend': str(DEST)}
(WORK / 'blender_transfer_report.json').write_text(json.dumps(report, indent=2) + '\n')
print('FULL_PARKING_OPENED', json.dumps(report))
