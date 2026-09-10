"""Read the actual structural shader connections before editing. Run via MCP."""
import bpy, json
s = bpy.context.scene
names = ('ZF_0000_Ceiling', 'ZF_0003_Floor_Annex', 'ZF_0004_Floor_Parking', 'ZF_0006_Walls_Concrete', 'ZF_0007_Walls_Plaster', 'L02_InterstoreySlab', 'L02_AlignedWallsAndColumns', 'L02_RoofAndBeams', 'L02_EasedVehicleRamp')
seen = set()
for name in names:
    ob = s.objects[name]
    print('STRUCTURE', name, 'UVS', [u.name for u in ob.data.uv_layers], 'SLOTS', {i: sum(p.material_index == i for p in ob.data.polygons) for i in range(len(ob.data.materials))}, 'MODIFIERS', [(m.name,m.type) for m in ob.modifiers])
    for m in ob.data.materials:
        if not m or m.name in seen: continue
        seen.add(m.name)
        print('SHADER', m.name, json.dumps({'nodes': [{'name': n.name, 'type': n.type, 'image': n.image.name if n.type == 'TEX_IMAGE' and n.image else None, 'projection': n.projection if n.type == 'TEX_IMAGE' else None, 'operation': getattr(n, 'operation', None), 'blend_type': getattr(n, 'blend_type', None), 'inputs': {i.name: (list(i.default_value) if hasattr(i.default_value, '__len__') and not isinstance(i.default_value,str) else i.default_value) for i in n.inputs if hasattr(i, 'default_value') and not i.is_linked}} for n in m.node_tree.nodes], 'links': [(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]}))
print('PHOTOREAL_MATERIAL_AUDIT_OK')
