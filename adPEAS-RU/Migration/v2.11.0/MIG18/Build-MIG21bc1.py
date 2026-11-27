#!/usr/bin/env python3
"""MIG21b/c1: scoped SYSVOL diagnostics and HTML coverage disclosure."""
import argparse, hashlib, json, re
from pathlib import Path

EXPORT = 'src/modules/Reporting/Export-HTMLReport.ps1'
TEMPLATE = 'src/modules/Reporting/templates/report-template.html'
EXACT = {
    'Skipped - SYSVOL not accessible': 'Проверка пропущена: SYSVOL недоступен.',
    'SYSVOL is not accessible - GPO logon restrictions could not be evaluated': 'SYSVOL недоступен: ограничения входа GPO не оценены.',
    'SYSVOL is not accessible - GPO user rights could not be evaluated': 'SYSVOL недоступен: права пользователей GPO не оценены.',
    'SYSVOL access failed - GPO logon restrictions could not be evaluated - SMB access failed (authentication/network issue)': 'Не удалось получить доступ к SYSVOL: ограничения входа GPO не оценены (ошибка SMB: аутентификация или сеть).',
    'SYSVOL access failed - GPO user rights could not be evaluated - SMB access failed (authentication/network issue)': 'Не удалось получить доступ к SYSVOL: права пользователей GPO не оценены (ошибка SMB: аутентификация или сеть).',
}
for en, ru in [
    ('GPO registry settings', 'параметры реестра GPO'),
    ('GPO local group assignments', 'назначения локальных групп GPO'),
    ('GPO scheduled tasks', 'запланированные задания GPO'),
    ('GPO scripts', 'сценарии GPO'),
]:
    EXACT['SYSVOL access failed - cannot analyze '+en+' - SMB access failed (authentication/network issue)'] = 'Не удалось получить доступ к SYSVOL: не проанализированы '+ru+' (ошибка SMB: аутентификация или сеть).'
