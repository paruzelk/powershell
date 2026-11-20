#!/usr/bin/env python3
"""MIG9: source-witnessed Russian UI for dynamic priorities, score tooltips and help.

The existing MIG1/MIG2/MIG3 catalogs supply all translated findings. Only
display values in the report are changed. Risk, original definitions, AD data,
IDs, generated JSON and license rules are not changed.
"""
import argparse
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ENC="utf-8-sig"
def read(p): return p.read_text(encoding=ENC)
def save(p,s): p.write_text(s,encoding=ENC)
def once(s,a,b,where):
    n=s.count(a)
    if n!=1:raise ValueError("MIG9 "+where+": source witness expected once, got "+str(n)+" / "+a[:65])
    return s.replace(a,b,1)

def patch_js(root,proof):
    p=root/"src/modules/Reporting/templates/report-scripts.js"
    s=read(p)
    s=once(s,
        "const checkInfo = (objectType && checkDescriptions) ? checkDescriptions[objectType] : null;",
        "const checkInfoRaw = (objectType && checkDescriptions) ? checkDescriptions[objectType] : null;\n                const checkInfo = checkInfoRaw ? Object.assign({}, checkInfoRaw, ruMIG2CheckDetails[objectType] || {}) : null;",
        "priority impact from already-reviewed Russian check details")
    s=once(s,
        "const remediationText = findingDef?.remediation?.[0] || '';",
        """// Use original matched definition by identity; never alter the matching algorithm or scoring.
                const matchedFindingId = findingDef ? Object.keys(findingDefinitions).find(id => findingDefinitions[id] === findingDef) : null;
                const translatedRemediation = matchedFindingId && ruMIG2Technical[matchedFindingId]?.remediation;
                const remediationText = Array.isArray(translatedRemediation) && translatedRemediation.length > 0
                    ? translatedRemediation[0] : (findingDef?.remediation?.[0] || '');""",
        "priority remediation from existing Russian technical catalog")
    s=once(s,"$"+"{objectCount} affected</span>",
           "Затронуто объектов: $"+"{objectCount}</span>","affected-object label")
    # The ordinary check tooltips already use this exact Russian overlay.
    start=s.index("function showTopActionInfo(")
    end=s.index("        function showTooltipAt(",start)
    segment=s[start:end]
    segment=once(segment,
        "const checkInfo = checkDescriptions[objectType];",
        "const checkInfo = Object.assign({}, checkDescriptions[objectType], ruMIG2CheckDetails[objectType] || {});",
        "priority information popup")
    labels={">Summary<":">Краткое описание<",">Why It Matters<":">Почему это важно<",
            ">What We Check<":">Что проверяется<",">Note<":">Примечание<"}
    for a,b in labels.items():segment=once(segment,a,b,"priority-popup "+a)
    s=s[:start]+segment+s[end:]
    proof["PriorityRussianCatalogOverlays"]=3
    proof["PriorityInfoLabels"]=len(labels)
    # Dynamic per-finding object controls switch back to English after a click in MIG8a.
    s=once(s,"? '<span>&#9660;</span> Collapse All'",
           "? '<span>&#9660;</span> Свернуть всё'","expand button state")
    s=once(s,": '<span>&#9654;</span> Expand All'",
           ": '<span>&#9654;</span> Развернуть всё'","collapse button state")
    # A separate display formatter translates the known reasons without modifying
    # any input to the scoring algorithm or the underlying score breakdown.
    reason_helper="""function translateMIG9ScoreReason(raw) {
            const names = {
                'Standard': 'Обычные условия',
                'Maximum (DCSync)': 'Максимальный риск (DCSync)',
                'Tier 0 (Domain Admin)': 'Tier 0 (администратор домена)',
                'Tier 1 (Server Admin)': 'Tier 1 (администратор сервера)',
                'Tier 2 (Workstation Admin)': 'Tier 2 (администратор рабочей станции)',
                'Non-Admin': 'Без административных прав',
                'RC4 encryption': 'Шифрование RC4',
                'Easier to exploit': 'Выше возможность эксплуатации',
                'Harder to exploit': 'Ниже возможность эксплуатации',
                'Disabled': 'Учётная запись отключена',
                'Smartcard required': 'Требуется смарт-карта',
                'Protected Users': 'Группа Protected Users',
                'Mitigated': 'Риск снижен',
                'Vulnerable': 'Уязвимо',
                'Appears in multiple findings': 'Упоминается в нескольких находках'
            };
            const passwordAge = typeof raw === 'string' && raw.match(/^Old password \((\d+)y\)$/);
            if (passwordAge) return 'Давно не менялся пароль (' + passwordAge[1] + ' г.)';
            return names[raw] || raw;
        }

        """
    s=once(s,"function formatScoreBreakdownHtml(breakdown) {",
           reason_helper+"function formatScoreBreakdownHtml(breakdown) {","display-only reason translator")
    # Risk labels only, leaving unmodified the numeric score and source reason values.
    start=s.index("function formatScoreBreakdownHtml(")
    end=s.index("        // Active score tooltip reference",start)
    segment=s[start:end]
    headings={
        "No risk score (informational)":"Оценка риска отсутствует (информационный результат)",
        "Base Score":"Базовая оценка","Impact":"Последствия",
        "Exploitability":"Возможность эксплуатации","Security":"Защитные меры",
        "Correlation":"Взаимосвязи"}
    for a,b in headings.items():
        old='class="score-tooltip-label">'+a
        segment=once(segment,old,'class="score-tooltip-label">'+b,"score label "+a)
    old=">Score Breakdown<"
    if segment.count(old)!=2:raise ValueError("MIG9 two score headers expected")
    segment=segment.replace(old,">Состав оценки риска<")
    for original,localized in (
        ("escapeHtml(breakdown.impactReason)","escapeHtml(translateMIG9ScoreReason(breakdown.impactReason))"),
        ("breakdown.exploitReasons.join(', ')","breakdown.exploitReasons.map(translateMIG9ScoreReason).join(', ')"),
        ("breakdown.securityReasons.join(', ')","breakdown.securityReasons.map(translateMIG9ScoreReason).join(', ')"),
        ("escapeHtml(breakdown.correlationReason)","escapeHtml(translateMIG9ScoreReason(breakdown.correlationReason))")
    ):
        segment=once(segment,original,localized,"score reason rendering")
    s=s[:start]+segment+s[end:]
    proof["ScoreLabels"]=8
    proof["ScoreReasonSourceTypes"]=16
    # Guide: exact translations of every displayed English paragraph and control label.
    guide=json.loads(read(HERE/"MIG9-ReportGuide.ru-RU.json"))["Translations"]
    backtick=chr(96)
    start=s.index("modal.innerHTML = "+backtick,s.index("function createShortcutHelpModal()"))
    end=s.index(backtick+";",start)
    segment=s[start:end]
    for a,b in sorted(guide.items(),key=lambda kv:-len(kv[0])):
        segment=once(segment,a,b,"guide "+a[:45])
    s=s[:start]+segment+s[end:]
    proof["GuideLabels"]=len(guide)
    save(p,s)

