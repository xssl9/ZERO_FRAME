"""Fetch exactly the two user-requested Poly Haven CC0 materials; verify every file."""
import json,hashlib,urllib.request,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets/polyhaven/textures'
UA={'User-Agent':'ZERO-FRAME-Blender-authoring/1.0'}
records=[]
for slug in ('rusty_metal_sheet','rusty_metal_05'):
 with urllib.request.urlopen(urllib.request.Request('https://api.polyhaven.com/files/'+slug,headers=UA),timeout=30) as r:info=json.load(r)
 directory=ROOT/slug;directory.mkdir(parents=True,exist_ok=True)
 for key,suffix in (('Diffuse','diff'),('arm','arm'),('nor_gl','nor_gl')):
  entry=info[key]['2k']['jpg'];url=entry['url'];parsed=urllib.parse.urlsplit(url)
  assert parsed.scheme=='https' and parsed.hostname=='dl.polyhaven.org' and '/'+slug+'/' in parsed.path
  dest=directory/(slug+'_'+suffix+'_2k.jpg')
  if dest.exists():raw=dest.read_bytes()
  else:
   with urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=120) as r:raw=r.read()
  assert len(raw)==entry['size'],(slug,key,'size mismatch')
  assert hashlib.md5(raw).hexdigest()==entry['md5'],(slug,key,'checksum mismatch')
  assert raw[:2]==b'\xff\xd8',(slug,key,'not JPEG')
  if not dest.exists():dest.write_bytes(raw)
  records.append({'asset':slug,'map':key,'path':str(dest),'url':url,'bytes':len(raw),'md5':entry['md5']})
  print('VERIFIED',slug,key,len(raw),flush=True)
 manifest=directory/'source_manifest.json'
 manifest.write_text(json.dumps({'source':'https://polyhaven.com/a/'+slug,'license':'CC0','files':[x for x in records if x['asset']==slug]},indent=2))
print('REQUESTED_METALS_DOWNLOAD_PASS',len(records))
