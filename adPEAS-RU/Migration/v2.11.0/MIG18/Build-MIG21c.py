#!/usr/bin/env python3
"""MIG21c2-c4: witnessed result presentation, field values, remaining text inventory."""
import argparse, collections, hashlib, json, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
EXPORT='src/modules/Reporting/Export-HTMLReport.ps1'
RENDER='src/modules/Core/Render-HtmlObject.ps1'
def read(p): return p.read_text(encoding='utf-8-sig')
def sha(b): return hashlib.sha256(b).hexdigest()
def q(s): return "'"+s.replace("'","''")+"'"
def patch(s,old,new):
    if s.count(old)!=1 or new in s: raise ValueError('MIG21c anchor: '+old[:150])
    t=s.replace(old,new,1)
    if t.count(new)!=1 or t.replace(new,old,1)!=s: raise ValueError('MIG21c non-reversible edit')
    return t
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--upstream',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    cat=json.loads(read(HERE/'MIG21c-Display.json'))
    source={f.relative_to(a.upstream).as_posix():read(f) for f in sorted((a.upstream/'src').rglob('*.ps1'))}
    rows=[]
    rules=[('line',en,en) for en,ru in cat['lines']]+[('pattern',pattern,witness) for pattern,ru,witness in cat['patterns']]+[('attribute:'+field,en,witness) for field,en,ru,witness in cat['attrs']]
    for kind,key,witness in rules:
        hits=[{'path':path,'line':i} for path,s in source.items() for i,line in enumerate(s.splitlines(),1) if witness in line and not line.lstrip().startswith('#')]
        if not hits: raise ValueError('MIG21c upstream witness missing '+witness)
        rows.append({'kind':kind,'value':key,'sourceMatches':hits})
    if len({(kind,key) for kind,key,_ in rules})!=len(rules): raise ValueError('Duplicate localization rule')
    # Only renderer helpers are modified; the collection, scoring and raw AD data are untouched.
    helper=['function ConvertTo-RuMIG21cLine {','    param([AllowNull()][string]$Text)','    switch -CaseSensitive ($Text) {']
    helper += ['        '+q(en)+' { return '+q(ru)+' }' for en,ru in cat['lines']]
    helper += ['    }']
    for pattern,ru,witness in cat['patterns']:
        if not pattern.startswith('^') or not pattern.endswith('$'): raise ValueError('Unanchored rule')
        groups=re.compile(pattern).groups
        if sorted(set(int(n) for n in re.findall(r'\$(\d+)',ru)))!=list(range(1,groups+1)): raise ValueError('Lost pattern capture')
        helper.append('    if ($Text -cmatch '+q(pattern)+') { return [regex]::Replace($Text, '+q(pattern)+', '+q(ru)+') }')
    helper+=['    return $Text','}','','']
    f=a.candidate/EXPORT
    s=read(f)
    anchor='function ConvertTo-RuReportLine {'
    s=patch(s,anchor,'\n'.join(helper)+anchor)
    anchor='    if ($mig21Display -cne $Text) { return $mig21Display }'
    s=patch(s,anchor,anchor+'\n    $mig21cDisplay = ConvertTo-RuMIG21cLine -Text $Text\n    if ($mig21cDisplay -cne $Text) { return $mig21cDisplay }')
    fields=collections.defaultdict(list)
    for field,en,ru,witness in cat['attrs']: fields[field].append((en,ru))
    helper=['function ConvertTo-RuMIG21cAttribute {','    param([AllowNull()][string]$Name,[AllowNull()][string]$Text)','    switch ($Name) {']
    for field,pairs in fields.items():
        helper+=['        '+q(field)+' {','            switch -CaseSensitive ($Text) {']
        helper+=['                '+q(en)+' { return '+q(ru)+' }' for en,ru in pairs]
        helper+=['            }','        }']
    helper+=['    }','    return $Text','}','','']
    g=a.candidate/RENDER
    t=read(g)
    anchor='function ConvertTo-RuDisplayAttribute19g {'
    t=patch(t,anchor,'\n'.join(helper)+anchor)
    anchor='    if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($Text)) { return $Text }\n    $result = $Text'
    t=patch(t,anchor,anchor+'\n    $mig21cDisplay = ConvertTo-RuMIG21cAttribute -Name $Name -Text $Text\n    if ($mig21cDisplay -cne $Text) { return $mig21cDisplay }')
    # Explicit type branches for card titles, never arbitrary AD object names.
    old='return "Credential ($credType)"'
    new='return ("Учётные данные (" + (ConvertTo-RuMIG21cAttribute -Name CredentialType -Text $credType) + ")")'
    # Some earlier stages may already have localized this title; preserve any prior change.
    title_applied=False
    evidence={}
    for path,out in ((f,s),(g,t)):
        raw=path.read_bytes()
        data=(b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+out.encode('utf-8')
        path.write_bytes(data)
        evidence[path.relative_to(a.candidate).as_posix()]={'beforeSha256':sha(raw),'afterSha256':sha(data)}
    # Explicitly distinguish generated text from ambiguous/unresolved phrases; no-match is not AD evidence.
    inventory=[]
    for path in sorted((a.candidate/'src').rglob('*.ps1')):
        rel=path.relative_to(a.candidate).as_posix()
        for i,line in enumerate(read(path).splitlines(),1):
            if not re.match(r'\s*(?:Show-(?:Line|Header|SubHeader|Output)|Write-(?:Warning|Error|Log|Verbose|Host))\s+',line): continue
            if not re.search(r'[A-Za-z]{2,}\s+[A-Za-z]{2,}',line): continue
            if re.search(r'[А-Яа-яЁё]',line): continue
            covered=[key for kind,key,witness in rules if kind in ('line','pattern') and witness in line]
            inventory.append({'path':rel,'line':i,'classification':'display-rule-source-match' if covered else 'unresolved-review','rules':covered,'text':line.strip()[:600]})
    result={'schema':'adPEAS-RU.MIG21c.Source.1','status':'PASS','rules':rows,'counts':{k:len(cat[k]) for k in cat},'files':evidence,'credentialCardTitleChanged':title_applied,'inventory':inventory,'unresolvedCount':sum(r['classification']=='unresolved-review' for r in inventory),'absenceOfSourceMatchMeansADData':False,'rawFindingsChanged':False,'fullLocalizationCertified':False,'productionReady':False}
    a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS MIG21c: %d line rules, %d anchored patterns, %d field rules; unresolved source rows %d' % (len(cat['lines']),len(cat['patterns']),len(cat['attrs']),result['unresolvedCount']))
if __name__=='__main__': main()
