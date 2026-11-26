#!/usr/bin/env python3
"""MIG19f: presentation-only fixes based on real reports; no real AD data."""
import argparse,json,hashlib
from pathlib import Path
def read(p):return p.read_text(encoding='utf-8-sig')
def main():
 a=argparse.ArgumentParser();a.add_argument('--candidate',type=Path,required=True);a.add_argument('--report',type=Path,required=True);a=a.parse_args()
 edits={}
 def replace(path,old,new):
  s=edits.get(path)
  if s is None:s=read(a.candidate/path)
  if s.count(old)!=1 or new==old:raise ValueError('Exact anchor missing: '+path+' '+old[:100])
  out=s.replace(old,new,1)
  if out.count(new)!=1 or out.replace(new,old,1)!=s:raise ValueError('Non-reversible patch: '+path)
  edits[path]=out
 export='src/modules/Reporting/Export-HTMLReport.ps1'
 messages='src/modules/Core/adPEAS-Messages.ps1'
 # Use the already-tested report presentation map; keep canonical header and collected Text.
 replace(export,"        'Analyzing Application Infrastructure' = 'Анализ инфраструктуры приложений'",
 """        'Analyzing Application Infrastructure' = 'Анализ инфраструктуры приложений'
        'Analyzing Shares' = 'Анализ общих ресурсов'
        'Collecting BloodHound Data' = 'Сбор данных BloodHound'
        'Establishing LDAP Connection' = 'Установление соединения LDAP'
        'Scan Summary' = 'Сводка аудита'""")
 replace(export,"        'Who can add computers to the domain:' = 'Субъекты, которым разрешено добавлять компьютеры в домен:'",
 """        'Who can add computers to the domain:' = 'Субъекты, которым разрешено добавлять компьютеры в домен:'
        'Checking which logons Group Policy denies...' = 'Проверка видов входа, запрещённых групповыми политиками...'
        'Searching for computer accounts that still carry the password they were created with...' = 'Поиск учётных записей компьютеров, сохранивших пароль, заданный при создании...'
        'Поиск тонких политик паролей (FGPP)...' = 'Поиск детализированных политик паролей (FGPP)...'""")
 replace(export,"    $ruPatterns = @(\n        @{ Pattern = '^No non-privileged principal holds",
 """    $ruPatterns = @(
        @{ Pattern = '^Found (\d+) computer\(s\) without LAPS protection, by OU:$'; Russian = 'Обнаружено компьютеров без защиты LAPS: $1 (по OU):' }
        @{ Pattern = '^No non-privileged principal holds""")
 helper="""# MIG19f: only translate presentation, after findings collection.
function ConvertTo-RuConsoleText19f {
    param([AllowNull()][string]$Text,[string]$Class)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Class -ceq 'Info') { return (ConvertTo-RuReportSectionTitle -Title $Text) }
    $line = ConvertTo-RuReportLine -Text $Text
    if ($line -cne $Text) { return $line }
    $rules = @(
        @{ Pattern = "^Successfully connected to domain '([^']+)' on server '([^']+)' as '([^']+)' via (.+)$"; Russian = 'Успешное подключение к домену «$1» на сервере «$2» от имени «$3» через $4' }
        @{ Pattern = '^Executing Modules: (.+)$'; Russian = 'Выполняемые модули: $1' }
        @{ Pattern = '^Duration: ([0-9]+(?:[.,][0-9]+)?) seconds$'; Russian = 'Продолжительность: $1 сек.' }
        @{ Pattern = '^Text report saved to: (.+)$'; Russian = 'Текстовый отчёт сохранён в: $1' }
        @{ Pattern = '^HTML report saved to: (.+)$'; Russian = 'HTML-отчёт сохранён в: $1' }
        @{ Pattern = '^JSON export saved to: (.+)$'; Russian = 'Экспорт JSON сохранён в: $1' }
    )
    foreach ($rule in $rules) {
        if ($Text -cmatch $rule.Pattern) {
            return [regex]::Replace($Text, [string]$rule.Pattern, [string]$rule.Russian)
        }
    }
    return $Text
}

"""
 # Place after preceding function, before next existing comment, without moving help.
 replace(export,"# MIG5: translate only a renderer-produced label, never the object name.\nfunction ConvertTo-RuReportObjectTitle {",helper+"# MIG5: translate only a renderer-produced label, never the object name.\nfunction ConvertTo-RuReportObjectTitle {")
 replace(messages,'    if ($Key) {\n        if ($Class -eq "Secure") {',
 """    # MIG19f: translate only the known display keys; collection has already completed.
    if ($Key -ceq 'Session Duration:') { $Key = 'Продолжительность сеанса:' }
    elseif ($Key -ceq 'Authenticated as:') { $Key = 'Аутентификация от имени:' }
    if ($Key) {
        if ($Class -eq "Secure") {""")
 replace(messages,'    switch ($Class) {\n        "Info" {\n            # Main section header with decorative lines',
 """    # MIG19f: canonical Value has already been collected; render the translated copy.
    $Value = ConvertTo-RuConsoleText19f -Text $Value -Class $Class
    switch ($Class) {
        "Info" {
            # Main section header with decorative lines""")
 for path,s in edits.items():(a.candidate/path).write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
 a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19f.Source.1','presentationOnly':True,'sixExactSourcePatches':True,'files':{p:hashlib.sha256((a.candidate/p).read_bytes()).hexdigest() for p in edits},'realADTestPerformedInCI':False,'productionReady':False},indent=2)+'\n',encoding='utf-8')
 print('PASS MIG19f: six reversible display-only source patches; canonical collection unchanged')
if __name__=='__main__':main()
