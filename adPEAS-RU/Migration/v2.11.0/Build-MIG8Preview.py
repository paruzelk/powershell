#!/usr/bin/env python3
"""MIG8: HTML display-only fixes, precise audit outcome vs card count labels."""
import argparse
import json
from pathlib import Path

ENC="utf-8-sig"
def read(p): return p.read_text(encoding=ENC)
def save(p,s): p.write_text(s,encoding=ENC)
def one(s,old,new,where):
    n=s.count(old)
    if n!=1: raise ValueError("MIG8 anchor "+where+" expected 1 got "+str(n))
    return s.replace(old,new,1)
def patch_table(p,m):
    s=read(p)
    for a,b in m.items(): s=one(s,a,b,p.name+" "+a[:60])
    save(p,s)

def patch_template(c,r):
    p=c/"src/modules/Reporting/templates/report-template.html"
    m={
        'aria-label="Toggle theme"':'aria-label="Переключить тему"',
        'title="Toggle Dark/Light Mode"':'title="Переключить светлую и тёмную тему"',
        'title="Keyboard Shortcuts (?)"':'title="Горячие клавиши (?)"',
        'aria-label="Show keyboard shortcuts and help"':'aria-label="Открыть справку и горячие клавиши"',
        'aria-label="Print report or save as PDF"':'aria-label="Печать отчёта или сохранение в PDF"',
        'title="Expand all cards and top priorities"':'title="Развернуть карточки и приоритетные действия"',
        'aria-label="Expand all finding cards"':'aria-label="Развернуть все карточки проверок"',
        'title="Collapse all cards and top priorities"':'title="Свернуть карточки и приоритетные действия"',
        'aria-label="Collapse all finding cards"':'aria-label="Свернуть все карточки проверок"'
    }
    s=read(p)
    for a,b in m.items():s=one(s,a,b,"template "+a)
    info='''            <!-- MIG8: clear audit outcome/card unit labels; no change to underlying counts. -->
            <div class="count-unit-note" role="note" style="margin: -8px 0 18px; color: var(--text-muted); font-size: 12px;">
                Результатов исходной сводки: <strong>{{TOTAL_COUNT}}</strong>.
                Карточек проверок: <strong id="mig8CardCount">—</strong>.
                Счётчики фильтров показывают невыполненные карточки.
            </div>

'''
    s=one(s,'            <!-- Card Controls -->',info+'            <!-- Card Controls -->',"counter unit note")
    save(p,s)
    r["TemplateStaticLabels"]=len(m)
    r["PreservedOriginalTotalPlaceholder"]=True

def patch_export(c,r):
    p=c/"src/modules/Reporting/Export-HTMLReport.ps1"
    q=chr(96)
    m={
        'aria-label='+q+'"Mark as completed'+q+'"':'aria-label='+q+'"Отметить как выполненное'+q+'"',
        'title='+q+'"Click for more info'+q+'"':'title='+q+'"Подробности проверки'+q+'"',
        'title='+q+'"Drag to resize the name column'+q+'"':'title='+q+'"Изменить ширину столбца названий'+q+'"',
    }
    patch_table(p,m)
    r["ExporterAccessibilityLabels"]=len(m)

