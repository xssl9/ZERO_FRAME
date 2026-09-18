"""Rebuild the game wrapper around the live export, retaining player/environment settings.
Only the parking rework scene is changed. Old geometry/material resources are
removed by dependency closure, not hidden while retaining their stale colliders.
Area -> spot light conversion is explicitly approximate (Godot has no area light).
"""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / 'scenes/levels/parking_garage_rework.tscn'
ASSETS = ROOT / 'assets/environment/parking_rework'
report = json.loads((ASSETS / 'live_export.json').read_text())
assert hashlib.sha256((ASSETS / 'assembly.glb').read_bytes()).hexdigest() == report['glb_sha256']
original = SCENE.read_text()
blocks = re.split(r'(?=^\[(?:ext_resource|sub_resource|node) )', original, flags=re.M)
resources = {}
nodes = []
kept_names = {'ParkingGarage', 'PhotorealEnvironment', 'Reflections', 'SpawnPoint3D', 'WetGround', 'Player', 'LightmapGI'}
for block in blocks[1:]:
    header = block.splitlines()[0]
    if not header.startswith('[node '):
        kind = 'ExtResource' if header.startswith('[ext_resource') else 'SubResource'
        resources[(kind, re.search(r'\bid="([^"]+)"', header)[1])] = block
        continue
    name = re.search(r'name="([^"]+)"', header)[1]
    parent = re.search(r'parent="([^"]+)"', header)
    if (name in kept_names and (parent is None or parent[1] == '.')) or (parent and parent[1].split('/')[0] == 'Reflections'):
        nodes.append(block)

# Keep the existing water system as an optional override, but not the old fullscreen
# flooded-floor look on top of the author's now dry PBR surfaces and local decals.
nodes = [b.replace('standing_water = 0.9', 'standing_water = 0.0') for b in nodes]
assembly = '[node name="Garage" parent="." instance=ExtResource("1_garage")]\n\n'
nodes.insert(2, assembly)
resources[('ExtResource', '1_garage')] = '[ext_resource type="PackedScene" path="res://assets/environment/parking_rework/assembly.glb" id="1_garage"]\n\n'

lights = ['[node name="Lights" type="Node3D" parent="."]\n\n']
for item in report['lights']:
    assert item['type'] in {'AREA', 'POINT'}, item
    area = item['type'] == 'AREA'
    daylight = item['name'].startswith('GP_')
    kind = 'SpotLight3D' if area else 'OmniLight3D'
    energy = item['energy_watts'] * (3.4 / 125.0 if area else 1.0 / 8.0)
    lights.append('[node name=%s type="%s" parent="Lights"]\n' % (json.dumps(item['name']), kind))
    # Blender report stores column vectors. Godot's text Transform3D stores
    # the 3x3 basis row-major (then origin), unlike its Basis-vector constructor.
    # Writing columns verbatim transposes rotation: downlights point UP.
    source_transform = item['transform']
    scene_transform = [source_transform[i] for i in (0, 3, 6, 1, 4, 7, 2, 5, 8, 9, 10, 11)]
    lights.append('transform = Transform3D(%s)\n' % ', '.join('%.9g' % v for v in scene_transform))
    lights.append('light_color = Color(%s, 1)\n' % ', '.join('%.9g' % v for v in item['color']))
    lights.append('light_energy = %.9g\nshadow_enabled = true\nshadow_bias = 0.045\n' % energy)
    lights.append('metadata/blender_energy_watts = %.9g\n' % item['energy_watts'])
    lights.append('metadata/blender_light_type = %s\n' % json.dumps(item['type']))
    if area:
        lights.append('spot_range = %s\nspot_angle = 85.0\nspot_attenuation = 1.5\n' % ('25.0' if daylight else '13.0'))
    else:
        lights.append('omni_range = 5.0\nomni_attenuation = 1.5\n')
    lights.append('\n')
nodes.insert(3, ''.join(lights))

# Drop every old car, prop, marking, material override, and their unused resources.
needed = set()
def dependencies(text):
    for kind, identifier in re.findall(r'(ExtResource|SubResource)\("([^"]+)"\)', text):
        key = (kind, identifier)
        if key not in needed:
            needed.add(key)
            dependencies(resources[key])
dependencies(''.join(nodes))
result = '[gd_scene format=3]\n\n' + ''.join(block for key, block in resources.items() if key in needed) + ''.join(nodes)
assert 'parent="Cars"' not in result and 'parent="Props"' not in result and 'parent="Paint"' not in result
assert 'solid_mesh_names' not in result and 'Material_floor' not in result
SCENE.write_text(result)
print('PARKING_WRAPPER_UPDATED lights=%d resources=%d' % (len(report['lights']), len(needed)))
