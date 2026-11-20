#!/usr/bin/env python3
"""MIG8a regression hotfix: translate prominent HTML notices at their source.

No license validation, audit rules, raw domain data or scoring logic are changed.
"""
import argparse
import json
from pathlib import Path

ENC = "utf-8-sig"
DISCLAIMER_EN = (
    "This report was generated using a tool that requires a valid "
    "commercial license for consulting or managed service use."
)
DISCLAIMER_RU = (
    "Этот отчёт создан с помощью инструмента, для использования которого "
    "при оказании консультационных или управляемых услуг требуется "
    "действующая коммерческая лицензия."
)

def read(p):
    return p.read_text(encoding=ENC)

def save(p, value):
    p.write_text(value, encoding=ENC)

def change_once(txt, old, new, label):
    n = txt.count(old)
    if n != 1:
        raise ValueError("MIG8a source anchor " + label + " count=" + str(n))
    return txt.replace(old, new, 1)

def patch_report(candidate, proof):
    p = candidate / "src/modules/Reporting/Export-HTMLReport.ps1"
    s = read(p)
    original = "$html = $html.Replace('{{DISCLAIMER}}', [string](ConvertTo-HtmlEncode $disclaimer))"
    replacement = """# MIG8a: only translate the DISPLAY of the exact known legal notice.
        # The license terms, license enforcement and original variable remain intact.
        $visibleDisclaimer = $disclaimer
        if ($disclaimer -ceq '""" + DISCLAIMER_EN + """') {
            $visibleDisclaimer = '""" + DISCLAIMER_RU + """'
        }
        $html = $html.Replace('{{DISCLAIMER}}', [string](ConvertTo-HtmlEncode $visibleDisclaimer))"""
    s = change_once(s, original, replacement, "single shared print/header disclaimer")
    if "$Script:adPEASDisclaimer" not in s:
        raise ValueError("MIG8a original license source unexpectedly absent")
    save(p, s)
    proof["LicenseNoticeUnmodifiedAtSource"] = True
    proof["KnownEnglishLegalNoticeTranslatedOnlyForHtml"] = True
    proof["HeaderAndPrintUseSameDisclaimerToken"] = True

def patch_js(candidate, proof):
    p = candidate / "src/modules/Reporting/templates/report-scripts.js"
    s = read(p)
    rows = [
        (
            '<div class="help-card-title">Top Priority Actions</div>',
            '<div class="help-card-title">Первоочередные действия</div>'
        ),
        (
            'AI-scored findings ranked by risk. Start here for the most critical issues.',
            'Находки упорядочены по оценке риска. Начните с наиболее серьёзных проблем.'
        ),
        (
            '<strong>Start with Top Priority Actions</strong> - These are automatically ranked by exploitability and impact.',
            '<strong>Начните с первоочередных действий</strong> — они автоматически упорядочены по возможности эксплуатации и последствиям.'
        ),
        (
            '                            Top Priority Actions\n',
            '                            Первоочередные действия\n'
        ),
        (
            ' critical findings total</span>',
            ' критических находок всего</span>'
        ),
        (
            '                                No Critical Findings\n',
            '                                Критических находок не выявлено\n'
        ),
        (
            'No high-priority security issues were detected. Review the hints and notes for potential improvements.',
            'Проблем безопасности высокого приоритета не обнаружено. Проверьте предупреждения и сведения для возможных улучшений.'
        )
    ]
    for old, new in rows:
        s = change_once(s, old, new, "HTML/JS literal " + old[:46])
    if 'critical findings total</span>' in s or '                            Top Priority Actions\n' in s:
        raise ValueError("MIG8a visible priority text untranslated")
    save(p, s)
    proof["SourceDynamicLabelsTranslated"] = len(rows)
    proof["PriorityFindingCountVariablePreserved"] = '$' + '{totalCriticalCount}' in s
    if not proof["PriorityFindingCountVariablePreserved"]:
        raise ValueError("MIG8a critical count expression unexpectedly lost")

def main():
    ap = argparse.ArgumentParser()
    for k in ("candidate","report"): ap.add_argument("--"+k,required=True,type=Path)
    o = ap.parse_args()
    proof = {
        "Schema":"adPEAS-RU.2.11.0.MIG8a.1",
        "Scope":"HTML display literals only; original licensing and AD audit untouched",
        "JsonExportModified":False,"LicenseValidationModified":False,
        "ScoringLogicModified":False,"FindingDefinitionsModified":False,
        "OriginalADDataModified":False,"RealADTestPerformed":False,
        "ProductionReady":False
    }
    patch_report(o.candidate,proof)
    patch_js(o.candidate,proof)
    o.report.parent.mkdir(parents=True,exist_ok=True)
    save(o.report,json.dumps(proof,ensure_ascii=False,indent=2)+"\n")
    print("MIG8a PASS: visible priority UI and legal notice translated at source, original rights intact")

if __name__=="__main__":main()
