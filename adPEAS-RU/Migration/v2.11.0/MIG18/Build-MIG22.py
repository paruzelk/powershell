#!/usr/bin/env python3
"""MIG22: acceptance candidate, narrow display fixes and residual triage."""
import argparse, collections, hashlib, json, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
EXPORT='src/modules/Reporting/Export-HTMLReport.ps1'
def read(p): return p.read_text(encoding='utf-8-sig')
def sha(b): return hashlib.sha256(b).hexdigest()
def q(s): return "'"+s.replace("'","''")+"'"
def patch(s,old,new):
    if s.count(old)!=1 or new in s: raise ValueError('MIG22 anchor: '+old[:140])
    t=s.replace(old,new,1)
    if t.count(new)!=1 or t.replace(new,old,1)!=s: raise ValueError('MIG22 non-reversible edit')
    return t
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--upstream',type=Path,required=True)
    p.add_argument('--prior',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    cat=json.loads(read(HERE/'MIG22-Display.json'))
    prior=json.loads(read(a.prior))
    if prior['schema']!='adPEAS-RU.MIG21c.Source.1' or prior['status']!='PASS': raise ValueError('MIG21c evidence missing')
    source={f.relative_to(a.upstream).as_posix():read(f) for f in sorted((a.upstream/'src').rglob('*.ps1'))}
    witnesses=[]
    for value in [en for en,ru in cat['exact']]+[w for pattern,ru,w in cat['patterns']]+cat['sysvol']+[en for en,ru in cat['groups']]:
        hits=[{'path':path,'line':i} for path,s in source.items() for i,line in enumerate(s.splitlines(),1) if value in line and not line.lstrip().startswith('#')]
        if not hits: raise ValueError('MIG22 source witness missing: '+value)
        witnesses.append({'text':value,'matches':hits})
    f=a.candidate/EXPORT
    raw=f.read_bytes(); s=read(f)
    helper=['function ConvertTo-RuMIG22Line {','    param([AllowNull()][string]$Text)','    switch -CaseSensitive ($Text) {']
    helper+=['        '+q(en)+' { return '+q(ru)+' }' for en,ru in cat['exact']]
    helper+=['    }']
    for pattern,ru,witness in cat['patterns']:
        if not pattern.startswith('^') or not pattern.endswith('$'): raise ValueError('Unanchored rule')
        if sorted(set(int(x) for x in re.findall(r'\$(\d+)',ru)))!=list(range(1,re.compile(pattern).groups+1)): raise ValueError('Missing capture')
        helper.append('    if ($Text -cmatch '+q(pattern)+') { return [regex]::Replace($Text, '+q(pattern)+', '+q(ru)+') }')
    helper+=['    return $Text','}','','']
    anchor='function ConvertTo-RuReportLine {'
    s=patch(s,anchor,'\n'.join(helper)+anchor)
    anchor='    if ($mig21cDisplay -cne $Text) { return $mig21cDisplay }'
    s=patch(s,anchor,anchor+'\n    $mig22Display = ConvertTo-RuMIG22Line -Text $Text\n    if ($mig22Display -cne $Text) { return $mig22Display }')
    # Extend known SYSVOL coverage diagnostics using exactly the MIG21c mapping, including offline RU.
    priorcat=json.loads(read(HERE/'MIG21c-Display.json'))
    existing=dict(priorcat['lines'])
    sysvol=[v for en in cat['sysvol'] for v in (en,existing[en])]
    anchor='        $display = ConvertTo-RuMIG21SysvolDiagnostic -Text $text'
    ext='        if ($text -cin @('+','.join(q(x) for x in sysvol)+')) { $observed++; continue }\n'
    ext+= "        if ($text -cmatch '^The NTFS permissions of [0-9]+ of [0-9]+ policy folder\\(s\\) in SYSVOL could not be read - who may rewrite their content is unknown$' -or $text -cmatch '^Не удалось прочитать разрешения NTFS [0-9]+ из [0-9]+ папок политик в SYSVOL — неизвестно, кто может изменять их содержимое\\.$') { $observed++; continue }\n"
    s=patch(s,anchor,ext+anchor)
    # Display-only title in the typed branch. Do not alter Object fields or generic name rendering.
    anchor='return "Credential ($credType)"'
    s=patch(s,anchor,'return ("Учётные данные (" + (ConvertTo-RuMIG21cAttribute -Name CredentialType -Text $credType) + ")")')
    anchor='            if ($Object.Count) { return "$label ($($Object.Count))" }'
    title=['            switch -CaseSensitive ($label) {']
    title+=['                '+q(en)+' { $label = '+q(ru)+' }' for en,ru in cat['groups']]
    title+=['            }',anchor]
    s=patch(s,anchor,'\n'.join(title))
    out=(b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+s.encode('utf-8')
    f.write_bytes(out)
    # Triage the complete prior inventory by command family, not an assertion of translation completeness.
    rows=[]
    neww=[en for en,ru in cat['exact']]+[w for pattern,ru,w in cat['patterns']]
    for item in prior['inventory']:
        text=item['text']; command=text.split()[0]
        if any(x in text for x in neww): kind='new-display-rule-source-match'
        elif item['classification']=='display-rule-source-match': kind='previous-display-rule-source-match'
        elif command in ('Write-Log','Write-Verbose'): kind='diagnostic-review'
        elif command in ('Write-Warning','Write-Error','Write-Host'): kind='console-review'
        elif command in ('Show-Line','Show-Header','Show-SubHeader','Show-Output'): kind='report-or-console-review'
        else: kind='other-review'
        rows.append(dict(item,triage=kind))
    counts=dict(collections.Counter(x['triage'] for x in rows))
    if len(rows)!=len(prior['inventory']) or sum(counts.values())!=len(rows): raise ValueError('Lost inventory row')
    result={'schema':'adPEAS-RU.MIG22.Source.1','status':'PASS','priorRows':len(rows),'triageCounts':counts,'inventory':rows,'sourceWitnesses':witnesses,'modifiedFile':EXPORT,'beforeSha256':sha(raw),'afterSha256':sha(out),'translationCompletenessCertified':False,'realADTestPerformed':False,'productionReady':False}
    a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS MIG22: report presentation and coverage; prior inventory triage '+json.dumps(counts,sort_keys=True))
if __name__=='__main__':main()
