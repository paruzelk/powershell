#!/usr/bin/env python3
"""MIG19a1: exact source anchors, display-only console localization."""
import argparse, json, hashlib
from pathlib import Path
RULES = json.loads("{\"src/modules/Core/Write-adPEASOutput.ps1\":[[\"[?] Searching for juicy information\",\"[?] Поиск значимой информации\"],[\"[!] Found a vulnerability which may be exploitable\",\"[!] Обнаружена потенциально эксплуатируемая уязвимость\"],[\"[+] Found some interesting information for further investigation\",\"[+] Обнаружены сведения для дальнейшего анализа\"],[\"[*] Some kind of note\",\"[*] Примечание\"],[\"[#] Some kind of secure configuration\",\"[#] Безопасная конфигурация\"],[\"    Active Directory Enumeration\",\"    Аудит Active Directory\"],[\"    Legend\\n        $($Legend[\\\"Info\\\"])\",\"    Условные обозначения\\n        $($Legend[\\\"Info\\\"])\"],[\"                                            Version $Version\",\"                                            Версия $Version\"]],\"src/modules/Core/adPEAS-Messages.ps1\":[[\"function Show-ScanLogo {\",\"function ConvertTo-RuConsoleDisclaimer19 {\\n    param([AllowNull()][string]$Text, [string]$Class)\\n    if ($Class -ceq 'Finding' -and $Text -ceq 'This report was generated using a tool that requires a valid commercial license for consulting or managed service use.') {\\n        return 'Этот отчёт создан с помощью инструмента, для использования которого при оказании консультационных или управляемых услуг требуется действующая коммерческая лицензия.'\\n    }\\n    return $Text\\n}\\n\\nfunction Show-ScanLogo {\"],[\"Show-Line ([string]$Disclaimer.Text) -Class ([string]$Disclaimer.Class) -FileOnly:$importOnScreen\",\"Show-Line (ConvertTo-RuConsoleDisclaimer19 -Text ([string]$Disclaimer.Text) -Class ([string]$Disclaimer.Class)) -Class ([string]$Disclaimer.Class) -FileOnly:$importOnScreen\"],[\"Show-SubHeader \\\"Quick Start\\\"\",\"Show-SubHeader \\\"Быстрый старт\\\"\"],[\"Show-Line \\\"Simple scan (Windows Auth):\\\"\",\"Show-Line \\\"Простое сканирование (аутентификация Windows):\\\"\"],[\"Show-Line \\\"Session-based with credentials:\\\"\",\"Show-Line \\\"Подключение с учётными данными:\\\"\"],[\"Show-Line \\\"On domain-joined machines, -Password/-NTHash/-AES*Key/-Certificate replace your Kerberos tickets.\\\"\",\"Show-Line \\\"На компьютерах в домене параметры -Password/-NTHash/-AES*Key/-Certificate заменяют ваши билеты Kerberos.\\\"\"],[\"Show-Line \\\"Use Connect-adPEAS with -ForceNTLM or -ForceSimpleBind to avoid this.\\\"\",\"Show-Line \\\"Чтобы избежать этого, используйте Connect-adPEAS с -ForceNTLM или -ForceSimpleBind.\\\"\"],[\"Show-Line \\\"More help:\\\"\",\"Show-Line \\\"Дополнительная справка:\\\"\"],[\"Show-SubHeader \\\"Security Check Modules\\\"\",\"Show-SubHeader \\\"Модули проверки безопасности\\\"\"],[\"Show-Line \\\"Run all modules:\\\"\",\"Show-Line \\\"Запустить все модули:\\\"\"],[\"Show-Line \\\"Invoke-adPEAS (without -Module)\\\"\",\"Show-Line \\\"Invoke-adPEAS (без -Module)\\\"\"],[\"Show-Line \\\"Run specific modules only:\\\"\",\"Show-Line \\\"Запустить только выбранные модули:\\\"\"],[\"Show-Line \\\"Run one check alone - by the name on its left:\\\"\",\"Show-Line \\\"Запустить отдельную проверку по имени слева:\\\"\"],[\"Show-SubHeader \\\"Additional Core and Helper Modules\\\"\",\"Show-SubHeader \\\"Дополнительные основные и вспомогательные команды\\\"\"],[\"Show-Line \\\"Checks - run in the scan, or alone by this name:\\\"\",\"Show-Line \\\"Проверки — в составе аудита или отдельно по имени:\\\"\"],[\"Show-Line \\\"Commands:\\\"\",\"Show-Line \\\"Команды:\\\"\"],[\"Show-SubHeader \\\"adPEAS checks and commands matching '$Search'\\\"\",\"Show-SubHeader \\\"Проверки и команды adPEAS по запросу '$Search'\\\"\"],[\"Show-Line \\\"No check or command matches '$Search' - Get-adPEASHelp lists them all\\\"\",\"Show-Line \\\"Нет проверок или команд по запросу '$Search'; полный список: Get-adPEASHelp\\\"\"]],\"src/adPEAS.ps1\":[[\"Show-Line $_importDisclaimer.Text -Class $_importDisclaimer.Class\",\"Show-Line (ConvertTo-RuConsoleDisclaimer19 -Text $_importDisclaimer.Text -Class $_importDisclaimer.Class) -Class $_importDisclaimer.Class\"]]}")
def main():
 p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
 changes={}
 applied={}
 already={}
 for name,rules in RULES.items():
  path=a.candidate/name
  original=path.read_text(encoding='utf-8-sig')
  s=original
  applied[name]=[]
  already[name]=[]
  for old,new in rules:
   old_count,new_count=s.count(old),s.count(new)
   # MIG4 already applies this exact DOC6f translation; no generic skip.
   if (name=='src/modules/Core/adPEAS-Messages.ps1'
       and old=='Show-Line "Invoke-adPEAS (without -Module)"'
       and old_count==0 and new_count==1):
    already[name].append(old)
    continue
   if old_count!=1 or new_count!=0:raise ValueError('Unexpected anchor: '+name+': '+old)
   s=s.replace(old,new,1)
   applied[name].append((old,new))
  reverse=s
  for old,new in reversed(applied[name]):
   if reverse.count(new)!=1:raise ValueError('Reverse anchor: '+name)
   reverse=reverse.replace(new,old,1)
  if reverse!=original:raise ValueError('Non-reversible patch: '+name)
  changes[path]=s
 if sum(map(len,applied.values()))!=26 or sum(map(len,already.values()))!=1:raise ValueError('MIG19a2 coverage mismatch: expected 26 new + 1 prior DOC6f translation')
 for path,s in changes.items():path.write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
 a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19a2.Source.1','newChanges':26,'previouslyTranslated':1,'priorWitness':already,'files':{str(p.relative_to(a.candidate)):{'changes':len(applied[p.relative_to(a.candidate).as_posix()]),'alreadyTranslated':len(already[p.relative_to(a.candidate).as_posix()]),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in changes},'licenseValidationModified':False,'realADTestPerformed':False},indent=2),encoding='utf-8')
 print('PASS MIG19a2: 26 reversible new changes and 1 verified DOC6f translation')
if __name__=='__main__':main()
