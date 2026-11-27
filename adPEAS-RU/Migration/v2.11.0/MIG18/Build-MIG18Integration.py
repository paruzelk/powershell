#!/usr/bin/env python3
"""Apply verified MIG12-17 source patches to a fresh MIG11 candidate. No AD access."""
import argparse, hashlib, json, re, subprocess, sys, tempfile, shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent
BOM=b'\xef\xbb\xbf'
EXPECTED={'ruMIG1Titles':(408,'987ab121880302364f00e53c7e3d8287c95b9951c8340eac2d00f31f7789f32b'),'ruMIG2Technical':(408,'5f2e3a96aef9671d4cd81e1b76efa46b8d05a8b856527e69f8b9e31e66a91c5a'),'ruMIG2CheckDetails':(128,'8fa52f56018c80bdc19b72a7be781b26fbb74650c8570aa4a313b028f11a2c62'),'ruMIG14RemediationLabels':(586,'2f362831a447c0d5944a1a92a0f53fa79ffd4bc45bb5ffc8b1dcd84f460fb24c'),'ruMIG15CommentLines':(169,'9c91a36a1e737c8a138c2ec76e93718fbe43a98fc4c4cd61f05f74a24dbadf5b')}
def sha(b):return hashlib.sha256(b).hexdigest()
def run(n,*args):subprocess.run([sys.executable,str(HERE/f'Build-MIG{n}Preview.py'),*map(str,args)],check=True)
def verify_catalogs(s,approved_check_sha=None):
 expected=dict(EXPECTED)
 if approved_check_sha is not None:
  if not re.fullmatch(r'[0-9a-f]{64}',approved_check_sha):raise ValueError('Invalid approved check digest')
  expected['ruMIG2CheckDetails']=(128,approved_check_sha)
 for name,(count,digest) in expected.items():
  m=list(re.finditer(r'\bconst '+name+r'\s*=\s*(\{[^\r\n]+\});',s))
  if len(m)!=1 or sha(m[0][1].encode())!=digest or len(json.loads(m[0][1]))!=count:raise ValueError('Catalog mismatch: '+name)
 return {n:{'count':c,'sha256':h} for n,(c,h) in expected.items()}
def integrate(root,upstream,report):
 root=root.resolve();upstream=upstream.resolve();report=report.resolve()
 if root==upstream or root in upstream.parents or upstream in root.parents:raise ValueError('Separate source trees required')
 # Work on a staged copy. On failure leave MIG11 candidate untouched.
 with tempfile.TemporaryDirectory(prefix='mig18-',dir=root.parent) as td:
  stage=Path(td)/'candidate';shutil.copytree(root,stage)
  core=Path('src/modules/Core/adPEAS-FindingDefinitions.ps1');js=Path('src/modules/Reporting/templates/report-scripts.js')
  canonical=(stage/core).read_bytes()
  for n in [12,13]:run(n,'--candidate',stage,'--report',Path(td)/f'2.11.0-mig{n}-coverage.json')
  run(14,'--candidate',stage,'--localization',HERE/'Localization-MIG14','--report',Path(td)/'2.11.0-mig14-coverage.json')
  run(15,'--candidate',stage,'--catalog',HERE/'Localization-MIG15/CommandCommentLines.ru-RU.json')
  run(16,'--candidate',stage,'--manifest',HERE/'MIG16-Terminology.json')
  assert (stage/core).read_bytes()==canonical,'Canonical definitions changed'
  assert canonical.decode('utf-8-sig').replace('\r\n','\n')==(upstream/core).read_bytes().decode('utf-8-sig').replace('\r\n','\n'),'Canonical source differs from upstream'
  catalogs=verify_catalogs((stage/js).read_text(encoding='utf-8-sig'))
  # MIG17 must see pristine pinned build files (MIG1 may have added BOM/CRLF).
  patched=Path(td)/'mig17';run(17,'--upstream',upstream,'--out',patched)
  for name in ('Build-Engine.ps1','Build-Release.ps1'):
   assert (stage/name).read_text(encoding='utf-8-sig')==(upstream/name).read_text(encoding='utf-8-sig'), 'Existing build changes: '+name
   shutil.copy2(patched/name,stage/name)
  shutil.copy2(HERE/'README-RU-2.11.0.md',stage/'README-RU-2.11.0.md')
  # Only known source files and README may change.
  changed=[]
  for f in stage.rglob('*'):
   if f.is_file():
    rel=f.relative_to(stage);old=root/rel
    if not old.exists() or f.read_bytes()!=old.read_bytes():changed.append(str(rel).replace('\\','/'))
  assert set(changed)<= {'Build-Engine.ps1','Build-Release.ps1','README-RU-2.11.0.md',str(js).replace('\\','/')} | {str(f.relative_to(stage)).replace('\\','/') for f in stage.joinpath('src').rglob('*.ps1')}
  for n in changed:
   f=stage/n
   if f.suffix in ('.ps1','.psm1','.psd1'):assert f.read_bytes().startswith(BOM),n
  result={'schema':'adPEAS-RU.2.11.0.MIG18.Source.1','catalogs':catalogs,'canonicalSha256':sha(canonical),'changedFiles':sorted(changed),'MIG17':json.loads((patched/'MIG17-patch-result.json').read_text()),'realADTestPerformed':False,'productionReady':False}
  # No deletions; install only changed files after all validation gates.
  for n in changed:shutil.copy2(stage/n,root/n)
  report.parent.mkdir(parents=True,exist_ok=True)
  for f in Path(td).glob('2.11.0-mig*-coverage.json'):shutil.copy2(f,report.parent/f.name)
  report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
  print('PASS MIG18 source integration, exact catalogs and canonical definitions')
def verify_build(root,report,approved_check_sha=None):
 files={}
 for name in ['adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe']:
  raw=(root/name).read_bytes();assert raw,name
  if name.endswith('.ps1'):
   assert raw.startswith(BOM),name+' BOM'
   if name!='adPEAS_obf.ps1':verify_catalogs(raw.decode('utf-8-sig'),approved_check_sha)
  else:assert raw.startswith(b'MZ'),name+' PE signature'
  files[name]={'length':len(raw),'sha256':sha(raw)}
 report.write_text(json.dumps({'schema':'adPEAS-RU.2.11.0.MIG18.Build.1','files':files,'realADTestPerformed':False,'productionReady':False},indent=2)+'\n',encoding='utf-8')
 print('PASS five files, three readable catalog witnesses, hashes and signatures')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--upstream',type=Path);p.add_argument('--report',type=Path,required=True);p.add_argument('--verify-build',action='store_true');p.add_argument('--mig20a-source',type=Path);a=p.parse_args()
 if a.verify_build:
  approved=None
  if a.mig20a_source:
   evidence=json.loads(a.mig20a_source.read_text(encoding='utf-8-sig'))
   if evidence.get('schema')!='adPEAS-RU.MIG20a.Source.1' or evidence.get('status')!='PASS' or evidence.get('beforeCheckCatalogSha256')!=EXPECTED['ruMIG2CheckDetails'][1]:raise ValueError('Invalid MIG20a source evidence')
   approved=evidence['afterCheckCatalogSha256']
  verify_build(a.candidate,a.report,approved)
 else:
  if not a.upstream:p.error('--upstream required for integration')
  integrate(a.candidate,a.upstream,a.report)
