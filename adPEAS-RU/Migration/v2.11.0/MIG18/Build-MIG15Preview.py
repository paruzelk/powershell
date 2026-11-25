#!/usr/bin/env python3
"""MIG15 display-only comments and terminology; original copy payload unchanged."""
import argparse, hashlib, json, re
from pathlib import Path
ANCHOR='function showFindingTooltip(trigger, findingId) {'
OLD='<pre>${escapeHtml(cmd.command)}</pre>'
NEW='<pre>${escapeHtml(translateMIG15CommandComments(cmd.command))}</pre>'
TERM='Внедрите Microsoft Enterprise Access Model (Tier Model).'
RU='Внедрите модель корпоративного доступа Microsoft (уровневую модель).'

def patch(text, lines):
    assert text.count(ANCHOR)==text.count(OLD)==text.count(TERM)==1
    assert 'const ruMIG15CommentLines' not in text and 'const ruMIG14RemediationLabels' in text
    assert len(lines)==169
    assert hashlib.sha256(json.dumps(lines,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()=='e517171f2ce34301d47f39d477fb69cb5f1f4f46f66b9a6b0525fde344f441e4'
    data=json.dumps(lines,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c').replace('\u2028','\\u2028').replace('\u2029','\\u2029')
    nl='\r\n' if '\r\n' in text else '\n'
    helper=nl.join(['const ruMIG15CommentLines = '+data+';', '', '        function translateMIG15CommandComments(value) {', r'            return value.split(/(\r\n|\n|\r)/).map(line =>', '                Object.prototype.hasOwnProperty.call(ruMIG15CommentLines, line)', '                    ? ruMIG15CommentLines[line] : line).join(\'\');', '        }', '', '        '])
    return text.replace(ANCHOR,helper+ANCHOR).replace(OLD,NEW).replace(TERM,RU)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--catalog',type=Path,required=True);a=ap.parse_args()
    p=a.candidate/'src/modules/Reporting/templates/report-scripts.js'
    raw=p.read_bytes();s=raw.decode('utf-8-sig');out=patch(s,json.loads(a.catalog.read_text(encoding='utf-8-sig')))
    p.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+out.encode())
if __name__=='__main__':main()
