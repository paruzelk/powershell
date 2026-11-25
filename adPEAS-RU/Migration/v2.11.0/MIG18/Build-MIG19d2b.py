#!/usr/bin/env python3
"""MIG19d2b: repair a false comment-help directive; keep runtime help gates."""
import argparse, hashlib, json, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
NAME='src/modules/Helpers/Get-adPEASOutputBasePath.ps1'
# Mirrors the upstream HelpCommentsParser directive recognition (not a PS 5.1 runtime proof).
DIRECTIVE=re.compile(r'^\s*\.(\w+)(\s+(\S.*))?\s*$')
KNOWN={'SYNOPSIS','DESCRIPTION','PARAMETER','EXAMPLE','OUTPUTS','NOTES','LINK','INPUTS','COMPONENT','ROLE','FUNCTIONALITY','FORWARDHELPTARGETNAME','FORWARDHELPCATEGORY','REMOTEHELPRUNSPACE','EXTERNALHELP'}
def unknown(block):
    return [m.group(1).upper() for line in block.splitlines() if (m:=DIRECTIVE.fullmatch(line)) and m.group(1).upper() not in KNOWN]
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    f=a.candidate/NAME
    original=f.read_text(encoding='utf-8-sig')
    block=json.loads((HERE/'MIG19d2-HelperHelp.json').read_text(encoding='utf-8-sig'))[NAME][0][1]
    declaration='function Get-adPEASOutputBasePath {'
    before='    Удаляются только три расширения, создаваемые adPEAS. Суффиксы доменов .com, .local,\n    .de и другие части имени не изменяются. Ранее удаление любого расширения могло'
    after='    Удаляются только три расширения, создаваемые adPEAS.\n    Суффиксы доменов .com, .local, .de и другие части имени не изменяются. Ранее удаление любого расширения могло'
    if block.count(before)!=1 or unknown(block)!=['DE']:raise ValueError('Expected exactly false .DE directive')
    new_block=block.replace(before,after,1)
    if unknown(new_block):raise ValueError('Unrecognized help directives')
    if ' '.join(block.split())!=' '.join(new_block.split()):raise ValueError('Non-whitespace help change')
    old=declaration+'\n'+block
    new=declaration+'\n'+new_block
    if original.count(old)!=1 or new in original:raise ValueError('Unexpected MIG19d2a help witness')
    result=original.replace(old,new,1)
    if result.replace(new,old,1)!=original or result.replace(new,declaration,1)!=original.replace(old,declaration,1):
        raise ValueError('Executable source changed')
    raw=b'\xef\xbb\xbf'+result.encode('utf-8')
    f.write_bytes(raw)
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19d2b.HelpDirective.1','path':NAME,'unknownDirectivesBefore':['DE'],'unknownDirectivesAfter':[],'helpWordsPreserved':True,'executableSourcePreserved':True,'sha256':hashlib.sha256(raw).hexdigest(),'runtimeTestRequired':True},indent=2)+'\n',encoding='utf-8')
    print('PASS MIG19d2b: false .DE directive removed; all help words and executable source preserved')
if __name__=='__main__':main()
