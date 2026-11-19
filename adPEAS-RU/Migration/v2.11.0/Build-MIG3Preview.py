#!/usr/bin/env python3
"""MIG3 - complete 16 new findings and 5 changed finding texts, preserve upstream semantics.

Apply after MIG1 and MIG2. Validate English witnesses against pinned adPEAS 2.11.0.
Only modifies report rendering resources: no finding rules, risk, triggers, commands, or APIs.
"""
import argparse
import json
import re
import runpy
from pathlib import Path

HERE = Path(__file__).resolve().parent
m2 = runpy.run_path(str(HERE / "Build-MIG2Preview.py"))
blocks = m2["blocks"]
FIND = m2["FIND"]
read_json = m2["read_json"]
js_catalog = m2["js_catalog"]

NEW_FILES = ("MIG3-NewFullTechnical-01.ru-RU.json", "MIG3-NewFullTechnical-02.ru-RU.json")
CHANGED = "MIG3-ChangedFields.ru-RU.json"
FIELDS = (("Impact", "impact"), ("Attack", "attack"), ("Remediation", "remediation"))

def source_description(block):
    match = re.search(r'^ {8}Description[ \t]*=[ \t]*"(.*)"[ \t]*$', block, re.M)
    if not match:
        raise ValueError("Missing canonical English Description")
    return match.group(1)

def source_array(block, field):
    match = re.search(r'^ {8}' + re.escape(field) + r'[ \t]*=[ \t]*@\(([^\r\n]*)', block, re.M)
    if match is None:
        return False, []
    if match.group(1).strip() == ")":
        return True, []
    lines = block[match.end():].splitlines()
    result = []
    for line in lines:
        if re.fullmatch(r' {8}\)[ \t]*', line):
            return True, result
        item = line.strip()
        if not item:
            continue
        if not (item.startswith('"') and item.endswith('"')):
            raise ValueError("Unexpected non-string " + field + " source item: " + item[:120])
        result.append(item[1:-1])
    raise ValueError("Unclosed source " + field)

def validate_row(id_, source, row, require_all):
    if row.get("SourceEnglishDescription") is not None:
        if row["SourceEnglishDescription"] != source_description(source):
            raise ValueError("Description witness mismatch for " + id_)
        if not isinstance(row.get("description"), str) or not re.search("[А-Яа-яЁё]", row["description"]):
            raise ValueError("Missing Russian Description for " + id_)
    elif require_all:
        raise ValueError("New finding missing English Description witness " + id_)
    for en, ru in FIELDS:
        if require_all or ru in row:
            present, values = source_array(source, en)
            if row.get("SourceEnglish" + en) != values:
                raise ValueError(id_ + ": English " + en + " items have changed")
            if row.get("SourceEnglish" + en + "Count") != len(values):
                raise ValueError(id_ + ": English " + en + " count mismatch")
            if "SourceEnglish" + en + "Declared" in row and row["SourceEnglish" + en + "Declared"] != present:
                raise ValueError(id_ + ": English " + en + " declared-state mismatch")
            translated = row.get(ru)
            if not isinstance(translated, list) or len(translated) != len(values):
                raise ValueError(id_ + ": RU " + ru + " count mismatch")
            if any(not isinstance(x, str) or not re.search("[А-Яа-яЁё]", x) for x in translated):
                raise ValueError(id_ + ": RU " + ru + " contains an empty or untranslated line")

def read_verified_catalogs(source):
    merged = {}
    for name in NEW_FILES:
        data = read_json(HERE / name)
        if data.get("UpstreamCommit") != "477696f48d6b486be5d9a99b598f72e3ccfcc0c0":
            raise ValueError("Unexpected upstream commit " + name)
        for id_, row in data["Translations"].items():
            if id_ in merged:
                raise ValueError("Duplicate new finding " + id_)
            if id_ not in source:
                raise ValueError("Unknown new finding " + id_)
            validate_row(id_, source[id_], row, True)
            merged[id_] = row
    changed = read_json(HERE / CHANGED)
    if changed["UpstreamCommit"] != "477696f48d6b486be5d9a99b598f72e3ccfcc0c0":
        raise ValueError("Changed field source tag mismatch")
    for id_, row in changed["Translations"].items():
        if id_ not in source or id_ in merged:
            raise ValueError("Unknown changed finding " + id_)
        validate_row(id_, source[id_], row, False)
    return merged, changed["Translations"]

