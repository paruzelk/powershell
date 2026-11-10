#Requires -Version 5.1
<#
.SYNOPSIS
  Перевод навигации и динамических кнопок HTML без изменения категорий фильтров.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($true)
$path=Join-Path $ProjectRoot 'src/modules/Reporting/Export-HTMLReport.ps1'
$s=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$source='$catNameEncoded = ConvertTo-HtmlEncode $catName'
$replacement=@'
        $ruCategoryNames = @{
            Accounts='Учётные записи'; ADCS='AD CS'; Delegation='Делегирование'
            Domain='Домен'; GPO='Групповые политики'; Rights='Права доступа'
            Creds='Учётные данные'; Computer='Компьютеры'; Application='Приложения'
            Shares='Общие ресурсы'; Bloodhound='BloodHound'
        }
        $nameRu = if($ruCategoryNames.ContainsKey($catName)){$ruCategoryNames[$catName]}else{$catName}
        $catNameEncoded = ConvertTo-HtmlEncode $nameRu
'@
if(-not $s.Contains($source)){throw 'Не найден источник названий категорий'}
$s=$s.Replace($source,$replacement)
$labels=@{
 '        All Categories'='        Все категории'
 '> Expand All</button>'='> Развернуть всё</button>'
 'Click for more info'='Подробнее о проверке'
 'Expand/Collapse all objects'='Развернуть или свернуть все объекты'
 'Drag to resize the name column'='Перетащите для изменения ширины названий'
}
foreach($p in $labels.GetEnumerator()){
 if(-not $s.Contains($p.Key)){throw "Не найден текст интерфейса HTML: $($p.Key)"}
 $s=$s.Replace($p.Key,$p.Value)
}
[IO.File]::WriteAllText($path,$s,$utf8)
# Текст темы — только подпись, не ключ localStorage или HTML-атрибут.
$template=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-template.html'
$h=[IO.File]::ReadAllText($template,[Text.Encoding]::UTF8)
$h=$h.Replace('<span id="themeLabel">Light</span>','<span id="themeLabel">Светлая</span>')
[IO.File]::WriteAllText($template,$h,$utf8)
$jsPath=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($jsPath,[Text.Encoding]::UTF8)
$en="document.getElementById('themeLabel').textContent = theme === 'dark' ? 'Light' : 'Dark';"
$ru="document.getElementById('themeLabel').textContent = theme === 'dark' ? 'Светлая' : 'Тёмная';"
if(-not $js.Contains($en)){throw 'Не найдена подпись переключателя темы'}
$js=$js.Replace($en,$ru)
[IO.File]::WriteAllText($jsPath,$js,$utf8)
Write-Host '[RU] Навигация HTML: 11 категорий, кнопки, подписи темы'
