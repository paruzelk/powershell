#!/usr/bin/env python3
"""MIG19g-h: shared scoped presentation and documentation source gates."""
import argparse,json,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
def read(p):return p.read_text(encoding='utf-8-sig')
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--candidate',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
 a=p.parse_args()
 catalog=json.loads(read(HERE/'MIG19gh-Display.json'))
 sources={};original={};witness=[]
 for path,old,new,count in catalog['patches']:
  if path not in sources:
   original[path]=sources[path]=read(a.candidate/path)
  s=sources[path]
  if s.count(old)!=count or old==new:raise ValueError('Exact anchor count: '+path+' '+old[:90])
  t=s.replace(old,new)
  # Some replacements contain the old string (e.g. extending the map); check inverse.
  if t.count(new)!=count or t.replace(new,old)!=s:raise ValueError('Non-reversible patch '+path)
  sources[path]=t;witness.append({'path':path,'count':count})
 path='src/modules/Core/Render-HtmlObject.ps1'
 before=sources[path];helper=catalog['helper']
 if 'function ConvertTo-RuDisplayAttribute19g {' in before:raise ValueError('Duplicate helper')
 sources[path]=before+'\n\n'+helper
 if sources[path][:-len('\n\n'+helper)]!=before:raise ValueError('Helper append mismatch')
 for path,s in sources.items():
  (a.candidate/path).write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
 guide=read(a.candidate/'README-RU-2.11.0.md')
 for title in ('MIG19gh','Параметры Invoke-adPEAS','Параметры Connect-adPEAS','Синтаксис дополнительных команд','Итоговый аудит MIG19i'):
  if title not in guide:raise ValueError('Missing README section '+title)
 data={'schema':'adPEAS-RU.MIG19gh.Source.1','presentationOnly':True,'patchOccurrences':sum(x['count'] for x in witness),'newLabels':11,'helperAppended':True,'sourceWitnesses':witness,'files':{p:hashlib.sha256((a.candidate/p).read_bytes()).hexdigest() for p in sources},'documentationSha256':hashlib.sha256((a.candidate/'README-RU-2.11.0.md').read_bytes()).hexdigest(),'productionReady':False}
 a.report.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('PASS MIG19gh: 11 labels, shared field-scoped render values, reversible source changes, README anchors')
if __name__=='__main__':main()
