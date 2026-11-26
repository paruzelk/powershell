#!/usr/bin/env python3
"""MIG19j: narrow presentation fixes from MIG19i; no real domain data."""
import argparse,hashlib,json
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
 edits={};witness=[]
 def replace(path,old,new):
  s=edits.get(path)
  if s is None:s=(a.candidate/path).read_text(encoding='utf-8-sig')
  if s.count(old)!=1 or new==old:raise ValueError('Exact anchor missing: '+path+' '+old[:100])
  t=s.replace(old,new,1)
  if t.count(new)!=1 or t.replace(new,old,1)!=s:raise ValueError('Non-reversible patch: '+path)
  edits[path]=t;witness.append(path)
 export='src/modules/Reporting/Export-HTMLReport.ps1'
 replace(export,"    $ruPatterns = @(\n        @{ Pattern = '^Found",
 r"""    # MIG19j: only this generated collector summary; preserve domain and numeric counts.
    if ($Text -cmatch '^(Собрано объектов: \d+; домен: [^:\r\n]+: )((?:\d+ (?:domains|users|groups|computers|OUs|containers|GPOs|ADCS objects))(?:, \d+ (?:domains|users|groups|computers|OUs|containers|GPOs|ADCS objects))*)$') {
        $prefix = $Matches[1]
        $parts = $Matches[2] -split ', '
        $labels = @{ 'domains'='доменов'; 'users'='пользователей'; 'groups'='групп'; 'computers'='компьютеров'; 'OUs'='OU'; 'containers'='контейнеров'; 'GPOs'='GPO'; 'ADCS objects'='объектов AD CS' }
        $translated = foreach ($part in $parts) {
            if ($part -cmatch '^(\d+) (.+)$') { $labels[$Matches[2]] + ': ' + $Matches[1] }
        }
        return $prefix + ($translated -join ', ')
    }
    $ruPatterns = @(
        @{ Pattern = '^Компьютеры с устаревшей версией Microsoft Windows: (\d+) \((\d+) inactive accounts filtered\)$'; Russian = 'Компьютеры с устаревшей версией Microsoft Windows: $1 (исключено неактивных учётных записей: $2)' }
        @{ Pattern = '^Found""")
 replace('src/modules/Core/Render-HtmlObject.ps1',"'lapsUnprotectedComputers' = 'Количество компьютеров без защиты LAPS'","'lapsUnprotectedComputers' = 'Список компьютеров без защиты LAPS'")
 replace('src/modules/Core/Write-adPEASOutput.ps1',
 "$paddingSpaces = ' ' * ([Math]::Max(0, $Width - $nameWithColon.Length))",
 "$minimumPadding = if ($Name) { 1 } else { 0 }\n    $paddingSpaces = ' ' * ([Math]::Max($minimumPadding, $Width - $nameWithColon.Length))")
 replace('src/modules/Core/adPEAS-Messages.ps1',
 "    elseif ($Key -ceq 'Authenticated as:') { $Key = 'Аутентификация от имени:' }",
 "    elseif ($Key -ceq 'Authenticated as:') { $Key = 'Аутентификация от имени:' }\n    elseif ($Key -ceq 'Domain:') { $Key = 'Домен:' }")
 for path,s in edits.items():(a.candidate/path).write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
 a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19j.Source.1','presentationOnly':True,'patches':len(witness),'files':{path:hashlib.sha256((a.candidate/path).read_bytes()).hexdigest() for path in edits},'realADTestPerformedInCI':False,'productionReady':False},indent=2)+'\n',encoding='utf-8')
 print('PASS MIG19j: four reversible presentation changes')
if __name__=='__main__':main()
