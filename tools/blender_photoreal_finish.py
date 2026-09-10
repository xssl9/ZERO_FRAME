"""Repair actual architectural PBR response without moving/remeshing the live parking.
Run through Blender MCP after checkpoint and before renders complete. No original saves.
"""
import bpy, json, math, hashlib
from pathlib import Path
from mathutils import Vector

s = bpy.context.scene
work = Path(s['photoreal_finish_work'])
assert not s.get('photoreal_finish_applied'), 'Already applied; do not stack the pass'
assert json.loads((work / 'before/status.json').read_text())['status'] == 'COMPLETE'
assert not bpy.app.is_job_running('RENDER')
root = Path('/home/tuxpc/game/ZERO_FRAME/assets/polyhaven/textures')
UV_NAME = 'PF_MetricSurface'

def structural(m):
    return m and ('WORLD_PBR_' in m.name or 'L02_' in m.name) and m.use_nodes and any(
        n.type == 'TEX_IMAGE' and n.image and '_diff_2k' in n.image.name for n in m.node_tree.nodes)

# Resolve effective object material overrides, not just the underlying mesh slots.
targets = [(o, [slot.material for slot in o.material_slots]) for o in s.objects
           if o.type == 'MESH' and o.visible_get() and not o.hide_render
           and any(structural(slot.material) for slot in o.material_slots)]
assert targets, 'No actual architectural materials found'
for o, materials in targets:
    for m in materials:
        if not structural(m): continue
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and '_diff_2k' in n.image.name:
                slug = n.image.name.split('_diff_2k')[0]
                for suffix in ('nor_gl', 'arm'):
                    assert (root / slug / (slug + '_' + suffix + '_2k.jpg')).is_file(), slug

copies = {}
records = []

def image_node(nodes, links, slug, suffix, vector_socket):
    path = root / slug / (slug + '_' + suffix + '_2k.jpg')
    im = bpy.data.images.load(str(path), check_existing=True)
    im.colorspace_settings.name = 'Non-Color'
    # Blender loads image pixels lazily; querying dimensions forces the real decode.
    dimensions = tuple(im.size)
    assert im.has_data and min(dimensions) >= 2048, (str(path), dimensions, im.has_data)
    if not im.packed_file: im.pack()
    n = nodes.new('ShaderNodeTexImage')
    n.name = 'PF_' + slug + '_' + suffix
    n.image = im
    n.extension = 'REPEAT'
    links.new(vector_socket, n.inputs['Vector'])
    return n

def repair(source):
    if source in copies: return copies[source]
    m = source.copy()
    m.name = 'PF_' + source.name
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bs = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    uv = nodes.new('ShaderNodeUVMap')
    uv.name = 'PF_MetricUV'
    uv.uv_map = UV_NAME
    photos = [n for n in nodes if n.type == 'TEX_IMAGE' and n.image and '_diff_2k' in n.image.name]
    # Existing triplanar sources use one metric scale node per texture layer. Keep
    # scale and world-space patch/dust masks; only give mapped channels a real tangent basis.
    vectors = {}
    for photo in photos:
        assert photo.inputs['Vector'].is_linked
        old = photo.inputs['Vector'].links[0].from_node
        assert old.type == 'VECT_MATH' and old.operation == 'SCALE', old.name
        if old not in vectors:
            mapped = nodes.new('ShaderNodeVectorMath')
            mapped.name = 'PF_' + old.name
            mapped.operation = 'SCALE'
            mapped.inputs[3].default_value = old.inputs[3].default_value
            links.new(uv.outputs['UV'], mapped.inputs[0])
            vectors[old] = mapped.outputs['Vector']
        for tex in list(nodes):
            if tex.type == 'TEX_IMAGE' and tex.inputs['Vector'].is_linked and tex.inputs['Vector'].links[0].from_node == old:
                tex.projection = 'FLAT'
                links.new(vectors[old], tex.inputs['Vector'])
    normals, roughness = [], []
    for photo in photos:
        slug = photo.image.name.split('_diff_2k')[0]
        vector = photo.inputs['Vector'].links[0].from_socket
        tex = image_node(nodes, links, slug, 'nor_gl', vector)
        normal = nodes.new('ShaderNodeNormalMap')
        normal.name = 'PF_Normal_' + slug
        normal.space = 'TANGENT'
        normal.uv_map = UV_NAME
        normal.inputs['Strength'].default_value = 0.8
        links.new(tex.outputs['Color'], normal.inputs['Color'])
        normals.append(normal.outputs['Normal'])
        arm = image_node(nodes, links, slug, 'arm', vector)
        sep = nodes.new('ShaderNodeSeparateColor')
        links.new(arm.outputs['Color'], sep.inputs[0])
        roughness.append(sep.outputs['Green'])
    normal_output, rough_output = normals[0], roughness[0]
    if len(photos) == 2:
        # The same authored patch mask must control color, roughness and normals.
        blend = next(n for n in nodes if n.type == 'MIX_RGB' and n.blend_type == 'MIX'
                     and n.inputs[1].is_linked and n.inputs[1].links[0].from_node == photos[0]
                     and n.inputs[2].is_linked and n.inputs[2].links[0].from_node == photos[1])
        for outputs, label in ((normals, 'Normals'), (roughness, 'Roughness')):
            mixed = nodes.new('ShaderNodeMixRGB')
            mixed.name = 'PF_Patch' + label
            mixed.use_clamp = False
            if blend.inputs[0].is_linked:
                links.new(blend.inputs[0].links[0].from_socket, mixed.inputs[0])
            else:
                mixed.inputs[0].default_value = blend.inputs[0].default_value
            links.new(outputs[0], mixed.inputs[1])
            links.new(outputs[1], mixed.inputs[2])
            if label == 'Normals': normal_output = mixed.outputs[0]
            else: rough_output = mixed.outputs[0]
    assert len(photos) in (1, 2)
    normalize = nodes.new('ShaderNodeVectorMath')
    normalize.name = 'PF_Normalize'
    normalize.operation = 'NORMALIZE'
    links.new(normal_output, normalize.inputs[0])
    # Retain the subtle authored pore bump as micro-detail, not the entire relief.
    bump = bs.inputs['Normal'].links[0].from_node if bs.inputs['Normal'].is_linked else None
    if bump and bump.type == 'BUMP':
        bump.inputs['Strength'].default_value = 0.08
        bump.inputs['Distance'].default_value = 0.0004
        links.new(normalize.outputs['Vector'], bump.inputs['Normal'])
    else:
        links.new(normalize.outputs['Vector'], bs.inputs['Normal'])
    links.new(rough_output, bs.inputs['Roughness'])
    # Building surfaces are dielectric. Existing color, stains and local AO remain.
    assert not bs.inputs['Metallic'].is_linked
    bs.inputs['Metallic'].default_value = 0.0
    # Pin old baked AO to the original UV map; a new active UV must not reinterpret it.
    for n in list(nodes):
        if n.type == 'TEX_IMAGE' and n.image and '_ao.png' in n.image.name:
            ao_uv = nodes.new('ShaderNodeUVMap')
            ao_uv.name = 'PF_OriginalAO_UV'
            ao_uv.uv_map = 'UVMap'
            links.new(ao_uv.outputs['UV'], n.inputs['Vector'])
    m['photoreal_finish_source'] = source.name
    m['photoreal_finish_uv'] = UV_NAME
    m['photoreal_finish_normal_maps'] = len(normals)
    copies[source] = m
    records.append({'source': source.name, 'material': m.name, 'normal_maps': len(normals),
                    'texture_layers': [p.image.name for p in photos]})
    return m

