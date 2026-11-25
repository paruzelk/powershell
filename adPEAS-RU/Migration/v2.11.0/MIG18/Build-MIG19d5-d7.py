#!/usr/bin/env python3
"""MIG19d5-d7: sequential gated localization, no network or AD calls."""
import argparse, collections, hashlib, json, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
PINS={
"DOC4a-RuntimeMessages.ru-RU.json":"ba3596187f8a45732578d196a628dac150917df55655898031136951beb17bb2",
"StageA-HelpersADCS.ru-RU.json":"91e86f3a8c9a928641b2c90efdd8bbd9c955d096bd3325d6c039ff28a6d4142b",
"StageA-HelpersBasic.ru-RU.json":"b32f4042b4c3f96fe08578daa625ebda8a38b059c2a3fc3b68b6188c2ae73754",
"StageA-HelpersOperations1.ru-RU.json":"73db130ea1bb916fdc0846bb00e2ed85f7a3fd0a097985bf788e5dc7ab000f6a",
"StageA-HelpersOperations2.ru-RU.json":"6cade908fcd7e4f72f5ff7dc510b7c3c1ea585561faae0675b7e025f3f17e71d",
"StageA-ReportingCollector.ru-RU.json":"0f6a253d24f25ecfc7cd68963ba8d20864c37ced0d6b7690e03845c7dd5944cc",
"StageB-AccountsADCSApplications.ru-RU.json":"5823dade0fad7e48cb85009edba46365f47e74f286740bc4d98f00cd2fbbd5e4",
"StageB-Computer.ru-RU.json":"52f819be7e4c1a61e150b3ae996573ce8e2dfb429d45d6b71e2b230759a623a4",
"StageB-Credentials.ru-RU.json":"80753e17734049fc87332ef681145a5d0840597537583b850b8f379022277596",
"StageB-DomainGPORights.ru-RU.json":"4ff3678e955f8e9c2384ff64a01628aef78e529973417424f358511bb1058352",
"StageB-Shares.ru-RU.json":"48daa8a5b627b8d4f744aed3b8410eed6bc3a783210769989dd2c7cf2ef5e942",
"StageC-ComputerOperations.ru-RU.json":"ec7b3775cd7b114fdb88c58463b13cad579e748699df9c9d76dd9d4aa1c56697",
"StageC-GPOGroupOperations.ru-RU.json":"94fe74a541f9e7310ed90a660e784e54564f5c7d3fb372919b2ec97556baf7e8",
"StageC-SessionAndCoreUX.ru-RU.json":"df2a9ebc37bec25fb828baa2ce9dc333009f968373f58fe9296987098abd7e33",
"StageC-UserOperations.ru-RU.json":"36bcb487bd367a4ef28797c85425027307a5ffac4b88c446419b37be7bc13684"}
RX=re.compile(r"""^(Write-Log|Write-Warning|Write-Error|Write-Verbose|Show-Line|Show-Header|Show-SubHeader) ("(?:[^"\x60]|\x60.)*")((?:\s+(?:-Class\s+(?:\w+|"\w+")|-FindingId\s+'[A-Z0-9_]+'|-ObjectType\s+"[A-Za-z0-9_]+"|-Level\s+\w+|-NoCollect|-Raw))*)$""")
V=re.compile(r'\$\([^)]+\)|\$\{[^}]+\}|\$[A-Za-z_][\w:]*')
RU=re.compile('[А-Яа-яЁё]')
PREFIX=re.compile(r'^"\[[^\]]+\] ')
VISIBLE=re.compile(r'^\s*(?:Write-(?:Log|Warning|Error|Verbose)|Show-(?:Line|Header|SubHeader))\s+"')
HELP=re.compile(r'(?ms)^\s*\.SYNOPSIS[ \t]*\n(.*?)(?=^\s*\.[A-Z]+(?:\s|$)|#>)')
def read(p):return p.read_text(encoding='utf-8-sig')
def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def digest(obj):return hashlib.sha256(json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def prefix(x):
 m=PREFIX.match(x)
 return m.group() if m else ''
def safe(x,y):
 return (x and y and x[1]==y[1] and (not y[3] or x[3]==y[3])
         and sorted(V.findall(x[2]))==sorted(V.findall(y[2]))
         and RU.search(y[2]) and prefix(x[2])==prefix(y[2])
         and re.findall(r'\x60.',x[2])==re.findall(r'\x60.',y[2]))
def legacy(locale):
 lookup=collections.defaultdict(dict);conflicts=set()
 for name,sha in PINS.items():
  o=json.loads(read(locale/name))
  if digest(o)!=sha:raise ValueError('Legacy catalog digest changed: '+name)
  for path,rows in o['files'].items():
   for a,b in rows.items():
    a,b=a.strip(),b.strip()
    if not safe(RX.fullmatch(a),RX.fullmatch(b)):continue
    if a in lookup[path] and lookup[path][a]!=b:conflicts.add((path,a))
    lookup[path][a]=b
 for path,a in conflicts:lookup[path].pop(a,None)
 if conflicts:raise ValueError('Unexpected translation conflict')
 return lookup
def inventory(sources):
 files=[]
 for path,s in sources.items():
  candidates=[]
  for i,l in enumerate(s.splitlines(),1):
   if not VISIBLE.match(l) or RU.search(l):continue
   x=RX.fullmatch(l.strip())
   # This is an inventory, never a proof of completeness.
   role='compound-or-other'
   if x:
    literal=x[2][1:-1]
    role='dynamic-or-technical-review' if not re.search(r'[A-Za-z]{2,}\s+[A-Za-z]{2,}',V.sub('',literal)) else 'prose-review'
   candidates.append({'line':i,'text':l.strip(),'classification':role})
  helps=[{'line':s.count('\n',0,m.start())+1,'text':m.group(1).strip()} for m in HELP.finditer(s) if m.group(1).strip() and not RU.search(m.group(1))]
  if candidates or helps:files.append({'path':path,'visibleCandidates':candidates,'helpCandidates':helps})
 return {'heuristicOnly':True,'fullLocalizationCertified':False,'visibleCandidateCount':sum(len(f['visibleCandidates']) for f in files),'helpCandidateCount':sum(len(f['helpCandidates']) for f in files),'classificationCounts':dict(collections.Counter(r['classification'] for f in files for r in f['visibleCandidates'])),'files':files}
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--candidate',type=Path,required=True);p.add_argument('--locale',type=Path,required=True)
 p.add_argument('--stage',choices=['d5','d6','d7'],required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--inventory',type=Path,required=True)
 a=p.parse_args()
 data=json.loads(read(HERE/'MIG19d5-d7-Messages.json'))
 sources={f.relative_to(a.candidate).as_posix():read(f) for f in sorted((a.candidate/'src').rglob('*.ps1'))}
 stage=a.stage
 initial=inventory(sources)
 expected_before={'d5':2837,'d6':2439,'d7':2102}[stage]
 if initial['visibleCandidateCount']!=expected_before or initial['helpCandidateCount']!=862:
  raise ValueError('Unexpected baseline inventory '+str((initial['visibleCandidateCount'],initial['helpCandidateCount'])))
 lookup=legacy(a.locale) if stage=='d5' else {}
 edits=[];outputs={};extra=[]
 for path,source in sources.items():
  lines=source.splitlines(keepends=True);originals={}
  for i,l in enumerate(lines):
   old=l.strip()
   if RU.search(old) or not VISIBLE.match(l):continue
   x=RX.fullmatch(old)
   if not x:continue
   target=None
   if stage=='d5':
    rows=lookup.get(path,{})
    t=rows.get(old,rows.get(x[1]+' '+x[2]))
    y=RX.fullmatch(t) if t else None
    if safe(x,y):target=y[1]+' '+y[2]+x[3]
   elif stage=='d6':
    pref=prefix(x[2])
    body=x[2][len(pref) if pref else 1:-1]
    if body in data['common']:target=x[1]+' "'+(pref[1:] if pref else '')+data['common'][body]+'"'+x[3]
   else:
    rows=data['reports'].get(path,{})
    if x[2][1:-1] in rows:target=x[1]+' "'+rows[x[2][1:-1]]+'"'+x[3]
   if target:
    y=RX.fullmatch(target)
    if not safe(x,y) or x[3]!=y[3]:raise ValueError('Display skeleton mismatch '+old)
    originals[i]=l;start=l.index(old);lines[i]=l[:start]+target+l[start+len(old):]
    edits.append({'path':path,'line':i+1,'before':old,'after':target,'command':x[1]})
  if stage=='d7' and path=='src/modules/Reporting/Compare-adPEASReport.ps1':
   seen=set()
   for i,l in enumerate(lines):
    m=re.fullmatch(r'(Show-Output\s+(?:-Class Info -Value|-Key) )"([^"]+)"(.* -NoCollect)',l.strip())
    if not m or m[2] not in data['comparisonLabels']:continue
    new=m[1]+'"'+data['comparisonLabels'][m[2]]+'"'+m[3]
    if sorted(V.findall(m[2]))!=sorted(V.findall(data['comparisonLabels'][m[2]])):raise ValueError('Comparison interpolation')
    if m[2] in seen or i in originals:raise ValueError('Duplicate comparison label')
    seen.add(m[2]);old=l.strip();originals[i]=l;start=l.index(old);lines[i]=l[:start]+new+l[start+len(old):]
    edits.append({'path':path,'line':i+1,'before':old,'after':new,'command':'Show-Output'})
   if seen!=set(data['comparisonLabels']):raise ValueError('Comparison label coverage')
  result=''.join(lines)
  for i,l in originals.items():lines[i]=l
  if ''.join(lines)!=source:raise ValueError('Non-reversible lines '+path)
  if originals:outputs[path]=result
 if stage=='d7':
  for filename,function,old,new in data['synopsis']:
   path='src/modules/Core/'+filename+'.ps1'
   source=outputs.get(path,sources[path])
   # Witness a synopsis immediately within the named function, not a string elsewhere.
   pattern=r'(?m)(^function '+re.escape(function)+r'\s*\{\s*<#\s*\.SYNOPSIS[ \t]*\n[ \t]*)'+re.escape(old)+r'(?=[ \t]*\n)'
   if len(list(re.finditer(pattern,source)))!=1 or '\n    '+new in source:raise ValueError('Synopsis witness '+function)
   result=re.sub(pattern,lambda m:m[1]+new,source,count=1)
   if result.replace(new,old,1)!=source:raise ValueError('Synopsis reversibility '+function)
   outputs[path]=result;extra.append({'kind':'synopsis','path':path,'function':function,'before':old,'after':new})
  path='src/modules/Reporting/templates/diff-template.html'
  source=read(a.candidate/path);old='aria-label="Toggle theme"';new='aria-label="Переключить тему оформления"'
  if source.count(old)!=1 or new in source:raise ValueError('Diff accessibility anchor')
  result=source.replace(old,new,1)
  if result.replace(new,old,1)!=source:raise ValueError('Diff template reversibility')
  outputs[path]=result;extra.append({'kind':'aria-label','path':path,'before':old,'after':new})
 expected={'d5':398,'d6':337,'d7':32}[stage]
 if len(edits)!=expected or len(extra)!=(10 if stage=='d7' else 0):raise ValueError('Unexpected change counts '+str((len(edits),len(extra))))
 if stage=='d5' and (len(set((r['path'],r['before']) for r in edits))!=394 or len(outputs)!=51):raise ValueError('Legacy coverage mismatch')
 final=inventory({k:outputs.get(k,v) for k,v in sources.items()})
 expected_after={'d5':2439,'d6':2102,'d7':2081}[stage]
 if final['visibleCandidateCount']!=expected_after or final['helpCandidateCount']!=(853 if stage=='d7' else 862):raise ValueError('Unexpected residual coverage '+str((final['visibleCandidateCount'],final['helpCandidateCount'])))
 for path,s in outputs.items():
  f=a.candidate/path
  # Preserve the existing HTML encoding convention; PowerShell always UTF-8 BOM.
  bom=f.read_bytes().startswith(b'\xef\xbb\xbf') or f.suffix=='.ps1'
  f.write_bytes((b'\xef\xbb\xbf' if bom else b'')+s.encode('utf-8'))
 write(a.report,{'schema':'adPEAS-RU.MIG19'+stage+'.Source.1','stage':stage,'commandOccurrences':len(edits),'additionalChanges':len(extra),'changedFiles':len(outputs),'initialVisibleCandidates':expected_before,'remainingVisibleCandidates':expected_after,'changes':edits,'otherChanges':extra,'fileSha256':{path:hashlib.sha256((a.candidate/path).read_bytes()).hexdigest() for path in outputs},'realADTestPerformed':False,'fullLocalizationCertified':False})
 write(a.inventory,{'schema':'adPEAS-RU.MIG19'+stage+'.Residual.1',**final})
 print('PASS MIG19'+stage+': '+str(len(edits))+' display command occurrences, '+str(len(extra))+' additional changes; residual '+str(expected_after))
if __name__=='__main__':main()
