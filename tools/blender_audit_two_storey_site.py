"""Read-only site clearance and materials inspection."""
import bpy,json
from mathutils import Vector
s=bpy.context.scene
out={'near_breach':[],'paint':[],'cars':[],'fixture_details':[]}
for o in s.objects:
 if o.type!='MESH':continue
 pts=[o.matrix_world@Vector(p) for p in o.bound_box]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 path=o.get('godot_path','')
 if path.startswith(('Cars/','Props/')) and lo[0]<-5 and hi[0]>-11 and lo[1]<-1.5 and hi[1]>-8:
  out['near_breach'].append({'name':o.name,'path':path,'lo':lo,'hi':hi})
 if path.startswith('Paint/') and len(out['paint'])<12:
  out['paint'].append({'name':o.name,'path':path,'lo':lo,'hi':hi,'materials':[{'name':m.name,'bsdf':[(i.name,list(i.default_value) if i.type=='RGBA' else i.default_value) for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED' for i in n.inputs if i.name in ('Base Color','Roughness','Alpha')],'links':[(l.from_node.type,l.to_node.type,l.to_socket.name) for l in m.node_tree.links]} for m in o.data.materials if m and m.use_nodes]})
 if path.startswith('Cars/'):
  out['cars'].append({'name':o.name,'path':path,'lo':lo,'hi':hi})
 if path.startswith('FixtureDetails/'):
  out['fixture_details'].append({'name':o.name,'path':path,'lo':lo,'hi':hi})
print('TWO_STOREY_SITE',json.dumps(out))
