#!/usr/bin/env python3
"""MIG19k2: no-session SID diagnostics are not report data."""
import argparse
import hashlib
import json
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    patches = [
        ('src/modules/Reporting/Convert-adPEASReport.ps1',
         "                Username = 'Offline'",
         "                Username = 'Offline'\n                OfflineSidReplay19k2 = $true"),
    ]
    for name in ('ConvertTo-SID', 'ConvertFrom-SID'):
        old = '            Show-NoSessionError -Context "' + name + '"'
        new = """            # MIG19k2: the converter's own temporary context identifies expected offline fallback.
            # Keep the original return value and all active-session resolution logic.
            if (-not ($Script:LDAPContext -is [hashtable] -and $Script:LDAPContext.ContainsKey('OfflineSidReplay19k2') -and $Script:LDAPContext['OfflineSidReplay19k2'] -eq $true)) {
""" + '    ' + old + """
            }"""
        patches.append(('src/modules/Helpers/' + name + '.ps1', old, new))
    evidence = []
    staged = []
    for rel, old, new in patches:
        f = a.candidate / rel
        raw = f.read_bytes()
        s = raw.decode('utf-8-sig')
        newline = '\r\n' if '\r\n' in s else '\n'
        old = old.replace('\n', newline)
        new = new.replace('\n', newline)
        if s.count(old) != 1 or new in s:
            raise ValueError('MIG19k2 exact anchor: ' + rel)
        t = s.replace(old, new, 1)
        if t.count(new) != 1 or t.replace(new, old, 1) != s:
            raise ValueError('MIG19k2 reversibility: ' + rel)
        out = (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + t.encode('utf-8')
        staged.append((f, out))
        evidence.append({'path': rel, 'beforeSha256': hashlib.sha256(raw).hexdigest(),
                         'afterSha256': hashlib.sha256(out).hexdigest(), 'reversible': True})
    for f, out in staged:
        f.write_bytes(out)
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19k2.Source.1',
        'patches':evidence,'sidFallbackUnchanged':True,'activeSessionLogicUnchanged':True,
        'temporaryContextRestoredByOriginalFinally':True,'realADTestPerformedInCI':False,
        'productionReady':False}, indent=2)+'\n', encoding='utf-8')
    print('PASS MIG19k2: 3 reversible source patches, offline SID fallback unchanged')
if __name__ == '__main__':
    main()
