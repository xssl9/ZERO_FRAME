"""Measured architectural/service/wear pass in the COMPLETE live Blender assembly.
Run only through parking_blender_mcp.py. Original gameplay assets remain unchanged.
"""
import bpy
import bmesh
import json
import math
from pathlib import Path
from mathutils import Vector
import numpy as np

ROOT = Path('/home/tuxpc/game/ZERO_FRAME')
WORK = ROOT.parent / 'ZERO_FRAME_backups/parking_full_rework_20260908'
OUT = ROOT / 'assets/environment/parking_rework'
scene = bpy.data.scenes['ZERO_FRAME_Parking_FULL_REWORK']
bpy.context.window.scene = scene
assert scene.get('phase') == 'FULL_ASSEMBLY_READY_FOR_REWORK', 'Inspect existing artist changes before repeating'
assert not (OUT / 'architectural_rework.glb').exists()
assert not (WORK / 'parking_complete_reworked.blend').exists()
layout = json.loads((WORK / 'rework_layout.json').read_text())
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'textures').mkdir(exist_ok=True)
collection = bpy.data.collections.new('ENV_REWORK_ARCHITECTURE_AND_WEAR')
scene.collection.children.link(collection)
buckets = {}
parts = {}
materials = []


def pbr(name, color, metal, rough):
    mat = bpy.data.materials.new('RW_' + name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    materials.append(mat)
    return len(materials)-1

steel = pbr('GalvanizedSteel', (.36, .39, .40), 1.0, .48)
paint = pbr('PipeClampPaint', (.13, .15, .14), 0.0, .66)
seal = pbr('ExpansionSeal', (.075, .073, .066), 0.0, .9)
recess = pbr('DrainRecess', (.022, .027, .025), 0.0, .78)


def bm_for(kind, x):
    key = (kind, int((x+30)//10))
    if key not in buckets:
        buckets[key] = bmesh.new()
    return buckets[key]


def game(point):
    return (point[0], -point[2], point[1])


def box(kind, centre, size, slot):
    bm = bm_for(kind, centre[0])
    result = bmesh.ops.create_cube(bm, size=1.0)
    for v in result['verts']:
        v.co = Vector(game((centre[0]+v.co.x*size[0], centre[1]+v.co.y*size[1], centre[2]+v.co.z*size[2])))
    for f in {face for v in result['verts'] for face in v.link_faces}:
        f.material_index = slot
    parts[kind] = parts.get(kind, 0)+1


def ring(x, y, z, inner, outer):
    bm = bm_for('PipeFlanges', x)
    rings = []
    for side, radius in ((-.014, outer), (.014, outer), (-.014, inner), (.014, inner)):
        rings.append([bm.verts.new(game((x+side, y+radius*math.cos(i*math.tau/16), z+radius*math.sin(i*math.tau/16)))) for i in range(16)])
    for a,b in ((0,1),(1,3),(3,2),(2,0)):
        for i in range(16):
            face = bm.faces.new((rings[a][i],rings[a][(i+1)%16],rings[b][(i+1)%16],rings[b][i]))
            face.material_index = paint
    parts['PipeFlanges'] = parts.get('PipeFlanges',0)+1

# Floor construction/control joints: flush thin sealing material, not raised bars.
for x in range(-24,25,6):
    box('FloorJoints', (x,.002,0), (.009,.003,39.6), seal)
for z in range(-15,16,6):
    for x in (-25,-15,-5,5,15,25):
        box('FloorJoints', (x,.002,z), (10,.003,.009), seal)
# Ceiling panel reveals, not fictitious sixty-metre unsupported concrete beams.
for z in (-13.5,-4.5,4.5,13.5):
    for x in (-25,-15,-5,5,15,25):
        box('CeilingReveals', (x,3.097,z), (10,.006,.018), seal)

# Rectangular duct flanges wrap the measured 0.70 x 0.45 m service, without
# filling its interior. Trapeze supports meet its underside and the real ceiling.
for x in range(-27,28,3):
    for y in (2.163,2.637):
        box('DuctFlanges', (x,y,-3.5), (.033,.024,.748), steel)
    for z in (-3.862,-3.138):
        box('DuctFlanges', (x,2.4,z), (.033,.45,.024), steel)
for x in (-27,-22.5,-18,-13.5,-9,-4.5,0,4.5,9,13.5,18,22.5,27):
    box('DuctSupports', (x,2.148,-3.5), (.048,.054,.88), steel)
    for z in (-3.916,-3.084):
        box('DuctSupports', (x,2.624,z), (.014,.952,.014), steel)
        box('DuctSupports', (x,3.095,z), (.10,.01,.10), steel)
        box('DuctSupports', (x,2.17,z), (.03,.017,.03), paint)

# Pipe connections are placed between columns, never through an existing pillar.
flanges = 0
for run in layout['service_runs']:
    for x in (-24,-15,-6,3,12,21):
        if any(abs(p['centre'][0]-x) < .6 and abs(p['centre'][2]-run['z']) < .6 for p in layout['pillars']):
            continue
        ring(x,run['y'],run['z'],run['radius']+.002,run['radius']+.024)
        flanges += 1
for x in (-24,-15,-6,3,12,21):
    box('PipeSupports',(x,2.375,10.75),(.04,.02,.96),steel)
    for z in (10.29,11.21):
        box('PipeSupports',(x,2.738,z),(.012,.724,.012),steel)
        box('PipeSupports',(x,3.095,z),(.09,.01,.09),steel)

# Flush perimeter grates: separated bars, visible recess and framing. These are
# visual drains; the original floor collision remains continuous, no fluid sim.
drains = []
for x in (-25,-15,-5,5,15,25):
    for z in (-19.25,19.25):
        drains.append((x,z))
        box('DrainRecess',(x,.0015,z),(.58,.001,.28),recess)
        for dx in (-.30,.30):
            box('DrainFrames',(x+dx,.004,z),(.018,.008,.32),steel)
        for dz in (-.151,.151):
            box('DrainFrames',(x,.004,z+dz),(.60,.008,.018),steel)
        for n in range(19):
            box('DrainBars',(x-.27+n*.03,.004,z),(.012,.008,.28),steel)

# Concrete formwork tie recesses are deliberately NOT faked with protruding bolts.
# This pass only adds existing-service supports and flush surface construction.
new_meshes = []
for (kind, sector), bm in sorted(buckets.items()):
    if kind not in ('FloorJoints','CeilingReveals','DrainRecess'):
        bmesh.ops.bevel(bm,geom=list(bm.edges),offset=.0012,segments=2,affect='EDGES',clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        normal = face.normal
        axis = max(range(3),key=lambda i:abs(normal[i]))
        a,b = ((1,2) if axis==0 else (0,2) if axis==1 else (0,1))
        for loop in face.loops:
            loop[uv].uv = (loop.vert.co[a]*.5,loop.vert.co[b]*.5)
    assert all(len(e.link_faces)==2 for e in bm.edges), 'Non-manifold detail: '+kind
    mesh = bpy.data.meshes.new('RW_%s_%d'%(kind,sector))
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(mesh.name,mesh)
    collection.objects.link(obj)
    obj['detail_kind'] = kind
    obj['gameplay_collision'] = 'none; flush floor or above 2.1m'
    new_meshes.append(obj)

# Deterministic original grime images, no fetched textures. Keep channel semantics:
# RGB is stain pigment; A is coverage; roughness stays a separate material value.
N = 512
rng = np.random.default_rng(240908)
yy,xx = np.mgrid[0:N,0:N].astype(np.float32)
x,y = (xx+.5)/N,(yy+.5)/N

def noise():
    result = np.zeros((N,N),dtype=np.float32)
    for cells,weight in ((5,.5),(13,.25),(33,.15),(80,.1)):
        grid = rng.random((cells,cells))
        across = np.array([np.interp(np.linspace(0,cells-1,N),np.arange(cells),row) for row in grid])
        out = np.array([np.interp(np.linspace(0,cells-1,N),np.arange(cells),col) for col in across.T]).T
        result += out*weight
    return result

n = noise()
radial = ((x-.5)/.48)**2+((y-.5)/.44)**2
masks = {}
masks['OilResidue'] = np.clip((.93-radial+(n-.5)*.85)*3,0,1)*(.15+.28*n)
masks['DrainDirt'] = np.clip((1.0-radial+(n-.5)*.6)*2,0,1)*(.08+.20*n)
# Repeat exactly along travel Y; varying intermittent pigment avoids solid rails.
groove = np.abs(np.sin((x*8+np.abs(np.sin(y*math.tau*4))*.25)*math.pi))
edge = np.clip((.48-np.abs(x-.5))*16,0,1)
travel = .45+.55*np.sin(y*math.tau*2)**2
masks['TireTransfer'] = edge*(.12+.20*groove)*travel
columns = np.sin(x*math.tau*19+.4*np.sin(x*math.tau*3))**8
masks['PipeRunoff'] = np.clip((1-np.abs(x-.5)*2)*2,0,1)*columns*(.1+.3*(1-y))*(np.sin(y*math.pi)**.7)
textures = {}
for name,mask in masks.items():
    pigment = (.055,.049,.036) if name=='OilResidue' else (.11,.087,.060) if name=='PipeRunoff' else (.12,.115,.098)
    rgba = np.ones((N,N,4),dtype=np.float32)
    for i in range(3):
        rgba[:,:,i] = pigment[i]*(.8+.4*n)
    rgba[:,:,3] = mask
    # Guard a completely transparent border on non-repeating dirt decals.
    if name!='TireTransfer':
        border = np.clip(np.minimum.reduce((x,y,1-x,1-y))*40,0,1)
        rgba[:,:,3] *= border
    image = bpy.data.images.new('RW_'+name,width=N,height=N,alpha=True)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(OUT/'textures'/('%s.png'%name))
    image.file_format = 'PNG'
    image.save()
    mat = bpy.data.materials.new('RW_'+name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = .40 if name=='OilResidue' else .84
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    mat.node_tree.links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
    textures[name] = mat


def decal(name,kind,centre,u,v,repeat=1.0):
    c,U,V = Vector(centre),Vector(u),Vector(v)
    coords = [game(c-U/2-V/2),game(c+U/2-V/2),game(c+U/2+V/2),game(c-U/2+V/2)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(coords,[],[(0,1,2,3)])
    mesh.update()
    uv = mesh.uv_layers.new(name='UVMap')
    coords_uv = [(0,0),(0,repeat),(1,repeat),(1,0)] if kind=='TireTransfer' else [(0,0),(1,0),(1,1),(0,1)]
    for i,value in enumerate(coords_uv):
        uv.data[i].uv = value
    mesh.materials.append(textures[kind])
    obj = bpy.data.objects.new(name,mesh)
    collection.objects.link(obj)
    obj['detail_kind'] = kind
    obj['no_shadow'] = True
    obj.visible_shadow = False
    new_meshes.append(obj)
    return obj

# Oil residue follows actual parked vehicles, not random scatter through corridors.
for i,(name,(low,high)) in enumerate(sorted(layout['cars'].items())):
    if i%2==0:
        cx,cz = (low[0]+high[0])/2,(low[2]+high[2])/2
        decal('RW_Oil_'+name,'OilResidue',(cx,.005,cz),(.85,0,0),(0,0,-.58))
for i,(dx,dz) in enumerate(drains):
    decal('RW_DrainDirt_%02d'%i,'DrainDirt',(dx,.004,dz),(1.1,0,0),(0,0,-.75))
for i,z in enumerate((-3.8,-2.2,4.2,5.8)):
    decal('RW_TireLane_%d'%i,'TireTransfer',(0,.0045,z),(54,0,0),(0,0,-.19),repeat=36.0)
for i,z in enumerate((11.0,10.5,-9.5)):
    for side in (-1,1):
        decal('RW_PipeRunoff_%d_%d'%(i,side),'PipeRunoff',(side*29.994,1.25,z),(0,0,side*.5),(0,2.3,0))

# Match the separate Godot variant: less globally mottled concrete and no unmotivated neon.
for obj in scene.objects:
    if obj.type=='LIGHT' and obj.name in ('LIGHT_NeonAccent','LIGHT_NeonAccent2'):
        obj.data.energy = 0
    if obj.type=='MESH' and obj.get('godot_path') in ('Garage/Floor_Parking','Garage/Walls_Concrete','Garage/Walls_Plaster'):
        for mat in obj.data.materials:
            if mat and mat.use_nodes and mat.get('godot_material_parameters'):
                for node in mat.node_tree.nodes:
                    if node.type=='MATH' and node.operation=='MULTIPLY':
                        node.inputs[1].default_value = .28

bpy.context.view_layer.update()
triangles = 0
for obj in new_meshes:
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
assert 0 < triangles < 120000, triangles
assert len(scene.objects) > 650, 'Full assembly lost'
bpy.ops.object.select_all(action='DESELECT')
for obj in new_meshes:
    obj.select_set(True)
# Export additive geometry only. Full editable scene remains in Blender with props.
assert 'FINISHED' in bpy.ops.export_scene.gltf(filepath=str(OUT/'architectural_rework.glb'),
    export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',
    export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
scene['phase'] = 'ARCHITECTURAL_SERVICE_WEAR_PASS_NOT_VISUALLY_APPROVED'
scene['rework_triangles'] = triangles
bpy.data.libraries.write(str(WORK/'parking_complete_reworked.blend'),{scene},path_remap='ABSOLUTE',fake_user=True)
bpy.ops.object.select_all(action='DESELECT')
# Start inside the full scene, not staring at its roof from outside.
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective = 'CAMERA'
report = {'added_meshes':len(new_meshes),'added_triangles':triangles,'parts':parts,
          'drains':len(drains),'pipe_flanges':flanges,'source_visible_meshes':601,
          'base_scene_sha256':layout['source_sha256'],'full_blend':str(WORK/'parking_complete_reworked.blend'),
          'limitations':['not a whole architectural shell replacement','visual acceptance pending','Blender world PBR/photometry approximate','no GI bake','flush decorative drains; unchanged floor collider']}
(OUT/'rework_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PARKING_REWORK_EXPORTED',json.dumps(report))
