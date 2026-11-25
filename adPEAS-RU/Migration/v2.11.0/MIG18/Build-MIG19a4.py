#!/usr/bin/env python3
"""MIG19a4: repair EXE module scope; exact post-MIG17 source witness."""
import argparse, hashlib, json
from pathlib import Path
EXPECTED = '9edfa6315c62da249e141a6858917643129a863fadc77a859d0c40f9dc6cc3c4'
OLD = "            // Dot-sourced at the top level of the session: functions and $Script: state land in\n            // the global scope, as after Import-Module of the .ps1 at a prompt.\n            const string load = \". ([ScriptBlock]::Create([BuildConsoleHost.Payload]::Text))\";"
NEW = "            // Keep the embedded script's $Script: state in one persistent module session state.\n            // A caller's external .ps1 must not become the script scope of adPEAS functions.\n            const string load = \"Import-Module -ModuleInfo (New-Module -Name adPEAS -ScriptBlock ([ScriptBlock]::Create([BuildConsoleHost.Payload]::Text)) -ErrorAction Stop) -Global -DisableNameChecking -ErrorAction Stop\";"
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    f=a.candidate/'Build-Engine.ps1'
    raw=f.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=EXPECTED or not raw.startswith(b'\xef\xbb\xbf'):
        raise ValueError('Unexpected MIG18a Build-Engine.ps1 witness')
    text=raw.decode('utf-8-sig')
    if text.count(OLD)!=1 or NEW in text:raise ValueError('Unexpected EXE launcher anchor')
    changed=text.replace(OLD,NEW,1)
    if changed.count(NEW)!=1 or changed.replace(NEW,OLD,1)!=text:raise ValueError('Non-reversible launcher patch')
    out=b'\xef\xbb\xbf'+changed.encode('utf-8')
    f.write_bytes(out)
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19a4.ExeScope.1','beforeSha256':EXPECTED,'afterSha256':hashlib.sha256(out).hexdigest(),'changes':1,'embeddedPayloadChangedByPatch':False,'realADTestPerformed':False},indent=2)+'\n',encoding='utf-8')
    print('PASS MIG19a4 exact launcher witness; persistent dynamic module')
if __name__=='__main__':main()
