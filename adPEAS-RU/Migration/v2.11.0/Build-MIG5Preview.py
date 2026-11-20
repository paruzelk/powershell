#!/usr/bin/env python3
"""MIG5: Report-backed source-side RU presentation, separate from AD detection."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAM = "477696f48d6b486be5d9a99b598f72e3ccfcc0c0"

def read(path):
    return path.read_text(encoding="utf-8-sig")

def save(path, source):
    path.write_text(source, encoding="utf-8-sig")

def replace_one(source, old, new, name):
    n = source.count(old)
    if n != 1:
        raise ValueError("MIG5 canonical display anchor " + name + " count=" + str(n))
    return source.replace(old, new, 1)

def ps_str(value):
    if "\n" in value or "\r" in value:
        raise ValueError("Newline in display value")
    return "'" + value.replace("'", "''") + "'"

def ps_table(values):
    lines = ["    $ru = @{"]
    for en, ru in values.items():
        lines.append("        " + ps_str(en) + " = " + ps_str(ru))
    lines.append("    }")
    return "\n".join(lines)

def section_function(d):
    return r"""# MIG5: translate only visual section titles. Numbering is preserved.
function ConvertTo-RuReportSectionTitle {
    param([string]$Title)
""" + ps_table(d["SectionTitles"]) + """
    $prefix = ''
    $text = $Title
    if ($Title -match '^(\[\d+/\d+\]\s*)(.*)$') {
        $prefix = $Matches[1]
        $text = $Matches[2]
    }
    if ($ru.ContainsKey($text)) { return $prefix + $ru[$text] }
    return $Title
}

"""

def object_function(d):
    return r"""# MIG5: translate only a renderer-produced label, never the object name.
function ConvertTo-RuReportObjectTitle {
    param([string]$Title)
""" + ps_table(d["ObjectCardExact"]) + """
    if ($ru.ContainsKey($Title)) { return $ru[$Title] }
    if ($Title -match '^Domain Controllers \((\d+)\)$') {
        return 'Контроллеры домена (' + $Matches[1] + ')'
    }
""" + "\n".join(
        "    if ($Title.StartsWith(" + ps_str(en) +
        ", [System.StringComparison]::Ordinal)) { return " + ps_str(ru) +
        " + $Title.Substring(" + str(len(en)) + ") }"
        for en, ru in d["ObjectCardPrefixes"].items()
    ) + """
    return $Title
}

