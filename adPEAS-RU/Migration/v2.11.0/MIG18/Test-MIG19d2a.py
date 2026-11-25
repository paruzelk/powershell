#!/usr/bin/env python3
"""MIG19b-c: public offline converter, identical fixture, all five variants."""
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys
from pathlib import Path
from datetime import datetime
from html.parser import HTMLParser

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('mig19a4',HERE/'Test-MIG19a4.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
def read(p):return p.read_text(encoding='utf-8-sig')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def digest(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def require(c,msg):
    if not c:raise ValueError(msg)
def normalize_cache(c):
    c=dict(c);require('ExportDate' in c,'missing ExportDate')
    datetime.fromisoformat(c.pop('ExportDate').replace('Z','+00:00'))
    rows=[]
    for f in c['Findings']:
        f=dict(f)
        f['Timestamp']=datetime.fromisoformat(f['Timestamp'].replace('Z','+00:00')).timestamp()
        rows.append(f)
    c['Findings']=rows
    return c
class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.cards=[];self.current=None;self.depth=0;self.scripts=[];self.script=None
        self.objects=0;self.summary={};self.summary_kind=None;self.summary_value=False
    def handle_starttag(self,tag,attrs):
        a=dict(attrs);classes=a.get('class','').split()
        if tag=='script':self.script=[]
        if 'summary-card' in classes:
            self.summary_kind=next((k for k in ('finding','hint','note','secure') if k in classes),None)
        if self.summary_kind and 'value' in classes:self.summary_value=True
        if 'finding-card' in classes:
            require(self.current is None,'nested finding cards');self.current=[];self.depth=0
        if self.current is not None:
            self.current.append(('start',tag,sorted(attrs)))
            if tag not in {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}:self.depth+=1
            if 'object-detail' in classes:self.objects+=1
    def handle_endtag(self,tag):
        if tag=='script' and self.script is not None:self.scripts.append(''.join(self.script));self.script=None
        if self.current is not None:
            self.current.append(('end',tag));self.depth-=1
            if self.depth==0:self.cards.append(self.current);self.current=None
        if tag=='button':self.summary_kind=None;self.summary_value=False
    def handle_data(self,data):
        if self.script is not None:self.script.append(data)
        if self.current is not None and data.strip():self.current.append(('text',data.strip()))
        if self.summary_kind and self.summary_value and data.strip().isdigit():
            self.summary[self.summary_kind]=int(data.strip());self.summary_value=False
def normalize_cards(cards):
    ids={}
    for card in cards:
        for event in card:
            if event[0]=='start':
                for k,v in event[2]:
                    if k=='id' and v and re.fullmatch(r'(?:fc|obj)-[0-9a-f]{8}',v):
                        token=v.split('-',1)[1];require(token not in ids,'duplicate generated ID');ids[token]='DYNAMIC_ID_'+str(len(ids))
    pattern=re.compile(r'(?<![0-9a-f])(?:'+'|'.join(map(re.escape,ids))+r')(?![0-9a-f])') if ids else None
    def norm(v):return pattern.sub(lambda m:ids[m.group(0)],v) if pattern and v else v
    return [[(e[0],e[1],[(k,norm(v)) for k,v in e[2]]) if e[0]=='start' else e for e in c] for c in cards]
def check_html(path,folder):
    raw=read(path);p=ReportParser();p.feed(raw);p.close()
    require(p.current is None,'unclosed card')
    require(len(p.cards)==4 and p.objects==2,'expected four cards and two objects')
    require(p.summary=={'finding':2,'hint':1,'note':1,'secure':1},'summary count mismatch: '+str(p.summary))
    require('fixture.invalid' in raw and 'MIG19bc-FINDING' in raw and 'MIG19bc-NOTE' in raw and 'MIG19bc-SECURE' in raw,'missing HTML fixture markers')
    require('Русский текст &amp; &lt;tag&gt; $123' in raw,'HTML value escaping mismatch')
    require('lang="ru"' in raw,'Russian HTML language missing')
    require('Пароль необязателен: MIG19bc-User-1' in raw and 'Пароль необязателен: MIG19bc-User-2' in raw,'Russian object title missing')
    require('Password Not Required: MIG19bc-User-1' not in raw,'English object title remains')
    require(not re.search(r'\{\{(?:DOMAIN|SERVER|USER|GENERATED|VERSION|FINDING_DEFINITIONS_JSON|CHECK_DESCRIPTIONS_JSON|SCORING_CONTEXT_JSON|FINDINGS_SECTIONS|CSS_CONTENT|JS_CONTENT)\}\}',raw),'unresolved template token')
    blobs={}
    counts={'findingDefinitions':408,'checkDescriptions':128,'ruMIG1Titles':408,'ruMIG2Technical':408,'ruMIG2CheckDetails':128,'ruMIG14RemediationLabels':586,'ruMIG15CommentLines':169}
    for name in list(counts)+['scoringContext']:
        matches=re.findall(r'\bconst '+name+r'\s*=\s*([^\r\n]+);[ \t]*$',raw,re.M)
        require(len(matches)==1,'missing/duplicate JS catalog: '+name)
        blobs[name]=json.loads(matches[0])
        if name in counts:require(len(blobs[name])==counts[name],'catalog count: '+name)
    require(len(blobs['scoringContext']['findingCards'])==4,'scoring card count')
    require(len(blobs['scoringContext']['accounts'])==2,'scoring account count')
    require(len(p.scripts)>=2,'missing report scripts')
    for i,s in enumerate(p.scripts):
        f=folder/f'inline-{i}.js';f.write_text(s,encoding='utf-8')
        r=subprocess.run(['node','--check',str(f)],capture_output=True,timeout=60)
        require(r.returncode==0,'JS syntax error: '+str(i)+' '+r.stderr.decode(errors='replace')[-2000:])
    return {'cards':normalize_cards(p.cards),'summary':p.summary,'catalogHashes':{k:digest(v) for k,v in blobs.items()},'scriptCount':len(p.scripts)}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--diagnostics',type=Path,required=True);ap.add_argument('--report',type=Path,required=True);a=ap.parse_args()
    root=a.candidate.resolve(strict=True);diag=a.diagnostics.resolve();diag.mkdir(parents=True,exist_ok=False)
    fixture=HERE/'MIG19bc-Fixture.json';input_hash=sha(fixture);expected=normalize_cache(json.loads(read(fixture)))
    ps=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe';probe=HERE/'Probe-MIG19d2a.ps1'
    results=[]
    for v in h.VARIANTS:
        folder=diag/v;folder.mkdir();base=folder/'report'
        if v=='adPEAS.exe':
            cmd='& '+h.quote_ps(probe)+' -Candidate '+h.quote_ps(root)+' -Variant '+h.quote_ps(v)+' -InputJson '+h.quote_ps(fixture)+' -OutputBase '+h.quote_ps(base)
            argv=[str(root/v),'-Command',cmd]
        else:argv=[str(ps),'-NoLogo','-NoProfile','-NonInteractive','-File',str(probe),'-Candidate',str(root),'-Variant',v,'-InputJson',str(fixture),'-OutputBase',str(base)]
        out=folder/'stdout.txt';err=folder/'stderr.txt';proc=h.run_process(argv,root,out,err,timeout=180)
        row={'variant':v,**proc,'errors':[]}
        try:
            require(proc['exitCode']==0 and not proc['timedOut'],'process failure')
            require(err.stat().st_size==0,'stderr not empty')
            if v in ('adPEAS.ps1','adPEAS.exe'):
                require(len(json.loads(read(base.with_suffix('.commenthelp.json'))))==8,'missing comment help evidence')
                help_status=json.loads(read(base.with_suffix('.commenthelp-status.json')))
                if help_status.get('Passed') is not True or help_status.get('Failed'):
                    row['errors'].append('comment_help_failed: '+str(help_status.get('Failed')))
            stdout=out.read_bytes().decode('utf-8',errors='replace')
            for marker in ('Источник:','Исходное сканирование:','HTML-отчёт сохранён:','Экспорт JSON сохранён:','Текстовый отчёт сохранён:'):
                require(marker in stdout,'missing Russian converter output: '+marker)
            require(read(base.with_suffix('.trace.txt')).splitlines()[-1].endswith(' EVIDENCE_WRITTEN'),'incomplete trace')
            e=json.loads(read(base.with_suffix('.evidence.json')))
            require(e['Variant']==v and e['Status']=='PASS' and e['InputSha256'].lower()==input_hash,'bad evidence')
            require(sha(fixture)==input_hash,'fixture modified')
            for ext in ('html','txt','json'):
                f=base.with_suffix('.'+ext);require(sha(f)==e['Files'][ext]['SHA256'].lower() and f.stat().st_size==e['Files'][ext]['Length'],'file witness mismatch '+ext)
            cache=normalize_cache(json.loads(read(base.with_suffix('.json'))))
            require(cache==expected,'JSON roundtrip mismatch against fixture')
            txt=read(base.with_suffix('.txt'))
            require('\x1b' not in txt,'ANSI in NoColor text')
            for token in ('MIG19bc-User-1','MIG19bc-User-2','MIG19bc-FINDING','MIG19bc-NOTE','MIG19bc-SECURE','Русский текст & <tag> $123'):
                require(token in txt,'missing TXT marker: '+token)
            html=check_html(base.with_suffix('.html'),folder)
            semantic={'json':digest(cache),'txt':digest(txt),'html':digest(html),'catalogs':html['catalogHashes'],'summary':html['summary']}
            h.write_json(folder/'semantic.json',semantic)
            row['semantic']=semantic
        except Exception as exc:
            row['errors'].append(str(exc))
        results.append(row);h.write_json(folder/'process.json',row)
    # Require the readable variant as reference, but retain independent evidence
    # and separate pairwise comparisons among available reports when it fails.
    ref=next((r.get('semantic') for r in results if r['variant']==h.VARIANTS[0]),None)
    available=[r for r in results if r.get('semantic') is not None]
    pairs=[]
    for i,left in enumerate(available):
        for right in available[i+1:]:
            pairs.append({'left':left['variant'],'right':right['variant'],'equal':left['semantic']==right['semantic']})
    for row in results:
        sem=row.get('semantic')
        if sem is None:row['parityStatus']='REPORT_NOT_VERIFIED'
        elif ref is None:
            row['parityStatus']='REFERENCE_UNAVAILABLE'
            row['errors'].append('readable_reference_unavailable')
        elif sem!=ref:
            row['parityStatus']='MISMATCH'
            row['errors'].append('cross_variant_semantic_mismatch')
        else:row['parityStatus']='MATCH'
        h.write_json(diag/row['variant']/'process.json',row)
        print(row['variant']+': '+('PASS' if not row['errors'] else 'FAIL '+str(row['errors']))+' parity='+row['parityStatus'],flush=True)
    passed=len(results)==5 and ref is not None and all(not r['errors'] and r['parityStatus']=='MATCH' for r in results)
    data={'schema':'adPEAS-RU.MIG19d2a.1','status':'PASS' if passed else 'FAIL','fixtureSha256':input_hash,'results':results,'readableReferenceAvailable':ref is not None,'pairwiseReportComparisons':pairs,'realADTestPerformed':False,'productionReady':False}
    h.write_json(a.report.resolve(),data);h.write_json(diag/'summary.json',data)
    return 0 if passed else 1
if __name__=='__main__':sys.exit(main())
