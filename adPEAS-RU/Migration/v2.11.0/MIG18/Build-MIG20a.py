#!/usr/bin/env python3
"""MIG20a: exact display-only corrections, original source witnesses and runtime evidence."""
import argparse, hashlib, json, re, runpy
from pathlib import Path
HERE=Path(__file__).resolve().parent
JS='src/modules/Reporting/templates/report-scripts.js'
DIFF='src/modules/Reporting/templates/diff-template.html'
CORE='src/modules/Core/adPEAS-ObjectTypes.ps1'
OLD_SHA='8fa52f56018c80bdc19b72a7be781b26fbb74650c8570aa4a313b028f11a2c62'
NAME='ruMIG2CheckDetails'
IDS={'ComputerInitialPassword','GPOLogonRestriction','GPOUserRightValue'}
def read(p): return p.read_text(encoding='utf-8-sig')
def sha(s): return hashlib.sha256(s.encode('utf-8')).hexdigest()
def require(c,msg):
    if not c: raise ValueError(msg)
def compact(obj):
    return json.dumps(obj,ensure_ascii=False,separators=(',',':'))
def extract(s):
    m=list(re.finditer(r'\bconst '+NAME+r'\s*=\s*(\{[^\r\n]+\});',s))
    require(len(m)==1,'catalog declaration count')
    return m[0]
def data():
    d=json.loads(read(HERE/'MIG20a-Translations.json'))
    require(set(d['rows'])==IDS,'unexpected translation IDs')
    return d['rows']
def source(root,upstream,report):
    rows=data()
    pinned=runpy.run_path(str(HERE/'Build-MIG18Integration.py'))
    js=read(root/JS);pinned['verify_catalogs'](js)
    original=read(upstream/CORE)
    m=extract(js);before=m[1];after=before
    require(sha(before)==OLD_SHA,'old digest')
    old=json.loads(before)
    expected=json.loads(before)
    for k,row in rows.items():
        require(original.count(row['upstreamBlock'])==1,'upstream block mismatch '+k)
        require(old[k]==row['before'],'old translation mismatch '+k)
        require(set(row['before'])==set(row['after'])=={'whyItMatters','whatWeCheck','secureMessage'},'field scope '+k)
        require(len(row['before']['whatWeCheck'])==len(row['after']['whatWeCheck']),'list size '+k)
        a=compact(k)+':'+compact(row['before']);b=compact(k)+':'+compact(row['after'])
        require(after.count(a)==1,'exact row anchor '+k)
        after=after.replace(a,b,1);expected[k]=row['after']
    require(json.loads(after)==expected,'unexpected catalog data change')
    reverse=after
    for k,row in rows.items():
        a=compact(k)+':'+compact(row['before']);b=compact(k)+':'+compact(row['after'])
        require(reverse.count(b)==1,'reverse anchor '+k)
        reverse=reverse.replace(b,a,1)
    require(reverse==before,'nonreversible catalog patch')
    new_js=js[:m.start(1)]+after+js[m.end(1):]
    template=read(root/DIFF)
    require(template.count('alt="adPEAS Logo"')==1,'diff alt anchor')
    new_template=template.replace('alt="adPEAS Logo"','alt="Логотип adPEAS"',1)
    # Preserve UTF-8 BOM and line endings exactly outside approved edits.
    for path,text in ((JS,new_js),(DIFF,new_template)):
        f=root/path;raw=f.read_bytes();newline='\r\n' if b'\r\n' in raw else '\n'
        f.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+text.replace('\n',newline).encode('utf-8'))
    approved=sha(after)
    pinned['verify_catalogs'](new_js,approved)
    result={'schema':'adPEAS-RU.MIG20a.Source.1','status':'PASS','beforeCheckCatalogSha256':OLD_SHA,
            'afterCheckCatalogSha256':approved,'changedIds':sorted(IDS),'changedFieldsPerId':3,
            'diffLogoAltLocalized':True,'upstreamWitnessesVerified':True,'sourcePatchReversible':True,
            'scannerLogicChanged':False,'productionReady':False}
    report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS MIG20a: three check descriptions, three lists, three secure messages and one diff alt; exact upstream witnesses')
def runtime(diag,source_report,report):
    rows=data();e=json.loads(read(source_report));approved=e['afterCheckCatalogSha256']
    pinned=runpy.run_path(str(HERE/'Build-MIG18Integration.py'))
    results=[]
    for variant in ('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe'):
        html=read(diag/variant/'report.html');pinned['verify_catalogs'](html,approved)
        translated=json.loads(extract(html)[1])
        for k,row in rows.items():require(translated[k]==row['after'],'runtime text mismatch '+variant+' '+k)
        diff=read(diag/variant/'report.comparison.html')
        require('alt="Логотип adPEAS"' in diff and 'alt="adPEAS Logo"' not in diff,'diff alt mismatch '+variant)
        results.append({'variant':variant,'status':'PASS','checkCatalogSha256':approved})
    report.write_text(json.dumps({'schema':'adPEAS-RU.MIG20a.Runtime.1','status':'PASS','results':results,'realADTestPerformed':False,'productionReady':False},indent=2)+'\n',encoding='utf-8')
    print('PASS MIG20a runtime: exact corrected catalog and comparison alt in all five variants')
def main():
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path);p.add_argument('--upstream',type=Path)
    p.add_argument('--diagnostics',type=Path);p.add_argument('--source-report',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    if a.diagnostics and a.source_report:runtime(a.diagnostics,a.source_report,a.report)
    elif a.candidate and a.upstream:source(a.candidate,a.upstream,a.report)
    else:p.error('source or runtime inputs required')
if __name__=='__main__':main()
