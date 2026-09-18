"""Author/export charcoal uniform materials, preserving the original game rig verbatim.

Run after blender_prepare_pistol.py via pistol_blender_mcp.py. The exported material
is merged into a copy of the original glTF; its binary, nodes, skin and animations
are deliberately NOT round-tripped through Blender's animation exporter.
"""
import bpy
import numpy as np
import json
import hashlib
import copy
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(PROJECT_ROOT) if 'PROJECT_ROOT' in globals() else Path(__file__).resolve().parents[1]
ASSET = ROOT / 'assets/weapons/pistol'
OUT = ASSET / 'uniform'
STAGING = ROOT / 'build/pistol_uniform'
OUT.mkdir(exist_ok=True)
STAGING.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes['PistolUniform']
bpy.context.window.scene = scene
arms = scene.objects['Object_9']
source_image = bpy.data.images.load(str(ASSET / 'textures/arms_diffuse.png'), check_existing=True)
w, h = source_image.size
original = np.array(source_image.pixels[:], dtype=np.float32).reshape(h, w, 4)

# Sample the soldier's actual atlas on sleeve/glove vertices, not the whole
# atlas (which also includes the helmet, boots and vest).
soldier = bpy.data.objects['SoldierMesh']
soldier_image = next(n.image for n in soldier.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)
sw, sh = soldier_image.size
soldier_pixels = np.array(soldier_image.pixels[:], dtype=np.float32).reshape(sh, sw, 4)
colors = {}
for region, groups in [('sleeve', ['Arm', 'ForeArm']), ('glove', ['Hand'])]:
    ids = {v.index for v in soldier.data.vertices if sum(g.weight for g in v.groups if any(name in soldier.vertex_groups[g.group].name for name in groups)) > .8}
    uv = np.array([soldier.data.uv_layers.active.data[l.index].uv[:] for l in soldier.data.loops if l.vertex_index in ids])
    sampled = soldier_pixels[(uv[:, 1]*sh).astype(int).clip(0, sh-1), (uv[:, 0]*sw).astype(int).clip(0, sw-1), :3]
    colors[region] = np.median(sampled, axis=0)

# Rasterize existing skin weights into UV space. This only distinguishes sleeve
# from glove for the finish; no vertex, group, weight, UV or bone is edited.
mesh = arms.data
sleeve_weights = np.array([sum(g.weight for g in v.groups if any(name in arms.vertex_groups[g.group].name for name in ['UpArm', 'Forearm', 'BoneTwist'])) for v in mesh.vertices])
mesh.calc_loop_triangles()
uv_data = mesh.uv_layers.active.data
mask_sum = np.zeros((h, w), dtype=np.float32)
hits = np.zeros((h, w), dtype=np.float32)
for tri in mesh.loop_triangles:
    uv = np.array([uv_data[i].uv[:] for i in tri.loops]) * [w, h] - .5
    low = np.maximum(np.floor(uv.min(axis=0)).astype(int), 0)
    high = np.minimum(np.ceil(uv.max(axis=0)).astype(int), [w-1, h-1])
    if np.any(low > high):
        continue
    a,b,c = uv
    det = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
    if abs(det) < 1e-8:
        continue
    yy,xx = np.mgrid[low[1]:high[1]+1,low[0]:high[0]+1]
    wa = ((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1])) / det
    wb = ((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1])) / det
    wc = 1-wa-wb
    inside = (wa >= -1e-5) & (wb >= -1e-5) & (wc >= -1e-5)
    values = np.clip(wa*sleeve_weights[tri.vertices[0]] + wb*sleeve_weights[tri.vertices[1]] + wc*sleeve_weights[tri.vertices[2]], 0, 1)
    mask_sum[low[1]:high[1]+1,low[0]:high[0]+1] += values * inside
    hits[low[1]:high[1]+1,low[0]:high[0]+1] += inside
covered = hits > 0
mask = mask_sum / np.maximum(hits,1)
# Extend edge texels into gutters for mipmapping; mirrored islands are identical.
valid = covered.copy()
for _ in range(16):
    total = np.zeros_like(mask)
    count = np.zeros_like(mask)
    for dy, dx in [(0,1),(0,-1),(1,0),(-1,0)]:
        shifted = np.roll(valid,(dy,dx),(0,1))
        total += np.roll(mask,(dy,dx),(0,1)) * shifted
        count += shifted
    fill = ~valid & (count > 0)
    mask[fill] = total[fill] / count[fill]
    valid |= fill

