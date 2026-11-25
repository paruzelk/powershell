#!/usr/bin/env python3
"""MIG19d1: source-witnessed core help and diagnostic localization."""
import argparse, json, hashlib, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
def load(name):
    return json.loads((HERE/name).read_text(encoding='utf-8-sig'))
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    help_rules=load('MIG19d1-CoreHelp.json')
    diag_rules=load('MIG19d1-Diagnostics.json')
    if len(help_rules)!=6 or sum(map(len,diag_rules.values()))!=269:raise ValueError('Catalog coverage')
    outputs={};stats={}
    for name in sorted(set(help_rules)|set(diag_rules)):
        f=a.candidate/name
        original=f.read_text(encoding='utf-8-sig');s=original
        applied=[];prior=0;help_count=0
        if name in help_rules:
            old,new=help_rules[name]
            if s.count(old)!=1 or new in s:raise ValueError('Unexpected help anchor: '+name)
            old_fields=re.findall(r'(?m)^\s*\.(?:PARAMETER|SYNOPSIS|DESCRIPTION|EXAMPLE|OUTPUTS|NOTES|LINK)\b[^\r\n]*',old)
            new_fields=re.findall(r'(?m)^\s*\.(?:PARAMETER|SYNOPSIS|DESCRIPTION|EXAMPLE|OUTPUTS|NOTES|LINK)\b[^\r\n]*',new)
            if [x.strip() for x in old_fields]!=[x.strip() for x in new_fields]:raise ValueError('Help field parity: '+name)
            s=s.replace(old,new);applied.append((old,new));help_count=1
        for old,new in diag_rules.get(name,[]):
            if s.count(old)==1 and new not in s:
                s=s.replace(old,new);applied.append((old,new))
            elif s.count(old)==0 and s.count(new)==1:prior+=1
            else:raise ValueError('Unexpected diagnostic anchor: '+name+': '+old)
        reverse=s
        for old,new in reversed(applied):
            if reverse.count(new)!=1:raise ValueError('Reverse anchor: '+name)
            reverse=reverse.replace(new,old)
        if reverse!=original:raise ValueError('Non-reversible patch: '+name)
        raw=b'\xef\xbb\xbf'+s.encode('utf-8')
        outputs[f]=raw
        stats[name]={'helpBlocks':help_count,'diagnosticsNew':len(applied)-help_count,'diagnosticsAlreadyTranslated':prior,'sha256':hashlib.sha256(raw).hexdigest()}
    for f,raw in outputs.items():f.write_bytes(raw)
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19d1.Source.1','files':stats,'helpBlocks':6,'diagnosticCandidates':269,'canonicalDefinitionsModified':False,'realADTestPerformed':False},indent=2)+'\n',encoding='utf-8')
    print('PASS MIG19d1: six help blocks and 269 diagnostic witnesses')
if __name__=='__main__':main()