def patch_ps(root,proof):
    p=root/"src/modules/Core/Render-HtmlObject.ps1"
    s=read(p)
    marker="    return $Text\n}\n\nfunction ConvertTo-RuReportAttributeLabel7 {"
    extra="""    # MIG9: presentation-only suffixes for this precise attribute.
    # Preserve actual group names, AD SIDs, membership and original evidence.
    if ($Name -ceq 'privilegedGroups') {
        return $Text.Replace(' (direct)', ' (прямое членство)').Replace(' (nested)', ' (через вложенную группу)')
    }
    return $Text
}

function ConvertTo-RuReportAttributeLabel7 {"""
    s=once(s,marker,extra,"privileged-group display context")
    save(p,s)
    p=root/"src/modules/Reporting/Export-HTMLReport.ps1"
    s=read(p)
    old="title="+chr(96)+'"Expand/Collapse all objects'+chr(96)+'"'
    new="title="+chr(96)+'"Развернуть или свернуть все объекты'+chr(96)+'"'
    s=once(s,old,new,"per-card object controls help title")
    save(p,s)
    proof["GroupMembershipLabelsDisplayOnly"]=True
    proof["OriginalGroupNamesAndIdsPreserved"]=True

def main():
    parser=argparse.ArgumentParser()
    for name in ("candidate","report"):parser.add_argument("--"+name,required=True,type=Path)
    o=parser.parse_args()
    proof={"Schema":"adPEAS-RU.2.11.0.MIG9.1",
           "DisplayOnly":True,"FindingDefinitionsModified":False,
           "ScoringLogicModified":False,"JsonExportModified":False,
           "LicenseValidationModified":False,"RealADTestPerformed":False,
           "ProductionReady":False}
    patch_js(o.candidate,proof)
    patch_ps(o.candidate,proof)
    o.report.parent.mkdir(parents=True,exist_ok=True)
    save(o.report,json.dumps(proof,ensure_ascii=False,indent=2)+"\n")
    print("MIG9 PASS: original translated impact/remediation reused; priority popup, complete help, score labels, membership display localized")
if __name__=="__main__":main()