# Keep the supplied weave, stitching, creases and wear as luminance variation;
# replace the sandy dye with the character's charcoal palette, not a flat fill.
luma = original[:,:,:3] @ np.array([.2126,.7152,.0722])
anchors = {}
for name, selection in [('sleeve',covered & (mask>.8)),('glove',covered & (mask<.2))]:
    assert selection.sum() > 100, name
    anchors[name] = float(np.median(luma[selection]))
anchor = anchors['glove']*(1-mask) + anchors['sleeve']*mask
palette = colors['glove'][None,None,:]*(1-mask[:,:,None]) + colors['sleeve'][None,None,:]*mask[:,:,None]
albedo = original.copy()
albedo[:,:,:3] = np.clip(palette * (np.maximum(luma,.001)/np.maximum(anchor,.001))[:,:,None],0,1)
# Both regions are nonmetallic. Preserve local gloss-map detail in a narrow,
# cloth-appropriate range around the soldier's authored sleeve roughness (0.8).
gloss_image = bpy.data.images.load(str(ASSET / 'textures/arms_specularGlossiness.png'), check_existing=True)
assert tuple(gloss_image.size) == (w,h)
gloss = np.array(gloss_image.pixels[:],dtype=np.float32).reshape(h,w,4)[:,:,3]
rough = np.clip(.74 + .06*mask + .08*(np.median(gloss[covered])-gloss), .65, .92)

def save_texture(name, pixels, noncolor=False):
    img = bpy.data.images.get(name) or bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.colorspace_settings.name = 'Non-Color' if noncolor else 'sRGB'
    img.pixels.foreach_set(np.asarray(pixels,dtype=np.float32).ravel())
    img.filepath_raw = str(OUT / (name+'.png'))
    img.file_format = 'PNG'
    img.save()
    return img

albedo_image = save_texture('pistol_uniform_albedo', albedo)
rough_pixels = np.ones_like(albedo)
rough_pixels[:,:,:3] = rough[:,:,None]
rough_image = save_texture('pistol_uniform_roughness', rough_pixels, True)
material = bpy.data.materials.get('SoldierUniformArms') or bpy.data.materials.new('SoldierUniformArms')
material.use_nodes = True
material.diffuse_color = (*colors['sleeve'],1)
nodes, links = material.node_tree.nodes, material.node_tree.links
nodes.clear()
bsdf = nodes.new('ShaderNodeBsdfPrincipled')
output = nodes.new('ShaderNodeOutputMaterial')
links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
bsdf.inputs['Metallic'].default_value = 0
bsdf.inputs['Roughness'].default_value = .8

def texture(img, x,y):
    node = nodes.new('ShaderNodeTexImage')
    node.image = img
    node.location=(x,y)
    return node

links.new(texture(albedo_image,-600,300).outputs['Color'],bsdf.inputs['Base Color'])
links.new(texture(rough_image,-600,0).outputs['Color'],bsdf.inputs['Roughness'])
normal_image=bpy.data.images.load(str(ASSET/'textures/arms_normal.png'),check_existing=True)
normal_image.colorspace_settings.name='Non-Color'
normal=nodes.new('ShaderNodeNormalMap')
normal.location=(-250,-200)
links.new(texture(normal_image,-600,-250).outputs['Color'],normal.inputs['Color'])
links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
# glTF's AO is an exporter input, not baked lighting multiplied into albedo.
settings = bpy.data.node_groups.get('glTF Material Output') or bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
if not settings.interface.items_tree:
    settings.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
settings_node=nodes.new('ShaderNodeGroup')
settings_node.node_tree=settings
occlusion=bpy.data.images.load(str(ASSET/'textures/arms_occlusion.png'),check_existing=True)
occlusion.colorspace_settings.name='Non-Color'
links.new(texture(occlusion,-600,-500).outputs['Color'],settings_node.inputs['Occlusion'])
# Double-sided like the source, including its deliberately cropped shoulder ends.
material.use_backface_culling = False
arms.data.materials[0]=material

# Export the real skinned assembly, restricted to this scene (never the soldier).
bpy.ops.object.select_all(action='DESELECT')
for obj in scene.objects:
    if obj.name != 'Icosphere':
        obj.select_set(True)