def extract_catalog(js):
    pattern = r'(?m)^        const ruMIG2Technical = ([^\r\n]+);[ \t]*$'
    matches = list(re.finditer(pattern, js))
    if len(matches) != 1:
        raise ValueError("MIG2 technical catalog declaration count != 1")
    return matches[0], json.loads(matches[0].group(1))

def replace_exact_one(source, before, after, scope):
    count = source.count(before)
    if count != 1:
        raise ValueError("MIG3 missing/duplicate UI anchor " + scope + ": " + repr(before) + " (count " + str(count) + ")")
    return source.replace(before, after, 1)

def patch_js(js, tech):
    original = js
    title = re.search(r'(?m)^        const ruMIG2Technical = ([^\r\n]+);[ \t]*$', js)
    match, _old = extract_catalog(js)
    js = js[:match.start()] + "        const ruMIG2Technical = " + js_catalog(tech) + ";" + js[match.end():]
    start = js.index("function buildTooltipHtml(finding, findingId, actualSeverity) {")
    end = js.index("        function escapeHtml(", start)
    block = js[start:end]
    mappings = {
        "> Description\n": "> Описание\n",
        "> Impact\n": "> Последствия\n",
        "isSecure ? 'Blocked Attack Vectors' : 'Attack Steps'": "isSecure ? 'Предотвращаемые атаки' : 'Этапы атаки'",
        "isSecureConfig ? 'Best Practices' : 'Remediation'": "isSecureConfig ? 'Рекомендации' : 'Устранение'",
        "> Quick Fix Commands": "> Команды исправления",
    }
    for before, after in mappings.items():
        if before in block:
            block = replace_exact_one(block, before, after, "finding tooltip")
    for original_label, russian_label in (("> References", "> Источники"), ("> Tools", "> Инструменты")):
        block = block.replace(original_label, russian_label)
    for en, ru in (("'FINDING'", "'НАРУШЕНИЕ'"), ("'HINT'", "'ПРЕДУПРЕЖДЕНИЕ'"),
                    ("'NOTE'", "'СВЕДЕНИЯ'"), ("'SECURE'", "'БЕЗОПАСНО'")):
        # risk label only; risk classes and risk IDs are not changed.
        if block.count("label: " + en) != 1:
            raise ValueError("Risk display label drift " + en)
        block = block.replace("label: " + en, "label: " + ru, 1)
    js = js[:start] + block + js[end:]
    start = js.index("function buildCheckTooltipHtml(check, checkTitle, cardSeverity) {")
    end = js.index("        // CHECKBOX SYSTEM", start)
    block = js[start:end]
    for en, ru in (("About this Check", "Об этой проверке"),
                   ("Secure Configuration", "Безопасная конфигурация"),
                   ("Why It Matters", "Почему это важно"),
                   ("What We Check", "Что проверяется"),
                   ("Output Filtering", "Фильтрация результатов")):
        block = replace_exact_one(block, en, ru, "check tooltip")
    js = js[:start] + block + js[end:]
    if original == js:
        raise ValueError("MIG3 failed to patch JavaScript")
    return js

def patch_template(template, is_diff=False):
    html = template
    if html.count('<html lang="en"') != 1:
        raise ValueError("HTML locale anchor unexpected")
    html = html.replace('<html lang="en"', '<html lang="ru"', 1)
    shared = {
        ">Print / PDF<": ">Печать / PDF<",
        ">Generated<": ">Создан<",
        ">Time Zone<": ">Часовой пояс<",
        ">Version<": ">Версия<",
    }
    main_only = {
        "adPEAS Security Report - {{DOMAIN}}": "Аудит безопасности AD — {{DOMAIN}}",
        ">adPEAS Security Report<": ">Аудит безопасности Active Directory<",
        ">Security Report Summary<": ">Сводка аудита безопасности<",
        ">Skip to Top Priority Actions<": ">К первоочередным действиям<",
        ">Skip to Findings<": ">К находкам<",
        ">Skip to Search<": ">К поиску<",
        ">Findings by Class<": ">Результаты по категориям<",
        ">Expand All<": ">Развернуть всё<",
        ">Collapse All<": ">Свернуть всё<",
        ">Hide completed<": ">Скрыть выполненные<",
        ">Domain Controller<": ">Контроллер домена<",
        ">Domain<": ">Домен<",
        ">User<": ">Пользователь<",
        ">Search findings<": ">Поиск результатов<",
        ">Finding<": ">Нарушение<",
        ">Hint<": ">Предупреждение<",
        ">Note<": ">Сведения<",
        ">Secure<": ">Безопасно<",
        "&#63; Help<": "&#63; Справка<",
    }
    diff_only = {
        "adPEAS Comparison Report - {{DOMAIN}}": "Сравнение аудитов adPEAS — {{DOMAIN}}",
        ">Comparison Report<": ">Сравнение аудитов<",
        ">New<": ">Новые<",
        ">Remediated<": ">Устранены<",
        ">Changed<": ">Изменились<",
        ">Unchanged<": ">Без изменений<",
        ">Baseline<": ">Исходный аудит<",
        ">Current<": ">Текущий аудит<",
        ">Compared<": ">Сравнено<",
    }
    for before, after in dict(shared, **(diff_only if is_diff else main_only)).items():
        if before in html:
            html = html.replace(before, after)
    return html

