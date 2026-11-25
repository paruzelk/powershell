#!/usr/bin/env python3
"""MIG19d2a: attach existing comment help inside the function, without changing executable code."""
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
NAME='src/modules/Helpers/Get-adPEASOutputBasePath.ps1'
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    f=a.candidate/NAME
    s=f.read_text(encoding='utf-8-sig')
    help_text=json.loads((HERE/'MIG19d2-HelperHelp.json').read_text(encoding='utf-8-sig'))[NAME][0][1]
    declaration='function Get-adPEASOutputBasePath {'
    before=help_text+'\n'+declaration
    after=declaration+'\n'+help_text
    if s.count(before)!=1 or after in s:raise ValueError('Unexpected helper comment help anchor')
    changed=s.replace(before,after,1)
    if changed.replace(after,before,1)!=s:raise ValueError('Non-reversible help relocation')
    if changed.replace(help_text,'',1).replace('\n\n','\n',1)!=s.replace(help_text,'',1).replace('\n\n','\n',1):
        # Compare executable source after removing only the moved comment and surrounding whitespace.
        if changed.replace(after,declaration,1)!=s.replace(before,declaration,1):
            raise ValueError('Executable source changed')
    raw=b'\xef\xbb\xbf'+changed.encode('utf-8')
    f.write_bytes(raw)
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19d2a.HelpPlacement.1','path':NAME,'helpTextPreserved':True,'executableSourcePreserved':True,'sha256':hashlib.sha256(raw).hexdigest()},indent=2)+'\n',encoding='utf-8')
    print('PASS MIG19d2a: existing help moved inside function; no executable changes')
if __name__=='__main__':main()
