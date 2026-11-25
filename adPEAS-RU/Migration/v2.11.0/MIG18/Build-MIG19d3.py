#!/usr/bin/env python3
"""MIG19d3: source-witnessed, presentation-only diagnostic localization."""
import argparse,hashlib,json,re
from collections import Counter
from pathlib import Path
HERE=Path(__file__).resolve().parent
EXPECTED={
 'src/modules/Helpers/Invoke-HTTPRequest.ps1':(124,128),
 'src/modules/Core/Connect-adPEAS.ps1':(14,16),
 'src/modules/Helpers/Get-adPEASSession.ps1':(8,9)
}
# Only single display commands with double-quoted message literals and unchanged suffixes.
LINE=re.compile(r'^(Write-Log|Show-Line|Show-SubHeader) ("(?:[^"\x60]|\x60.)*")((?:\s+-Class\s+\w+|\s+-Level\s+\w+)?)$')
VARS=re.compile(r'\$\([^)]+\)|\$\{[^}]+\}|\$[A-Za-z_][\w:]*')
RU=re.compile(r'[А-Яа-яЁё]')
VISIBLE=re.compile(r'^\s*(?:Write-(?:Log|Warning|Error|Verbose)|Show-(?:Line|Header|SubHeader))\s+"')
def read(p):return p.read_text(encoding='utf-8-sig')
def write(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--candidate',type=Path,required=True)
 p.add_argument('--report',type=Path,required=True)
 p.add_argument('--inventory',type=Path,required=True)
 a=p.parse_args()
 catalog=HERE/'MIG19d3-DisplayMessages.json'
 rules=json.loads(read(catalog))
 if set(rules)!=set(EXPECTED):raise ValueError('Unexpected source groups')
 outputs={};stats={}
 for name,rows in rules.items():
  expected=EXPECTED[name]
  if (len(rows),sum(r[2] for r in rows))!=expected:raise ValueError('Catalog count '+name)
  source=read(a.candidate/name)
  lines=source.splitlines(keepends=True);lookup={}
  for old,new,count in rows:
   x,y=LINE.fullmatch(old),LINE.fullmatch(new)
   if not x or not y or x[1]!=y[1] or x[3]!=y[3] or old==new or not RU.search(new):
    raise ValueError('Not display-only: '+old)
   if sorted(VARS.findall(x[2]))!=sorted(VARS.findall(y[2])):raise ValueError('Interpolation mismatch '+old)
   if x[1]=='Write-Log':
    prefix=lambda z:re.match(r'^"\[[^\]]+\] ',z)
    u,v=prefix(x[2]),prefix(y[2])
    if not u or not v or u.group()!=v.group():raise ValueError('Log source prefix changed '+old)
   if old in lookup:raise ValueError('Duplicate old literal '+old)
   lookup[old]=(new,count)
  actual=Counter(l.strip() for l in lines)
  for old,(new,count) in lookup.items():
   if actual[old]!=count or actual[new]!=0:raise ValueError('Source witness '+name+': '+old+' expected='+str(count)+' actual='+str(actual[old]))
  replacements={}
  for i,line in enumerate(lines):
   old=line.strip()
   if old in lookup:
    new=lookup[old][0]
    start=line.index(old)
    replacements[i]=line
    lines[i]=line[:start]+new+line[start+len(old):]
  if len(replacements)!=expected[1]:raise ValueError('Replacement count '+name)
  result=''.join(lines)
  for i,old in replacements.items():lines[i]=old
  if ''.join(lines)!=source:raise ValueError('Non-reversible source changes '+name)
  outputs[name]=result
  stats[name]={'unique':expected[0],'occurrences':expected[1],'sha256':hashlib.sha256(b'\xef\xbb\xbf'+result.encode()).hexdigest()}
 # Inventory current sources, not stale earlier source snapshots.
 inventory=[]
 for path in sorted((a.candidate/'src').rglob('*.ps1')):
  name=path.relative_to(a.candidate).as_posix()
  s=outputs.get(name)
  if s is None:s=read(path)
  hits=[{'line':i,'text':l.strip()} for i,l in enumerate(s.splitlines(),1) if VISIBLE.match(l) and not RU.search(l)]
  helps=[]
  for m in re.finditer(r'(?ms)^\s*\.SYNOPSIS[ \t]*\n(.*?)(?=^\s*\.[A-Z]+(?:\s|$)|#>)',s):
   synopsis=m.group(1).strip()
   if synopsis and not RU.search(synopsis):helps.append({'line':s.count('\n',0,m.start())+1,'text':synopsis})
  if hits or helps:inventory.append({'path':name,'visibleCandidates':hits,'helpCandidates':helps})
 for name,s in outputs.items():(a.candidate/name).write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
 write(a.inventory,{'schema':'adPEAS-RU.MIG19d3.ResidualInventory.1','heuristicOnly':True,'visibleCandidateCount':sum(len(f['visibleCandidates']) for f in inventory),'helpCandidateCount':sum(len(f['helpCandidates']) for f in inventory),'files':inventory})
 write(a.report,{'schema':'adPEAS-RU.MIG19d3.Source.1','catalogSha256':hashlib.sha256(catalog.read_bytes()).hexdigest(),'uniqueMessages':sum(x[0] for x in EXPECTED.values()),'occurrences':sum(x[1] for x in EXPECTED.values()),'files':stats,'canonicalDefinitionsModified':False,'realADTestPerformed':False,'fullLocalizationCertified':False})
 print('PASS MIG19d3: 146 unique display messages / 153 occurrences; reversible source witnesses')
if __name__=='__main__':main()
