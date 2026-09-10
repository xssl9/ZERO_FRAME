#!/usr/bin/env python3
"""Prepare measured rework layout or create a separate playable scene, never overwrite base.
Run without arguments before Blender, then --integrate after the detail GLB exists.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
from blockout_boxes import boxes

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT.parent / 'ZERO_FRAME_backups/parking_full_rework_20260908'
SOURCE = ROOT / 'scenes/levels/parking_garage.tscn'
DEST = ROOT / 'scenes/levels/parking_garage_rework.tscn'
ASSET = ROOT / 'assets/environment/parking_rework/architectural_rework.glb'
manifest = json.loads((WORK / 'manifest.json').read_text())
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == manifest['scene_sha256'], 'Base scene changed; refresh source audit'

if '--integrate' in sys.argv:
    assert ASSET.is_file() and not DEST.exists(), 'Missing export or refusing scene overwrite'
    text = SOURCE.read_text()
    # New scene needs its own UID, not the base scene's identity.
    text = re.sub(r'^\[gd_scene[^\n]+\]', '[gd_scene format=3]', text, count=1)
    insert = '[ext_resource type="PackedScene" path="res://assets/environment/parking_rework/architectural_rework.glb" id="49_rework"]\n\n'
    text = text.replace('[sub_resource type="Environment" id="Environment_garage"]', insert + '[sub_resource type="Environment" id="Environment_garage"]', 1)
    text = text.replace('[node name="Lights" type="Node3D" parent="."', '[node name="ArchitecturalRework" parent="." instance=ExtResource("49_rework")]\n\n[node name="Lights" type="Node3D" parent="."', 1)
    # Remove stylistic neon fill ONLY in the new variant; preserve 11 displaced
    # authored lights and all functional tube lights until the user clarifies them.
    for name in ('NeonAccent', 'NeonAccent2'):
        pattern = r'(\[node name="' + name + r'"[^\n]+\]\n)([^\[]*)'
        match = re.search(pattern, text)
        assert match
        body, n = re.subn(r'^light_energy = [^\n]+', 'light_energy = 0.0', match[2], count=1, flags=re.M)
        assert n == 1
        text = text[:match.start(2)] + body + text[match.end(2):]
    # Smaller secondary patches keep the existing high-density PBR base; localized
    # new stains supply uniqueness instead of adding global random dirt everywhere.
    for material in ('floor', 'concrete', 'plaster'):
        pattern = r'(\[sub_resource type="ShaderMaterial" id="Material_' + material + r'"\]\n)([^\[]*)'
        match = re.search(pattern, text)
        assert match
        body = re.sub(r'^shader_parameter/variant_amount = [^\n]+', 'shader_parameter/variant_amount = 0.28', match[2], flags=re.M)
        text = text[:match.start(2)] + body + text[match.end(2):]
    DEST.write_text(text)
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == manifest['scene_sha256']
    print('PARKING_REWORK_SCENE_CREATED', DEST)
else:
    output = WORK / 'rework_layout.json'
    assert not output.exists(), 'Refusing layout overwrite'
    found = boxes(ROOT / 'assets/environment/parking/parking_garage.gltf')
    pillars = [b for b in found if b.mesh == 'Walls_Concrete' and .7 < b.size[0] < 1 and .7 < b.size[2] < 1 and b.size[1] > 2]
    cars = {}
    for item in manifest['meshes']:
        if item['group'] == 'Cars':
            name = item['path'].split('/')[1]
            if name not in cars:
                cars[name] = [list(item['bounds_low']), list(item['bounds_high'])]
            else:
                for i in range(3):
                    cars[name][0][i] = min(cars[name][0][i], item['bounds_low'][i])
                    cars[name][1][i] = max(cars[name][1][i], item['bounds_high'][i])
    plan = {'pillars': [{'centre': [(b.low[i]+b.high[i])/2 for i in range(3)], 'size': list(b.size)} for b in pillars],
            'cars': cars, 'source_sha256': manifest['scene_sha256'],
            'service_runs': [{'z': 11.0, 'y': 2.48, 'radius': .096}, {'z': 10.5, 'y': 2.48, 'radius': .068}, {'z': -9.5, 'y': 2.48, 'radius': .115}],
            'duct': {'centre_y': 2.4, 'centre_z': -3.5, 'height': .45, 'width': .7}}
    output.write_text(json.dumps(plan, indent=2)+'\n')
    print('REWORK_LAYOUT_READY pillars=',len(pillars),'cars=',len(cars))