# Prepare materials before changing any object. An interrupted preparation leaves
# only unused copies; never stack this pass on a partially assigned scene.
assert not any(slot.material and slot.material.get('photoreal_finish_source')
               for ob in s.objects if ob.type == 'MESH' for slot in ob.material_slots), 'Inspect partially applied state'
for unused in list(bpy.data.materials):
    if unused.name == 'PF_WEAR_WORLD_PBR_ZF_0003_Floor_Annex' and unused.users == 0 and not unused.get('photoreal_finish_source'):
        bpy.data.materials.remove(unused)
for ob, effective_materials in targets:
    for material in effective_materials:
        if structural(material): repair(material)

for ob, effective_materials in targets:
    # Data copies protect other scenes and linked instances; vertex/index topology stays identical.
    ob.data = ob.data.copy()
    for slot, material in zip(ob.material_slots, effective_materials):
        slot.material = repair(material) if structural(material) else material
    uv = ob.data.uv_layers.get(UV_NAME) or ob.data.uv_layers.new(name=UV_NAME)
    normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
    for face in ob.data.polygons:
        normal = (normal_matrix @ face.normal).normalized()
        axis = max(range(3), key=lambda i: abs(normal[i]))
        a, b, sign = ((1, 2, 1 if normal.x >= 0 else -1),
                      (0, 2, -1 if normal.y >= 0 else 1),
                      (0, 1, 1 if normal.z >= 0 else -1))[axis]
        for index in face.loop_indices:
            p = ob.matrix_world @ ob.data.vertices[ob.data.loops[index].vertex_index].co
            uv.data[index].uv = (p[a] * sign, p[b])
    ob.data.update()

# Slight circuit-correlated variation, not flicker or colored accent lighting. Keep
# all fixtures, light transforms, daylight portals and gameplay visibility intact.
light_records = []
for ob in s.objects:
    if ob.type != 'LIGHT' or 'LIGHT_Deck' not in ob.name: continue
    old_energy, old_color = ob.data.energy, list(ob.data.color)
    ob.data = ob.data.copy()
    column = int(round((ob.location.x + 26.0) / 7.4))
    upper = ob.location.z > 4
    factors = (0.94, 1.02, 0.98, 1.06, 0.97, 1.03, 0.95, 1.0)
    ob.data.energy = old_energy * factors[column % len(factors)]
    ob.data.color = (1.0, 0.965, 0.90) if not upper else (0.94, 0.965, 1.0)
    light_records.append({'name': ob.name, 'before_energy': old_energy, 'after_energy': ob.data.energy,
                          'before_color': old_color, 'after_color': list(ob.data.color)})
assert len(light_records) == 80, len(light_records)
s['photoreal_finish_applied'] = True
report = {'phase': 'MATERIAL_AND_LIGHT_PASS', 'objects': [o.name for o, _ in targets],
    'materials': records, 'lights': light_records, 'geometry_policy': 'original vertices, topology and transforms preserved',
    'limits': ['Cycles appearance requires visual review', 'procedural materials require baking or equivalent Godot shaders before export',
               'no new GI bake', 'no gameplay scene replaced']}
(work / 'finish_report.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(work / 'parking_photoreal.blend'))
assert Path(bpy.data.filepath) == work / 'parking_photoreal.blend'
print('PHOTOREAL_FINISH_APPLIED', json.dumps({'objects': len(targets), 'materials': len(records), 'lights': len(light_records), 'file': bpy.data.filepath}))
