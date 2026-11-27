#!/usr/bin/env python3
"""MIG21a: isolate duplicate SID helpers; inventory witnessed text origins without AD data."""
import argparse, collections, hashlib, json, re
from pathlib import Path
CORE='src/modules/Core/ConvertFrom-LDAPAttribute.ps1'
COLLECTOR='src/modules/Collector/Invoke-adPEASCollector.ps1'
OLD='Convert-SIDToString'
NEW='Convert-LdapSidBytesToString'
def read(p): return p.read_text(encoding='utf-8-sig')
def sha(b): return hashlib.sha256(b).hexdigest()
def require(c,m):
    if not c: raise ValueError(m)
def write(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def hits(s,name): return list(re.finditer(r'\b'+re.escape(name)+r'\b',s,re.I))
def definitions(s,name): return list(re.finditer(r'(?im)^\s*function\s+'+re.escape(name)+r'\s*\{',s))
def source(root,upstream,report):
    f=root/CORE;original=f.read_bytes();s=read(f)
    u=read(upstream/CORE);collector=read(root/COLLECTOR)
    # Verify the bug on pristine upstream and on the fully localized candidate, not a guess.
    require(len(definitions(u,OLD))==1 and len(hits(u,OLD))==2,'upstream core helper references')
    require(len(definitions(read(upstream/COLLECTOR),OLD))==1,'upstream collector duplicate')
    require(len(definitions(s,OLD))==1 and len(hits(s,OLD))==2,'candidate core helper references')
    require(len(definitions(collector,OLD))==1,'candidate collector duplicate')
    require('param([byte[]]$SIDBytes)' in s and '$SidInput' in collector,'conflicting signature witnesses')
    for pattern in ('function Convert-SIDToString {','Convert-SIDToString -SIDBytes $sidBytes'):
        require(s.count(pattern)==1 and u.count(pattern)==1,'exact source anchor '+pattern)
    allfiles={p.relative_to(root).as_posix():p for p in sorted((root/'src').rglob('*.ps1'))}
    before={path:sha(p.read_bytes()) for path,p in allfiles.items()}
    refs={path:len(hits(read(p),OLD)) for path,p in allfiles.items() if hits(read(p),OLD)}
    require(set(refs)=={CORE,COLLECTOR},'unexpected SID helper references '+str(refs))
    require(not any(hits(read(p),NEW) for p in allfiles.values()),'new helper name already exists')
    # Preserve every byte other than the two exact identifier occurrences.
    require(original.count(OLD.encode())==2,'raw exact core occurrence count')
    changed=original.replace(OLD.encode(),NEW.encode())
    require(changed.replace(NEW.encode(),OLD.encode())==original,'nonreversible patch')
    f.write_bytes(changed)
    after={path:sha(p.read_bytes()) for path,p in allfiles.items()}
    require([path for path in before if before[path]!=after[path]]==[CORE],'unexpected modified file')
    require(len(definitions(read(f),NEW))==1 and not hits(read(f),OLD),'new helper definition')
    require(len(definitions(read(root/COLLECTOR),OLD))==1,'collector retained')
    data={'schema':'adPEAS-RU.MIG21a.Source.1','status':'PASS','upstreamCollisionConfirmed':True,
          'beforeReferences':refs,'modifiedFiles':[CORE],'renamedDefinitionAndCall':2,
          'beforeSha256':before[CORE],'afterSha256':after[CORE],
          'collectorSha256Unchanged':before[COLLECTOR]==after[COLLECTOR],
          'conversionAlgorithmChanged':False,'productionReady':False}
    write(report,data)
    print('PASS MIG21a source: case-insensitive SID collision confirmed upstream; two identifier edits only')
# Known report phrases are curated constants, not raw reports or customer data.
PHRASES={
 'Unchanged, never used':'generated verdict; scoring-sensitive: display only',
 'Unchanged, in use':'generated verdict; scoring-sensitive: display only',
 'Windows Firewall disabled via GPO':'generated vulnerability label; display only until consumers verified',
 'Credential mention (needs review)':'generated credential context candidate; trace exact/partial source, not AD evidence',
 'Dormant policies':'generated GPO group label; display only',
 'Enabled - QUARANTINED_DOMAIN set':'generated trust status; preserve flag token and raw value',
 'Found possible sensitive information':'generated finding headline; display only',
 'Collection failed':'generated diagnostic prefix; exception suffix from runtime',
 'No LDAP Security configuration found in any GPO':'generated diagnostic with interpolated count',
 'Not configured':'ambiguous: generated value, OS data or AD text; field-scoped review',
 'Not set':'ambiguous: generated value, OS data or AD text; field-scoped review',
 'Authentication failed':'generated diagnostic prefix; exception suffix from runtime',
}
def origin(root,report):
    files={p.relative_to(root).as_posix():read(p) for p in sorted((root/'src').rglob('*')) if p.is_file() and p.suffix.lower() in ('.ps1','.js','.html')}
    rows=[]
    for phrase,classification in PHRASES.items():
        found=[]
        for path,s in files.items():
            for line,text in enumerate(s.splitlines(),1):
                if phrase.casefold() in text.casefold():
                    found.append({'path':path,'line':line,'context':text.strip()[:500]})
        rows.append({'phrase':phrase,'classification':classification,'sourceMatchCount':len(found),'sourceMatches':found,
                     'reviewRequired':True})
    verdict=next(r for r in rows if r['phrase']=='Unchanged, never used')
    require(any('Pattern' in m['context'] and 'Severity' in m['context'] for m in verdict['sourceMatches']),'severity-consumer witness missing')
    require(any('$verdict' in m['context'] for m in verdict['sourceMatches']),'producer witness missing')
    write(report,{'schema':'adPEAS-RU.MIG21a.TextOrigin.1','status':'PASS','rows':rows,
                  'noMatchMeansADData':False,'rawReportsIncluded':False,'translationApplied':False,
                  'classificationIsManualReviewNotProof':True,'productionReady':False})
    print('PASS MIG21a origin: curated phrase source locations and password verdict scoring witness')
def main():
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--upstream',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    p.add_argument('--origin-report',type=Path,required=True);a=p.parse_args()
    source(a.candidate,a.upstream,a.report);origin(a.candidate,a.origin_report)
if __name__=='__main__':main()
