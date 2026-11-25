#!/usr/bin/env python3
"""MIG14: exact-match Russian remediation labels; preserve all command text."""
import argparse, hashlib, json, re
from pathlib import Path

# Original labels from pinned 2.11.0; translations reviewed for display only.
NEW = {
    'Show whom managedBy names on each read-only Domain Controller': 'Показать, на кого указывает атрибут managedBy каждого контроллера домена только для чтения (RODC)',
    'Remove the delegated administrator of a read-only Domain Controller': 'Удалить назначение делегированного администратора контроллера домена только для чтения (RODC)',
    'Show every setting of the template, the cryptography ones included': 'Показать все параметры шаблона, включая криптографические',
    'Read the raw attribute the settings are stored in': 'Прочитать исходное значение атрибута, в котором хранятся эти параметры',
    'List the principals the account names': 'Перечислить субъектов безопасности, указанных в учётной записи',
    'Write the list again with only the principals that should be there': 'Перезаписать список, оставив только субъектов, которым действительно необходим доступ',
    'Name a dedicated group as the delegated administrator': 'Назначить выделенную группу делегированным администратором',
    'Remove the delegated administrator': 'Удалить назначение делегированного администратора',
    'List the accounts whose secrets the server holds': 'Перечислить учётные записи, секреты которых хранятся на сервере',
    'Show the decryptor group and the password the account can read': 'Показать группу с правом расшифровки и пароль, доступный данной учётной записи для чтения',
    'Read the VNC values a policy deploys, to see which form each one is stored in': 'Прочитать значения VNC, развёртываемые политикой, чтобы определить формат хранения каждого значения',
    'Require Extended Protection on an IIS virtual directory': 'Сделать расширенную защиту (Extended Protection) обязательной для виртуального каталога IIS',
    'See who created the account and when it last logged on': 'Установить, кто создал учётную запись и когда она в последний раз выполняла вход',
    'Show the Extended Protection settings of an IIS virtual directory': 'Показать параметры расширенной защиты (Extended Protection) виртуального каталога IIS',
    'Show the owner and the access rules that can write managedBy of a read-only Domain Controller': 'Показать владельца и правила доступа, разрешающие запись в managedBy контроллера домена только для чтения (RODC)',
    'Find computer accounts that never had a password set': 'Найти учётные записи компьютеров, для которых пароль никогда не задавался',
    'Require a password on the account': 'Сделать наличие пароля для учётной записи обязательным',
}
ANCHOR = 'function showFindingTooltip(trigger, findingId) {'
OLD = 'escapeHtml(cmd.description)'
NEW_EXPR = 'escapeHtml(translateMIG14RemediationLabel(cmd.description))'
EXPECTED_OVERLAY = 'a877223bdfd79c5bb4a11cc6623c073f5e2557a3ccc88b0d396497669a3a9c9c'

def sha(s): return hashlib.sha256(s.encode('utf-8')).hexdigest()
def read_catalogs(localization):
    result={}; conflicts=[]
    for n in range(1,6):
        name=f'RemediationLabels-{n:02d}.ru-RU.json'
        for en,ru in json.loads((localization/name).read_text(encoding='utf-8-sig')).items():
            if en in result and result[en]!=ru: conflicts.append(en)
            result.setdefault(en,ru)
    if len(result)!=569 or conflicts!=['Remove Client Authentication EKU from template (if not required)']:
        raise ValueError('Unexpected DOC6j catalog inventory/conflicts')
    if set(NEW)&set(result): raise ValueError('New label already translated')
    result.update(NEW)
    assert len(result)==586
    assert all(re.search('[А-Яа-яЁё]',v) for v in result.values())
    return result

def patch(text,labels):
    if text.count(ANCHOR)!=1 or text.count(OLD)!=1 or 'const ruMIG14RemediationLabels' in text:
        raise ValueError('Unexpected renderer anchors')
    m=re.search(r'const ruMIG2CheckDetails = (\{[^\r\n]*\});',text)
    if not m or sha(m[1])!=EXPECTED_OVERLAY: raise ValueError('MIG13 overlay witness changed')
    nl='\r\n' if '\r\n' in text else '\n'
    # JSON literal is encoded for use inside an inline HTML script; avoid accidental closing tags.
    data=json.dumps(labels,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c').replace('\u2028','\\u2028').replace('\u2029','\\u2029')
    extra=nl.join(['const ruMIG14RemediationLabels = '+data+';', '', '        function translateMIG14RemediationLabel(value) {', '            return Object.prototype.hasOwnProperty.call(ruMIG14RemediationLabels, value)', '                ? ruMIG14RemediationLabels[value] : value;', '        }', '', '        '])
    return text.replace(ANCHOR,extra+ANCHOR).replace(OLD,NEW_EXPR)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--localization',type=Path,required=True);ap.add_argument('--report',type=Path,required=True);a=ap.parse_args()
    path=a.candidate/'src/modules/Reporting/templates/report-scripts.js'
    canonical=a.candidate/'src/modules/Core/adPEAS-FindingDefinitions.ps1';before=hashlib.sha256(canonical.read_bytes()).hexdigest()
    labels=read_catalogs(a.localization)
    raw=path.read_bytes();bom=raw.startswith(b'\xef\xbb\xbf');s=raw.decode('utf-8-sig');patched=patch(s,labels)
    path.write_bytes((b'\xef\xbb\xbf' if bom else b'')+patched.encode('utf-8'))
    assert before==hashlib.sha256(canonical.read_bytes()).hexdigest()
    a.report.write_text(json.dumps(dict(Schema='adPEAS-RU.2.11.0.MIG14.Source.1',UniqueLabels=len(labels),Reused=569,New=17,CanonicalFindingDefinitionsPreserved=True,OriginalDefinitionsSha256=before,ProductionReady=False),indent=2)+'\n',encoding='utf-8')
if __name__=='__main__': main()