def patch_renderer(c,r):
    p=c/"src/modules/Core/Render-HtmlObject.ps1"
    s=read(p)
    q=chr(96)
    a='title='+q+'"Drag to reorder'+q+'"'
    if s.count(a)!=6:raise ValueError("MIG8 original drag handle expected 6")
    s=s.replace(a,'title='+q+'"Изменить порядок перетаскиванием'+q+'"')
    code=r'''# MIG8: display-only field-specific text. Raw AD values and keys are never modified.
function ConvertTo-RuReportAttributeContext8 {
    param([AllowNull()][string]$Name, [AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Name -ceq 'iscriticalsystemobject') {
        if ($Text -ceq 'TRUE') { return 'Да' }
        if ($Text -ceq 'FALSE') { return 'Нет' }
    }
    if ($Name -ceq 'operatingSystems') {
        if ($Text -cmatch '^(\d+) server\(s\)(?:, (\d+) client\(s\), (\d+) other)?$') {
            $result = 'Серверов: ' + $Matches[1]
            if ($Matches.ContainsKey(2)) {
                $result += ', клиентов: ' + $Matches[2] + ', прочих: ' + $Matches[3]
            }
            return $result
        }
    }
    if ($Name -ceq 'domainControllers') {
        if ($Text -match '^(.*) \[((?:PDC Emulator|Schema Master|Infrastructure Master|Domain Naming Master|RID Master)(?:, (?:PDC Emulator|Schema Master|Infrastructure Master|Domain Naming Master|RID Master))*)\]$') {
            $prefix = $Matches[1]
            $roles = $Matches[2]
            $ru = @{
                'PDC Emulator' = 'Эмулятор PDC'
                'Schema Master' = 'Мастер схемы'
                'Infrastructure Master' = 'Мастер инфраструктуры'
                'Domain Naming Master' = 'Мастер именования доменов'
                'RID Master' = 'Мастер RID'
            }
            $list = @($roles.Split(',') | ForEach-Object {
                $role = $_.Trim()
                if ($ru.ContainsKey($role)) { [string]$ru[$role] } else { $role }
            })
            return $prefix + ' [' + ($list -join ', ') + ']'
        }
    }
    return $Text
}

'''
    s=one(s,"function ConvertTo-RuReportAttributeLabel7 {",code+"function ConvertTo-RuReportAttributeLabel7 {","renderer helper")
    old="(ConvertTo-RuReportAttributeContext7 -Name $Row.Name -Text (ConvertTo-RuReportAttributeValue -Text $val.Display))"
    if s.count(old)!=2:raise ValueError("MIG8 expected two original display calls")
    s=s.replace(old,"(ConvertTo-RuReportAttributeContext8 -Name $Row.Name -Text "+old+")")
    save(p,s)
    r["StaticRendererDragLabels"]=6
    r["ValueContexts"]=3
    r["OriginalAttributeKeysPreserved"]=True

def patch_js(c,r):
    p=c/"src/modules/Reporting/templates/report-scripts.js"
    m={
        'title="Toggle Top Priority Actions"':'title="Показать или скрыть приоритетные действия"',
        'title="More Info"':'title="Дополнительные сведения"',
        "'Risk Score (click for details)'":"'Оценка риска (нажмите для подробностей)'",
        'title="Remove all adPEAS data from browser storage"':'title="Удалить данные adPEAS из хранилища браузера"',
        "'Show information about this check'":"'Показать сведения об этой проверке'",
        "'Finding details'":"'Подробности находки'",
        'aria-label="Close help dialog"':'aria-label="Закрыть окно справки"'
    }
    s=read(p)
    for a,b in m.items():s=one(s,a,b,"js "+a)
    countmarker="        function updateSidebarCounts() {\n"
    add="""        function updateSidebarCounts() {
            // MIG8: the original audit total is distinct from interactive check cards.
            const output = document.getElementById('mig8CardCount');
            if (output) output.textContent = String(document.querySelectorAll('.finding-card').length);
"""
    s=one(s,countmarker,add,"card count")
    old="""                if (el) {
                    el.textContent = severityCounts[severity];
                }
"""
    new="""                if (el) {
                    el.textContent = severityCounts[severity];
                    const labels = {
                        finding: 'Показать нарушения',
                        hint: 'Показать предупреждения',
                        note: 'Показать сведения',
                        secure: 'Показать безопасные карточки'
                    };
                    const button = el.closest('.summary-card');
                    if (button) button.setAttribute('aria-label', labels[severity] + ': ' + severityCounts[severity]);
                }
"""
    s=one(s,old,new,"accessible summary")
    save(p,s)
    r["DynamicLabels"]=len(m)
    r["FilterCardCountersKept"]=True
    r["OriginalAuditCountersKept"]=True
    r["AccessibleSummaryCountsUpdated"]=True

def main():
    ap=argparse.ArgumentParser()
    for key in ("new","candidate","report"):ap.add_argument("--"+key,required=True,type=Path)
    o=ap.parse_args()
    r={"Schema":"adPEAS-RU.2.11.0.MIG8.1","UpstreamCommit":"477696f48d6b486be5d9a99b598f72e3ccfcc0c0",
       "OnlyDisplayLocalization":True,"OriginalADDataModified":False,
       "FindingDefinitionsModified":False,"JsonExportModified":False,"ProductionReady":False,"RealADTestPerformed":False}
    patch_template(o.candidate,r)
    patch_export(o.candidate,r)
    patch_renderer(o.candidate,r)
    patch_js(o.candidate,r)
    o.report.parent.mkdir(parents=True,exist_ok=True)
    save(o.report,json.dumps(r,ensure_ascii=False,indent=2)+"\n")
    print("MIG8 PASS: source-side accessibility, field-context values, separate audit results/check cards")
if __name__=="__main__":main()
