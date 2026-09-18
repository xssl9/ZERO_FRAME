"""
Fix parking floor gaps and improve materials.
Run with: blender --background parking_photoreal.blend --python tools/fix_parking_floor.py
"""
import bpy
import os
import sys

BLEND_PATH = "/home/tuxpc/game/ZERO_FRAME_backups/parking_finish_20260908T185805Z/parking_photoreal.blend"
EXPORT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../assets/environment/parking_rework/assembly.glb")

def set_principled(mat, base_color=None, roughness=None, metallic=None, specular=None, normal_strength=None):
    if not mat or not mat.use_nodes:
        return
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            if base_color is not None:
                node.inputs['Base Color'].default_value = (*base_color, 1.0)
            if roughness is not None:
                node.inputs['Roughness'].default_value = roughness
            if metallic is not None:
                node.inputs['Metallic'].default_value = metallic
            if specular is not None and 'Specular IOR Level' in node.inputs:
                node.inputs['Specular IOR Level'].default_value = specular
            break

def fix():
    # --- 1. Fix FloorJoints Z position ---
    # They sit at z=0.0005..0.0035, floor surface is at z=0.0.
    # Snap them flush to floor so no gap is visible underneath.
    for obj in bpy.data.objects:
        if obj.name.startswith('RW_FloorJoints'):
            # Move down so top face is exactly at z=0
            bb_max_z = max(v[2] for v in obj.bound_box) * obj.scale[2] + obj.location[2]
            obj.location[2] -= bb_max_z  # top face now at z=0
            print(f"Snapped {obj.name} to floor (moved {-bb_max_z:.4f}m)")

    # --- 2. Improve RW_ExpansionSeal material ---
    # Was near-black (0.075, 0.073, 0.066) — looked like a void.
    # Real expansion joint sealant is dark grey rubber/bitumen.
    mat = bpy.data.materials.get('RW_ExpansionSeal')
    if mat:
        set_principled(mat,
            base_color=(0.055, 0.052, 0.048),  # very dark grey, not black
            roughness=0.92,                      # matte rubber
            metallic=0.0)
        print("Fixed RW_ExpansionSeal material")

    # --- 3. Improve RW_DrainRecess material ---
    mat = bpy.data.materials.get('RW_DrainRecess')
    if mat:
        set_principled(mat,
            base_color=(0.032, 0.035, 0.030),
            roughness=0.85,
            metallic=0.0)
        print("Fixed RW_DrainRecess material")

    # --- 4. Improve RW_GalvanizedSteel ---
    mat = bpy.data.materials.get('RW_GalvanizedSteel')
    if mat:
        set_principled(mat,
            base_color=(0.52, 0.54, 0.52),
            roughness=0.38,
            metallic=0.85)
        print("Fixed RW_GalvanizedSteel material")

    # --- 5. Improve floor concrete materials ---
    for mat_name in ['PF_WEAR_L02_FloorConcrete', 'PF_WEAR_L02_UnbakedConcrete',
                     'PF_L02_UnbakedConcrete']:
        mat = bpy.data.materials.get(mat_name)
        if mat:
            # Concrete: slightly warm grey, rough
            set_principled(mat,
                base_color=(0.38, 0.36, 0.33),
                roughness=0.88,
                metallic=0.0)
            print(f"Fixed {mat_name}")

    # --- 6. Export GLB ---
    print(f"\nExporting to {EXPORT_PATH}...")
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_materials='EXPORT',
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    print("Export done.")

fix()
