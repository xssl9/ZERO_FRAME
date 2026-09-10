import bpy,json
s=bpy.context.scene
print('ZONING_PROGRESS',json.dumps({'scene':s.name,'file':bpy.data.filepath,'hierarchy':s.get('prop_source_hierarchy_verified'),'fences_ready':s.get('zoned_fences_ready'),
 'extensions':len(bpy.data.collections['ZONE_FenceExtensions'].objects) if bpy.data.collections.get('ZONE_FenceExtensions') else None,
 'groups':{str(i):[o.name for o in s.objects if o.get('godot_path','').startswith('Props/Prop%d_fence/'%i)] for i in (90,91,92)}}))