PATTERNS = [
    (r'^([0-9]+) SYSVOL folder\(s\) could not be read - the result below is incomplete$', 'Не удалось прочитать папки SYSVOL (количество: $1); результат ниже неполный.', 'SYSVOL folder(s) could not be read - the result below is incomplete'),
    (r'^([0-9]+) SYSVOL file\(s\) could not be read or parsed - the result below is incomplete$', 'Не удалось прочитать или обработать файлы SYSVOL (количество: $1); результат ниже неполный.', 'SYSVOL file(s) could not be read or parsed - the result below is incomplete'),
]
def read(p): return p.read_text(encoding='utf-8-sig')
def sha(b): return hashlib.sha256(b).hexdigest()
def q(s): return "'" + s.replace("'", "''") + "'"
def replace(s, old, new):
    if s.count(old) != 1 or new in s: raise ValueError('MIG21bc1 exact anchor: '+old[:120])
    t=s.replace(old,new,1)
    if t.count(new)!=1 or t.replace(new,old,1)!=s: raise ValueError('MIG21bc1 reversible edit failed')
    return t
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--upstream',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    source={f.relative_to(a.upstream).as_posix():read(f) for f in sorted((a.upstream/'src').rglob('*.ps1'))}
    rows=[]
    for phrase in list(EXACT)+[row[2] for row in PATTERNS]:
        hits=[{'path':path,'line':i} for path,s in source.items() for i,line in enumerate(s.splitlines(),1) if 'Show-Line' in line and phrase in line]
        if not hits: raise ValueError('MIG21bc1 source witness missing: '+phrase)
        rows.append({'phrase':phrase,'sourceMatches':hits,'origin':'generated diagnostic'})
    helper = [
        'function ConvertTo-RuMIG21SysvolDiagnostic {',
        '    param([AllowNull()][string]$Text)',
        '    switch -CaseSensitive ($Text) {',
    ]
    helper += ['        '+q(en)+' { return '+q(ru)+' }' for en,ru in EXACT.items()]
    helper += ['    }']
    helper += ['    if ($Text -cmatch '+q(pattern)+') { return [regex]::Replace($Text, '+q(pattern)+', '+q(ru)+') }' for pattern,ru,_ in PATTERNS]
    helper += ['    return $Text','}', '', 'function Get-RuMIG21CoverageNotice {',
        '    param([AllowNull()][object[]]$Findings)',
        '    $observed = 0',
        '    foreach ($entry in $Findings) {',
        "        if ($null -eq $entry -or $entry.Type -cne 'Line') { continue }",
        "        if ($entry.Class -notin @('Finding','Hint','Note')) { continue }",
        '        $text = [string]$entry.Text',
        '        $display = ConvertTo-RuMIG21SysvolDiagnostic -Text $text',
        '        if ($display -cne $text) { $observed++; continue }',
        '        # Recognize the exact already-localized diagnostic on offline replay.',
        '        if ($text -cin @('+','.join(q(v) for v in EXACT.values())+')) { $observed++; continue }',
        "        if ($text -cmatch '^Не удалось прочитать папки SYSVOL \(количество: [0-9]+\); результат ниже неполный\.$' -or $text -cmatch '^Не удалось прочитать или обработать файлы SYSVOL \(количество: [0-9]+\); результат ниже неполный\.$') { $observed++ }",
        '    }',
        "    $status = if ($observed -gt 0) { 'Обнаружены сообщения об ограничениях SYSVOL: ' + $observed + '. Это число диагностических строк, а не число уникальных файлов или проверок.' } else { 'В известных диагностических строках ограничения SYSVOL не обнаружены; это не подтверждает полноту доступа или проверок.' }",
        "    return '<div id=\"mig21-coverage-notice\" class=\"info-bar\" role=\"note\"><div class=\"info-item\"><div class=\"label\">Полнота аудита</div><div>Complete=True в JSON означает финальный экспорт, а не успешность всех проверок. CompletedModules не подтверждает отсутствие ошибок внутри модулей. ' + $status + '</div></div></div>'",
        '}', '', '',
    ]
    f=a.candidate/EXPORT
    old=read(f)
    anchor='function ConvertTo-RuReportLine {\n    param([AllowNull()][string]$Text)\n    if ([string]::IsNullOrEmpty($Text)) { return $Text }'
    new=replace(old,anchor,'\n'.join(helper)+anchor+'\n    $mig21Display = ConvertTo-RuMIG21SysvolDiagnostic -Text $Text\n    if ($mig21Display -cne $Text) { return $mig21Display }')
    line="        $html = $html.Replace('{{DOMAIN}}', [string](ConvertTo-HtmlEncode $domain))"
    new=replace(new,line,"        $html = $html.Replace('{{MIG21_COVERAGE_NOTICE}}', [string](Get-RuMIG21CoverageNotice -Findings $findings))\n"+line)
    t=a.candidate/TEMPLATE
    oldt=read(t)
    tag='<section id="summary" aria-labelledby="summaryTitle">'
    newt=replace(oldt,tag,tag+'\n            {{MIG21_COVERAGE_NOTICE}}')
    # Only presentation files are modified, preserving the original encoding marker.
    files={}
    for path,content in [(f,new),(t,newt)]:
        raw=path.read_bytes()
        out=(b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+content.encode('utf-8')
        path.write_bytes(out)
        files[path.relative_to(a.candidate).as_posix()]={'beforeSha256':sha(raw),'afterSha256':sha(out)}
    a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG21bc1.Source.1','status':'PASS','sourceWitnesses':rows,'files':files,'jsonSemanticsChanged':False,'findingClassificationChanged':False,'absenceOfKnownDiagnosticsProvesCoverage':False,'realADTestPerformed':False,'productionReady':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS MIG21bc1: source-witnessed SYSVOL diagnostics and separate HTML coverage disclosure')
if __name__=='__main__': main()
