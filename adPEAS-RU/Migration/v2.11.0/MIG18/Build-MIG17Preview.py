#!/usr/bin/env python3
"""Translate the pinned upstream EXE build messages, without changing launcher logic."""
import argparse, hashlib, json
from pathlib import Path

PIN = '477696f48d6b486be5d9a99b598f72e3ccfcc0c0'
FILES = {
 'Build-Engine.ps1': ('3ab7377420ed6a969b95c8cc35775578e47c9c58', [
  ('[Build] Script to embed not found: $ScriptPath', '[Сборка] Встраиваемый скрипт не найден: $ScriptPath'),
  ('[Build] Icon not found: $IconPath', '[Сборка] Иконка не найдена: $IconPath'),
  ('[Build] Windows PowerShell 5.1 not found ($windowsPowerShell) - it compiles the executable', '[Сборка] Windows PowerShell 5.1 не найден ($windowsPowerShell) — он необходим для компиляции EXE'),
  ('Embedded script {RESOURCE} not found', 'Встроенный скрипт {RESOURCE} не найден'),
  ('Microsoft.PowerShell.ConsoleHost is not loaded', 'Сборка Microsoft.PowerShell.ConsoleHost не загружена'),
  ('[Build] Compiling $(Split-Path -Leaf $OutputPath) failed (exit code $exitCode)', '[Сборка] Не удалось скомпилировать $(Split-Path -Leaf $OutputPath) (код завершения $exitCode)'),
  ('[System.IO.File]::WriteAllText($sourcePath, $source, (New-Object System.Text.UTF8Encoding($false)))', '[System.IO.File]::WriteAllText($sourcePath, $source, (New-Object System.Text.UTF8Encoding($true)))'),
 ]),
 'Build-Release.ps1': ('9516cd996df8deea0b5a63f5867e899f67554cfd', [
  ('[Build] Creating console executable: $($ExeVariant.FileName)', '[Сборка] Создание консольного исполняемого файла: $($ExeVariant.FileName)'),
  ("[Build] Variants.Executable.BasedOn must be Readable, Minimized or Ultra, not '$($ExeVariant.BasedOn)'", "[Сборка] Variants.Executable.BasedOn должен иметь значение Readable, Minimized или Ultra, а не '$($ExeVariant.BasedOn)'"),
  ('Description = "$($Config.ProjectName) $BuildVersion"', 'Description = "$($Config.ProjectName) $BuildVersion — аудит безопасности Active Directory"'),
  ('[Build] Icon for $($ExeVariant.FileName) not found: $ExeIconPath', '[Сборка] Иконка для $($ExeVariant.FileName) не найдена: $ExeIconPath'),
  ('[Build]   - Icon: $($ExeVariant.Icon)', '[Сборка]   - Иконка: $($ExeVariant.Icon)'),
  ('[Build]   - Embedding $(Split-Path -Leaf $ExeBasePath), compiling with the .NET Framework C# compiler...', '[Сборка]   - Встраивание $(Split-Path -Leaf $ExeBasePath), компиляция C# средствами .NET Framework...'),
  ('[Build] Console executable created: $ExeOutputPath', '[Сборка] Консольный исполняемый файл создан: $ExeOutputPath'),
  ('[Build] Size: $([Math]::Round($ExeSize, 2)) KB', '[Сборка] Размер: $([Math]::Round($ExeSize, 2)) КБ'),
 ])
}
def gitsha(b):
 return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def transform(s, rules):
 for old,new in rules:
  if s.count(old)!=1 or new in s: raise ValueError('Unexpected anchor: '+old)
  s=s.replace(old,new,1)
 return s

def main():
 p=argparse.ArgumentParser();p.add_argument('--upstream',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.upstream.resolve()==a.out.resolve(): raise ValueError('Use a separate output directory')
 outputs={}; report={}
 for name,(sha,rules) in FILES.items():
  raw=(a.upstream/name).read_bytes()
  # Accept Git checkout CRLF only if its LF-normalized bytes exactly match the pinned blob.
  if gitsha(raw)!=sha: raw=raw.replace(b'\r\n',b'\n')
  if gitsha(raw)!=sha: raise ValueError('Wrong upstream blob: '+name)
  source=raw.decode('utf-8-sig');result=transform(source,rules)
  assert transform(result,[(n,o) for o,n in reversed(rules)])==source
  outputs[name]=b'\xef\xbb\xbf'+result.encode('utf-8')
  report[name]={'upstreamGitBlob':sha,'changes':len(rules),'sha256':hashlib.sha256(outputs[name]).hexdigest()}
 a.out.mkdir(parents=True,exist_ok=True)
 for name,raw in outputs.items(): (a.out/name).write_bytes(raw)
 (a.out/'MIG17-patch-result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print(json.dumps(report,indent=2))
if __name__=='__main__': main()