def main():
    p = argparse.ArgumentParser()
    for name in ("new", "candidate", "report"):
        p.add_argument("--" + name, required=True, type=Path)
    args = p.parse_args()
    script = args.candidate / "src/modules/Reporting/templates/report-scripts.js"
    findings = args.new / "src/modules/Core/adPEAS-FindingDefinitions.ps1"
    if not script.is_file() or not findings.is_file():
        raise ValueError("Expected MIG2 candidate and pinned upstream sources")
    canonical = blocks(findings.read_text(encoding="utf-8-sig"), FIND)
    if len(canonical) != 408:
        raise ValueError("Upstream 2.11 finding count changed")
    verified_new, verified_changed = read_verified_catalogs(canonical)
    if len(verified_new) != 16 or len(verified_changed) != 5:
        raise ValueError("MIG3 new/changed translation coverage incomplete")
    source = script.read_text(encoding="utf-8-sig")
    marker, current = extract_catalog(source)
    if set(current) != set(canonical):
        raise ValueError("MIG2 catalog does not contain all 408 canonical IDs")
    for key, row in verified_new.items():
        for field in ("description", "impact", "attack", "remediation"):
            current[key][field] = row[field]
    for key, row in verified_changed.items():
        for field in ("description", "impact", "attack", "remediation"):
            if field in row:
                current[key][field] = row[field]
    for id_, row in current.items():
        if not isinstance(row.get("description"), str) or not row["description"].strip():
            raise ValueError("Missing Russian Description " + id_)
        for field in ("impact", "attack", "remediation"):
            if not isinstance(row.get(field), list):
                raise ValueError("Missing Russian list " + id_ + ": " + field)
    script.write_text(patch_js(source, current), encoding="utf-8-sig")
    templates = args.candidate / "src/modules/Reporting/templates"
    html = templates / "report-template.html"
    diff = templates / "diff-template.html"
    html.write_text(patch_template(html.read_text(encoding="utf-8-sig")), encoding="utf-8-sig")
    diff.write_text(patch_template(diff.read_text(encoding="utf-8-sig"), True), encoding="utf-8-sig")
    report = {
        "Schema": "adPEAS-RU.2.11.0.MIG3.1",
        "Canonical": "61106960/adPEAS@477696f48d6b486be5d9a99b598f72e3ccfcc0c0",
        "FindingIds": len(current), "FullRussianDescriptionCount": sum(bool(r.get("description")) for r in current.values()),
        "FullRussianAttackImpactRemediationLists": 408,
        "NewFullyTranslatedFindingIds": sorted(verified_new),
        "UpdatedFindingIds": {k: [x for x in ("description", "impact", "attack", "remediation") if x in row]
                              for k, row in verified_changed.items()},
        "ChangedEnglishFieldsReconciled": sum(len([x for x in ("description", "impact", "attack", "remediation") if x in row])
                                              for row in verified_changed.values()),
        "ProductionReady": False,
        "ADLiveTestPerformed": False,
        "Outstanding": ["Console and additional dynamic 2.11 UI messages", "Full CLI/README 2.11 parity review",
                        "Real HTML findings from domain scan", "Full Windows PowerShell/Pester regression suite"]
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8-sig")
    print("MIG3 PASS: 408 finding titles/descriptions/field arrays; 16 new fully translated; "
          "5 changed finding definitions reviewed with original English witnesses")
if __name__ == "__main__":
    main()
