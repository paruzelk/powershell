#!/usr/bin/env python3
"""MIG20 read-only localization evidence; candidates are not translation verdicts."""
import argparse, collections, hashlib, json, re, runpy
from html.parser import HTMLParser
from pathlib import Path
HERE=Path(__file__).resolve().parent
RU=re.compile(r'[А-Яа-яЁё]')
EN=re.compile(r'[A-Za-z]{2,}')
PROSE=re.compile(r'\b[A-Za-z]{2,}\s+[A-Za-z]{2,}\b')
VARIABLE=re.compile(r'\$\([^\r\n)]*\)|\$\{[^}]*\}|\$[\w:]+')
TECH=re.compile(r'^(?:[A-Z0-9_.:/\\ -]+|[A-Za-z][\w.-]*|S-\d+(?:-\d+)+)$')
NAMES=('ruMIG1Titles','ruMIG2Technical','ruMIG2CheckDetails','ruMIG14RemediationLabels','ruMIG15CommentLines')
VARIANTS=('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')
def read(p): return p.read_text(encoding='utf-8-sig')
def write(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def hashbytes(b): return hashlib.sha256(b).hexdigest()
def digest(v): return hashbytes(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())
def require(c,msg):
    if not c: raise ValueError(msg)
def language(value):
    t=VARIABLE.sub('',value).strip()
    if not t: return 'empty-or-dynamic'
    if RU.search(t):
        return 'mixed-prose-review' if PROSE.search(t) else 'russian-with-technical-tokens' if EN.search(t) else 'russian'
    if not EN.search(t): return 'non-prose'
    if PROSE.search(t): return 'english-prose-review'
    if TECH.fullmatch(t): return 'technical-or-name-review'
    return 'other-english-review'
def leaves(v,path=()):
    if isinstance(v,str): yield path,v
    elif isinstance(v,dict):
        for k,x in v.items(): yield from leaves(x,path+(k,))
    elif isinstance(v,list):
        for i,x in enumerate(v): yield from leaves(x,path+(i,))
def catalog(s,name):
    m=re.findall(r'\bconst '+re.escape(name)+r'\s*=\s*([^\r\n]+);[ \t]*$',s,re.M)
    require(len(m)==1,'missing/duplicate catalog '+name)
    return json.loads(m[0])
def inspect_catalog(s,name):
    value=catalog(s,name)
    counts=collections.Counter()
    review=[]
    for path,text in leaves(value):
        cls=language(text);counts[cls]+=1
        if 'review' in cls or cls=='empty-or-dynamic':
            review.append({'path':list(path),'classification':cls,'text':text})
    return {'entries':len(value),'sha256':digest(value),'stringCounts':dict(counts),'review':review}
class StaticHtml(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True);self.ignored=[];self.rows=[]
    def check(self,text,kind):
        text=text.strip()
        cls=language(text)
        if text and 'review' in cls:
            self.rows.append({'line':self.getpos()[0],'kind':kind,'classification':cls,'text':text})
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style'): self.ignored.append(tag)
        if not self.ignored:
            for k,v in attrs:
                if k in ('title','aria-label','placeholder','alt') and v: self.check(v,k)
    def handle_endtag(self,tag):
        if self.ignored and tag==self.ignored[-1]: self.ignored.pop()
    def handle_data(self,text):
        if not self.ignored: self.check(text,'text')
def source_audit(root,upstream,report):
    integration=runpy.run_path(str(HERE/'Build-MIG18Integration.py'))
    prior=runpy.run_path(str(HERE/'Build-MIG19d5-d7.py'))
    paths=sorted((root/'src').rglob('*'))
    snapshot={f.relative_to(root).as_posix():hashbytes(f.read_bytes()) for f in paths if f.is_file()}
    core='src/modules/Core/adPEAS-FindingDefinitions.ps1'
    require(read(root/core)==read(upstream/core),'canonical finding source differs')
    js=read(root/'src/modules/Reporting/templates/report-scripts.js')
    pins=integration['verify_catalogs'](js)
    ps={f.relative_to(root).as_posix():read(f) for f in paths if f.is_file() and f.suffix=='.ps1'}
    inv=prior['inventory'](ps)
    templates={}
    for f in paths:
        if f.is_file() and f.suffix=='.html':
            parser=StaticHtml();parser.feed(read(f));parser.close()
            templates[f.relative_to(root).as_posix()]=parser.rows
    # Wider source candidate scan: includes mixed prose, single quotes, variable and compound
    # expressions. It is deliberately not equivalent to the old double-quote line inventory.
    candidates=[]
    visible=re.compile(r'\b(?:Write-(?:Host|Output|Log|Warning|Error|Verbose|Information|Debug)|Show-(?:Line|Header|SubHeader|Output|Object)|throw)\b',re.I)
    for path,s in ps.items():
        for line,text in enumerate(s.splitlines(),1):
            if text.lstrip().startswith('#') or not visible.search(text): continue
            # only actual text-looking quoted fragments; AST inventory is separate.
            for m in re.finditer(r""" "(?:[^"\x60]|\x60.)*" | '(?:[^']|'')*' """,text,re.X):
                t=m.group()[1:-1];cls=language(t)
                if 'review' in cls:
                    candidates.append({'path':path,'line':line,'classification':cls,'text':t})
    require(snapshot=={f.relative_to(root).as_posix():hashbytes(f.read_bytes()) for f in paths if f.is_file()},'audit mutated source')
    data={'schema':'adPEAS-RU.MIG20.Source.1','status':'PASS','fullLocalizationCertified':False,
          'canonicalFindingSourceUnchanged':True,'pinnedCatalogs':pins,'catalogReview':{n:inspect_catalog(js,n) for n in NAMES},
          'priorComparableInventory':inv,'priorD7Baseline':{'visibleCandidateCount':2081,'helpCandidateCount':853},
          'expandedLineCandidates':candidates,'expandedLineClassificationCounts':dict(collections.Counter(r['classification'] for r in candidates)),
          'staticHtmlCandidates':templates,'sourceSha256':snapshot,'sourceModifiedByAudit':False,'productionReady':False}
    write(report,data)
    print('PASS MIG20 source: pinned catalogs and canonical finding source; residual candidates',inv['visibleCandidateCount'],inv['helpCandidateCount'])
def runtime_audit(diag,report):
    results=[];reference=None
    for variant in VARIANTS:
        html=read(diag/variant/'report.html')
        blobs={n:catalog(html,n) for n in ('findingDefinitions','checkDescriptions')+NAMES}
        signatures={n:digest(v) for n,v in blobs.items()}
        if reference is None:
            reference=signatures
            canonical=blobs['findingDefinitions'];tech=blobs['ruMIG2Technical'];titles=blobs['ruMIG1Titles']
            checks=blobs['checkDescriptions'];ruchecks=blobs['ruMIG2CheckDetails']
            require(set(canonical)==set(tech),'technical catalog ID mismatch')
            require(len(canonical)==408 and len(checks)==128,'canonical counts')
            findings=[]
            for id_,row in sorted(canonical.items()):
                trans=tech[id_];title=row.get('title');fields={}
                for name in ('description','attack','impact','remediation'):
                    orig=row.get(name);ru=trans.get(name)
                    fields[name]={'sourceCount':len(orig) if isinstance(orig,list) else int(bool(orig)),
                                  'translationCount':len(ru) if isinstance(ru,list) else int(bool(ru)),
                                  'sameType':type(orig)==type(ru),'exactEnglishRetained':bool(orig) and orig==ru,
                                  'translationLanguageCounts':dict(collections.Counter(language(t) for _,t in leaves(ru)))}
                findings.append({'id':id_,'titleMapped':title in titles if isinstance(title,str) else False,'fields':fields})
            checkrows=[]
            for id_,row in sorted(checks.items()):
                trans=ruchecks.get(id_,{});fields={}
                for name in ('whyItMatters','whatWeCheck','secureMessage'):
                    orig=row.get(name);ru=trans.get(name)
                    if orig:
                        fields[name]={'translationPresent':bool(ru),'exactEnglishRetained':orig==ru,
                                      'translationLanguageCounts':dict(collections.Counter(language(t) for _,t in leaves(ru)))}
                checkrows.append({'id':id_,'translationEntryPresent':id_ in ruchecks,'fields':fields})
            review={n:inspect_catalog(html,n) for n in NAMES}
        require(signatures==reference,'runtime catalog parity mismatch: '+variant)
        results.append({'variant':variant,'catalogHashes':signatures,'parity':'MATCH'})
    data={'schema':'adPEAS-RU.MIG20.Runtime.1','status':'PASS','fullLocalizationCertified':False,
          'variants':results,'findingRows':findings,'checkRows':checkrows,'catalogReview':review,
          'findingTitleMappingsMissing':[r['id'] for r in findings if not r['titleMapped']],
          'findingFieldReview':[{'id':r['id'],'field':k,**v} for r in findings for k,v in r['fields'].items()
             if not v['sameType'] or v['sourceCount']!=v['translationCount'] or v['exactEnglishRetained'] or any('review' in c for c in v['translationLanguageCounts'])],
          'checkFieldReview':[{'id':r['id'],'field':k,**v} for r in checkrows for k,v in r['fields'].items()
             if not v['translationPresent'] or v['exactEnglishRetained'] or any('review' in c for c in v['translationLanguageCounts'])],
          'realADTestPerformed':False,'productionReady':False}
    write(report,data)
    print('PASS MIG20 runtime: 408 finding rows, 128 check rows, five catalog parity witnesses; review rows',len(data['findingFieldReview']),len(data['checkFieldReview']))
def main():
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path);p.add_argument('--upstream',type=Path)
    p.add_argument('--diagnostics',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    if a.diagnostics: runtime_audit(a.diagnostics,a.report)
    elif a.candidate and a.upstream: source_audit(a.candidate,a.upstream,a.report)
    else: p.error('source or runtime inputs required')
if __name__=='__main__': main()