bpy.context.view_layer.objects.active=arms
# NLA_TRACKS limits export to clips actually attached to this rig. ACTIONS would
# try to apply the separate soldier reference's actions to the pistol as well.
bpy.ops.export_scene.gltf(filepath=str(STAGING/'pistol_uniform.gltf'),export_format='GLTF_SEPARATE',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_skins=True)
exported=json.loads((STAGING/'pistol_uniform.gltf').read_text())
assert {a['name'] for a in exported['animations']} == {a['name'] for a in json.loads((ASSET/'scene.gltf').read_text())['animations']}
new_material=copy.deepcopy(next(m for m in exported['materials'] if m['name']=='SoldierUniformArms'))
original_doc=json.loads((ASSET/'scene.gltf').read_text())
result=copy.deepcopy(original_doc)
# glTF export may rename texture files. Remap each exported texture/image/sampler
# into the original document while copying only this material's dependencies.
texture_remap={}
for slot in [new_material['pbrMetallicRoughness']['baseColorTexture'],new_material['pbrMetallicRoughness']['metallicRoughnessTexture'],new_material['normalTexture'],new_material['occlusionTexture']]:
    index=slot['index']
    if index not in texture_remap:
        tex=copy.deepcopy(exported['textures'][index])
        image=copy.deepcopy(exported['images'][tex['source']])
        payload=(STAGING/unquote(image['uri'])).read_bytes()
        # Reuse original texture bytes if the exporter copied them unchanged.
        existing=next((i for i,item in enumerate(result['images']) if 'uri' in item and (ASSET/unquote(item['uri'])).is_file() and (ASSET/unquote(item['uri'])).read_bytes()==payload),None)
        if existing is None:
            target=OUT/Path(unquote(image['uri'])).name
            if not target.exists():
                target.write_bytes(payload)
            else:
                assert target.read_bytes()==payload, 'Texture filename collision: '+str(target)
            image['uri']=target.relative_to(ASSET).as_posix()
            existing=len(result['images'])
            result['images'].append(image)
        tex['source']=existing
        if 'sampler' in tex:
            sampler=exported['samplers'][tex['sampler']]
            samplers=result.setdefault('samplers',[])
            if sampler not in samplers:
                samplers.append(sampler)
            tex['sampler']=samplers.index(sampler)
        texture_remap[index]=len(result['textures'])
        result['textures'].append(tex)
    slot['index']=texture_remap[index]
result['materials'][0]=new_material
for extension in new_material.get('extensions',{}):
    used=result.setdefault('extensionsUsed',[])
    if extension not in used:
        used.append(extension)
# The pistol still uses its original specular/glossiness material, unchanged.
for key in ('nodes','meshes','skins','animations','accessors','bufferViews','buffers','scenes','scene'):
    assert result.get(key)==original_doc.get(key), key
assert result['materials'][1:]==original_doc['materials'][1:]
(ASSET/'pistol_uniform.gltf').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
# Editable source: only the pistol authoring scene and its dependencies, not the
# 50-animation soldier reference or any pre-existing user scenes.
bpy.data.libraries.write(str(STAGING/'pistol_uniform_library.blend'),{scene},path_remap='RELATIVE',fake_user=True,compress=True)
# Convert this isolated scene library into a normally openable .blend with
# blender_package_pistol.py in a separate factory-startup background process.
report={
    'source':'assets/weapons/pistol/scene.gltf',
    'source_gltf_sha256':hashlib.sha256((ASSET/'scene.gltf').read_bytes()).hexdigest(),
    'shared_binary_sha256':hashlib.sha256((ASSET/'scene.bin').read_bytes()).hexdigest(),
    'palette_reference':'IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb',
    'reference_sha256':hashlib.sha256((ROOT/'IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb').read_bytes()).hexdigest(),
    'sleeve_rgb':colors['sleeve'].tolist(),'glove_rgb':colors['glove'].tolist(),
    'texture_size':[w,h],'covered_texels':int(covered.sum()),
    'animations':[a['name'] for a in result['animations']],
    'method':'Blender material export merged into unchanged source glTF rig; original UV detail recolored to sampled soldier palette',
}
(OUT/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print('PISTOL_UNIFORM_EXPORTED',json.dumps(report))