"""

def patch_report(candidate, upstream, glossary, rodc, report):
    target = candidate / "src/modules/Reporting/Export-HTMLReport.ps1"
    enfile = upstream / "src/modules/Reporting/Export-HTMLReport.ps1"
    original = read(target)
    if original != read(enfile):
        raise ValueError("Reporting module was previously changed: require new source reconciliation")
    txt = original
    txt = replace_one(txt, "function Build-NavigationHtml {",
                      section_function(glossary) + object_function(glossary) +
                      "function Build-NavigationHtml {", "report UI helpers")
    txt = replace_one(txt,
        "$catNameEncoded = ConvertTo-HtmlEncode $catName",
        ps_table(glossary["SidebarCategories"]) +
        "\n        $visibleCategory = if ($ru.ContainsKey($catName)) { $ru[$catName] } else { $catName }\n" +
        "        $catNameEncoded = ConvertTo-HtmlEncode $visibleCategory",
        "rendered category label")
    txt = replace_one(txt,
        '<div class="sidebar-title">Categories</div>',
        '<div class="sidebar-title">Категории</div>', "sidebar title")
    txt = replace_one(txt, "        All Categories", "        Все категории", "sidebar all label")
    txt = replace_one(txt,
        "$(ConvertTo-HtmlEncode $group.Header)",
        "$(ConvertTo-HtmlEncode (ConvertTo-RuReportSectionTitle -Title $group.Header))",
        "visible section heading")
    txt = replace_one(txt,
        '$objectCount item(s)</span>', 'Объектов: $objectCount</span>', "count plural")
    txt = replace_one(txt,
        '1 result</span>', 'Результатов: 1</span>', "count singular")
    txt = replace_one(txt, "(all times in this report)", "(все отметки времени в отчёте)", "timezone label")
    txt = replace_one(txt,
        "<span>&#9654;</span> Expand All</button>",
        "<span>&#9654;</span> Развернуть всё</button>", "object expand label")
    txt = replace_one(txt,
        "$objectName = Get-ObjectCardTitle -Object $Object",
        "$objectName = ConvertTo-RuReportObjectTitle -Title (Get-ObjectCardTitle -Object $Object)",
        "object card visible title")

    original_rodc = rodc["SourceEnglish"]["Summary"]
    translated_rodc = rodc["Translated"]["summary"]
    if not original_rodc or not translated_rodc:
        raise ValueError("RODC source/translation absent")
    anchor = "    # XSS Protection: Encode title for both display and data attribute"
    guard = ("    # MIG5: only the RODC visible HTML subtitle; source definitions stay canonical.\n" +
             "    if ($resolvedObjectType -eq 'RODCPasswordReplication' -and $subtitle -ceq " +
             ps_str(original_rodc) + ") {\n" +
             "        $subtitle = " + ps_str(translated_rodc) + "\n" +
             "    }\n\n")
    txt = replace_one(txt, anchor, guard + anchor, "RODC HTML summary")
    save(target, txt)
    report["ReportSourceLabelsLocalized"] = True
    report["ReportSourcePowerShellStringsInserted"] = len(glossary["SectionTitles"]) + len(glossary["SidebarCategories"]) + len(glossary["ObjectCardExact"]) + len(glossary["ObjectCardPrefixes"]) + 8

def patch_template(candidate, report):
    path = candidate / "src/modules/Reporting/templates/report-template.html"
    s = read(path)
    translations = {
        "                All <span class=\"count\" aria-label=\"total findings\">":
            "                Все <span class=\"count\" aria-label=\"всего результатов\">",
        "                Finding <span class=\"count\" aria-label=\"critical findings\">":
            "                Нарушения <span class=\"count\" aria-label=\"критические результаты\">",
        "                Hint <span class=\"count\" aria-label=\"hints\">":
            "                Предупреждения <span class=\"count\" aria-label=\"предупреждения\">",
        "                Note <span class=\"count\" aria-label=\"notes\">":
            "                Сведения <span class=\"count\" aria-label=\"сведения\">",
        "                Secure <span class=\"count\" aria-label=\"secure items\">":
            "                Безопасно <span class=\"count\" aria-label=\"безопасные результаты\">",
        "Search findings... (press / to focus)":
            "Поиск результатов... (нажмите /)",
        "Type to filter findings by text content":
            "Введите текст для поиска среди результатов",
    }
    for old, new in translations.items():
        s = replace_one(s, old, new, "HTML static " + old[:45])
    save(path, s)
    report["TemplateStringsLocalized"] = len(translations)

def patch_last_line(candidate, glossary, report):
    row = glossary["SingleRemainingEnglishLine"]
    file = candidate / row["file"]
    original = read(file)
    before = 'Show-Line "' + row["english"] + '"'
    after = 'Show-Line "' + row["russian"] + '"'
    updated = replace_one(original, before, after, "untranslated deleted-objects note")
    save(file, updated)
    report["LastPureEnglishCheckLineTranslated"] = True

def test_candidate(candidate, report):
    source = read(candidate / "src/modules/Reporting/Export-HTMLReport.ps1")
    if "1 result</span>" in source or "$objectCount item(s)</span>" in source:
        raise ValueError("Report still outputs English count labels")
    if "ConvertTo-RuReportSectionTitle" not in source:
        raise ValueError("Missing section title translation function")
    if "ConvertTo-RuReportObjectTitle" not in source:
        raise ValueError("Missing object title translation function")
    if "Get-Ru" in source:
        raise ValueError("Unrecognized runtime localization helper")
    if "function ConvertTo-CategorySlug" not in source:
        raise ValueError("Category slug function unexpectedly missing")
    required_positive = ("ReportSourceLabelsLocalized", "LastPureEnglishCheckLineTranslated")
    for key in required_positive:
        if report.get(key) is not True:
            raise ValueError("MIG5 report translation gate " + key)
    if report.get("RealADTestPerformed") is not False or report.get("ProductionReady") is not False:
        raise ValueError("MIG5 preview safety status drift")

def main():
    ap = argparse.ArgumentParser()
    for k in ("new", "candidate", "report"):
        ap.add_argument("--" + k, required=True, type=Path)
    args = ap.parse_args()
    g = json.loads(read(ROOT / "MIG5-SourceSidePresentation.ru-RU.json"))
    rodc = json.loads(read(ROOT / "MIG4-RODCPasswordReplication.ru-RU.json"))
    if g["UpstreamCommit"] != UPSTREAM or rodc["UpstreamCommit"] != UPSTREAM:
        raise ValueError("Pinned source mismatch")
    if len(g["SectionTitles"]) != 9 or len(g["SidebarCategories"]) != 9:
        raise ValueError("Expected nine categories and nine section titles")
    result = {
        "Schema": "adPEAS-RU.2.11.0.MIG5.1",
        "OriginalCommit": UPSTREAM,
        "RealADTestPerformed": False,
        "ProductionReady": False,
        "FindingDefinitionsModified": False,
        "OriginalADDataModified": False
    }
    patch_report(args.candidate, args.new, g, rodc, result)
    patch_template(args.candidate, result)
    patch_last_line(args.candidate, g, result)
    test_candidate(args.candidate, result)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    save(args.report, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print("MIG5 PASS: source-side RU headings/categories/counts/object labels/RODC subtitle; no AD rule changes")
if __name__ == "__main__":
    main()
