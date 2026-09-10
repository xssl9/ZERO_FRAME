"""Read-only inspection after an interrupted authoring operation."""
import bpy, json
s = bpy.context.scene
print('PROGRESS', json.dumps({'file': bpy.data.filepath, 'applied': s.get('photoreal_finish_applied'),
    'rendering': bpy.app.is_job_running('RENDER'),
    'materials': [{'name': m.name, 'source': m.get('photoreal_finish_source'), 'users': m.users,
                  'images': [(n.image.name, list(n.image.size)) for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]}
                 for m in bpy.data.materials if m.name.startswith('PF_') and m.use_nodes],
    'changed_objects': [o.name for o in s.objects if o.type == 'MESH' and any(slot.material and slot.material.name.startswith('PF_') for slot in o.material_slots)]}))
im = bpy.data.images.get('concrete_floor_damaged_01_nor_gl_2k.jpg')
if im:
    loaded_before = im.has_data
    dimensions = list(im.size)
    print('NORMAL_IMAGE_LOAD', json.dumps({'before': loaded_before, 'size': dimensions, 'after': im.has_data}))
print('PHOTOREAL_PROGRESS_OK')
