#!/usr/bin/env python3
"""MIG19d2: pinned DOC6g-i log-line migration, two help blocks, FGPP terminology."""
import argparse, json, hashlib, re
from collections import Counter
from pathlib import Path

HERE=Path(__file__).resolve().parent
PINS={
 "DOC6g-SecurityChecks.ru-RU.json":"bd573b748e605530e112f9ad7f68aa244846cc914d646e812057fc8e768e832d",
 "DOC6h-Check1.json":"b71ea60801469db92607bcaeaaf621bf78b788007bc375c90b4c5f6c86f42033",
 "DOC6h-Check2.json":"bb23346450083c28b88a997b7e38841a3a628e31db534142cab56058bb2c2f02",
 "DOC6h-Check3.json":"4885db22ddf8884730f17eed1d8f8d3e157b91323053b7a5fdc6abc07122935d",
 "DOC6h-Check4.json":"cb797f85b81205e5cafb72e3e8a417d70fc7840b89e9701f6d554a55facb0fac",
 "DOC6h-Check5.json":"b076bc843f12eb514b3486be2b26c947f235f6e67e20f5370ac55c1d850598cb",
 "DOC6i-Check1.json":"abb98361424b8a5b718d70b02523d5083219e84a07e4ae9fe807f990c6e8a724",
 "DOC6i-Check2.json":"1571db1853f023a0364bf73588fa3d79d0a52409b2f95728cd85ee5b42a17cf2",
 "DOC6i-Check3.json":"ce71343b545c1c6940e42fcc7ff3f4fb61653d899c6ab1fa1c3786c9f9fc1451",
 "DOC6i-Check4.json":"955b5b2264cb08663bcb93e95d10282aca457eca6dc915e20c66e78ec5d1b84d",
 "DOC6i-Check5.json":"8f7d2b785fa7724b084c996a9a3be1c0e062211300f92efcc041c333ed200b10"
}
# Counts independently measured against the successful MIG19d1 readable artifact.
EXPECTED={
 "src/modules/Checks/Accounts/Get-PrivilegedGroupMembers.ps1":(64,3,0),
 "src/modules/Checks/Domain/Get-DomainInformation.ps1":(38,0,0),
 "src/modules/Checks/ADCS/Get-ADCSVulnerabilities.ps1":(49,0,4),
 "src/modules/Checks/Application/Get-ExchangeInfrastructure.ps1":(27,0,0),
 "src/modules/Checks/Creds/Get-CredentialExposure.ps1":(17,10,0),
 "src/modules/Checks/GPO/Get-GPOPermissions.ps1":(22,0,0),
 "src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1":(22,0,0),
 "src/modules/Checks/ADCS/Get-WeakCertificateMapping.ps1":(17,0,0),
 "src/modules/Checks/Creds/Get-BitLockerRecoveryKeyAccess.ps1":(17,0,0),
 "src/modules/Checks/Rights/Get-AddComputerRights.ps1":(17,0,0),
 "src/modules/Checks/Creds/Get-LAPSCredentialAccess.ps1":(13,3,0),
 "src/modules/Checks/Computer/Get-InfrastructureServers.ps1":(15,0,0),
 "src/modules/Checks/GPO/Get-GPOLocalGroupMembership.ps1":(11,4,0)
}
FGPP={
 "src/modules/Core/adPEAS-ObjectTypes.ps1":[
  'SectionTitle = "Тонкие политики паролей (FGPP)"'
 ],
 "src/modules/Checks/Domain/Get-DomainPasswordPolicy.ps1":[
  'Show-Line "Тонкие политики паролей настроены корректно" -Class Secure',
  'Show-Line "Тонкие политики паролей не обнаружены ни по именам, ни по назначению" -Class Note',
  'Show-Line "Тонкие политики паролей недоступны: необходим функциональный уровень домена Windows Server 2008 или выше" -Raw'
 ]
}
LITERAL=r'"(?:[^"\x60]|\x60.)*"'
LOG=re.compile(r'^Write-(?:Log|Warning|Error|Verbose)\s+'+LITERAL+r'(?:\s+-Level\s+\w+)?$')
RU=re.compile(r'[А-Яа-яЁё]')
VARS=re.compile(r'\$\([^)]+\)|\$\{[^}]+\}|\$[A-Za-z_][\w:]*')
FIELDS=re.compile(r'(?m)^\s*\.(?:PARAMETER|SYNOPSIS|DESCRIPTION|EXAMPLE|OUTPUTS|NOTES|LINK)\b[^\r\n]*')
VISIBLE=re.compile(r'^\s*(?:Write-(?:Log|Warning|Error|Verbose)|Show-(?:Line|Header|SubHeader))\s+"')
def read(path):return path.read_text(encoding='utf-8-sig')
def canonical(obj):return hashlib.sha256(json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def safe(a,b):
    return (LOG.fullmatch(a) and LOG.fullmatch(b) and
            re.sub(LITERAL,'""',a)==re.sub(LITERAL,'""',b) and
            sorted(VARS.findall(a))==sorted(VARS.findall(b)) and RU.search(b))
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--locale',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--inventory',type=Path,required=True)
    a=p.parse_args()
    originals={};outputs={};changes={};stats={};review=[]
    def get(name):
        if name not in originals:originals[name]=read(a.candidate/name)
        return outputs.get(name,originals[name])
    def stage(name,old,new,kind):
        s=get(name)
        if s.count(old)!=1 or new in s:raise ValueError('Anchor mismatch: '+name+': '+old[:140])
        outputs[name]=s.replace(old,new,1)
        changes.setdefault(name,[]).append((old,new,kind))
    seen=set()
    for fn,pin in PINS.items():
        obj=json.loads(read(a.locale/fn))
        if canonical(obj)!=pin:raise ValueError('Catalog digest mismatch: '+fn)
        for g in obj.get('files',[obj]):
            name=g['path']
            if name not in EXPECTED or name in seen:raise ValueError('Unexpected catalog group: '+name)
            seen.add(name)
            lines=get(name).splitlines(keepends=True)
            counts=Counter(line.strip() for line in lines)
            result=Counter()
            for row in g['entries']:
                old,new=row['original'].strip(),row['target'].strip()
                if not safe(old,new):status='excluded'
                elif counts[old]==1 and counts[new]==0:status='new'
                else:status='unmatched'
                result[status]+=1
                if status=='new':
                    matched=[line.rstrip('\r\n') for line in lines if line.strip()==old]
                    if len(matched)!=1:raise ValueError('Line witness: '+name)
                    before=matched[0];after=before[:len(before)-len(before.lstrip())]+new
                    # Replace complete lines, with newline boundaries, not substrings in comments.
                    source=get(name)
                    if source.count('\n'+before+'\n')!=1 or '\n'+after+'\n' in source:raise ValueError('Exact line anchor: '+name)
                    stage(name,'\n'+before+'\n','\n'+after+'\n','diagnostic')
                else:
                    review.append({'path':name,'catalog':fn,'legacyLine':row.get('line'),'status':status,'original':old})
            if tuple(result[k] for k in ('new','unmatched','excluded'))!=EXPECTED[name]:
                raise ValueError('Source coverage mismatch '+name+': '+str(dict(result)))
            stats[name]=dict(result)
    if seen!=set(EXPECTED):raise ValueError('Incomplete catalog groups')
    for name,rules in json.loads(read(HERE/'MIG19d2-HelperHelp.json')).items():
        for old,new in rules:
            if [x.strip() for x in FIELDS.findall(old)]!=[x.strip() for x in FIELDS.findall(new)]:
                raise ValueError('Help section parity: '+name)
            stage(name,old,new,'help')
    for name,lines in FGPP.items():
        for old in lines:stage(name,old,old.replace('Тонкие политики паролей','Детализированные политики паролей'),'fgpp')
    summary=Counter(kind for rows in changes.values() for _,_,kind in rows)
    if summary!=Counter({'diagnostic':329,'help':2,'fgpp':4}):raise ValueError('Coverage mismatch '+str(summary))
    for name,rows in changes.items():
        reverse=outputs[name]
        for old,new,kind in reversed(rows):
            if reverse.count(new)!=1:raise ValueError('Reverse anchor '+name)
            reverse=reverse.replace(new,old,1)
        if reverse!=originals[name]:raise ValueError('Non-reversible changes: '+name)
    # Inventory is deliberately heuristic: code/technical strings are not confirmed translation gaps.
    inventory=[]
    for path in sorted((a.candidate/'src').rglob('*.ps1')):
        name=path.relative_to(a.candidate).as_posix()
        s=outputs.get(name)
        if s is None:s=read(path)
        lines=s.splitlines()
        hits=[{'line':i,'text':l.strip()} for i,l in enumerate(lines,1) if VISIBLE.match(l) and not RU.search(l)]
        help_hits=[]
        for m in re.finditer(r'(?ms)^\s*\.SYNOPSIS[ \t]*\n(.*?)(?=^\s*\.[A-Z]+(?:\s|$)|#>)',s):
            synopsis=m.group(1).strip()
            if synopsis and not RU.search(synopsis):
                help_hits.append({'line':s.count('\n',0,m.start())+1,'text':synopsis})
        if hits or help_hits:inventory.append({'path':name,'visibleCandidates':hits,'helpCandidates':help_hits})
    def save_json(path,data):
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for name,s in outputs.items():
        (a.candidate/name).write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
    save_json(a.inventory,{'schema':'adPEAS-RU.MIG19d2.ResidualInventory.1','heuristicOnly':True,'visibleCandidateCount':sum(len(r['visibleCandidates']) for r in inventory),'helpCandidateCount':sum(len(r['helpCandidates']) for r in inventory),'legacyReview':review,'files':inventory})
    save_json(a.report,{'schema':'adPEAS-RU.MIG19d2.Source.1','newDiagnostics':329,'unmatchedLegacy':20,'excludedComposite':4,'newHelpBlocks':2,'fgppStaticLabels':4,'catalogGroups':stats,'files':{name:hashlib.sha256((a.candidate/name).read_bytes()).hexdigest() for name in outputs},'canonicalDefinitionsModified':False,'realADTestPerformed':False,'fullLocalizationCertified':False})
    print('PASS MIG19d2: 329 diagnostic lines, 2 help blocks, 4 FGPP labels; 24 legacy rows reserved for review')
if __name__=='__main__':main()
