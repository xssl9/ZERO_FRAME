import bpy,json
s=bpy.context.scene
print('FENCE_IDS',json.dumps([{'requested':('ZF_%04d'%i),'objects':[{'name':o.name,'path':o.get('godot_path'),'transfer':o.get('transfer_id'),'zone':o.get('zone'),'linked_to_scene':o.name in s.objects,'collections':[c.name for c in o.users_collection]} for o in bpy.data.objects if o.name.startswith('ZF_%04d_'%i)]} for i in range(339,359)]))
