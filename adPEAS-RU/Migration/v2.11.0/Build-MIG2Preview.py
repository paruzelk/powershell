#!/usr/bin/env python3
"""MIG2: reuse DOC6j Russian text only where canonical 2.11 English is unchanged.

Run AFTER Build-MIG1Preview.py. Original finding definitions and detection are not modified.
"""
import argparse
import json
import re
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parent
mig1 = runpy.run_path(str(ROOT / "Build-MIG1Preview.py"))
blocks = mig1["blocks"]
FIND = mig1["FIND"]
OBJ = mig1["OBJ"]
read_json = mig1["read_json"]

BASE_FILES = (
    "FullTechnical-01.ru-RU.json",
    "FullTechnical-02.ru-RU.json",
    "FullTechnical-Report-03.ru-RU.json",
    "FullTechnical-Report-04.ru-RU.json",
    "FullTechnical-Brief-05.ru-RU.json",
    "FullTechnical-Catalog-06a.ru-RU.json",
    "FullTechnical-Catalog-06b.ru-RU.json",
    "FullTechnical-Catalog-06c.ru-RU.json",
    "FullTechnical-Catalog-06d.ru-RU.json",
    "FullTechnical-Catalog-06e.ru-RU.json",
)

def field_source(block, name):
    match = re.search(r'(?m)^ {8}' + re.escape(name) + r'[ \t]*=', block)
    if not match:
        return None
    nextfield = re.search(r'(?m)^ {8}[A-Z][A-Za-z0-9_]*[ \t]*=', block[match.end():])
    end = match.end() + nextfield.start() if nextfield else len(block)
    return re.sub(r'\s+', ' ', block[match.start():end]).strip()

def identical(old, new, name):
    return field_source(old, name) == field_source(new, name)

def overlay_source_verified(entries, folder, mask, kinds, counts):
    for file in sorted(folder.glob(mask)):
        data = read_json(file)
        for key, row in data["translations"].items():
            if key not in entries:
                raise ValueError("Unknown 2.9 FindingId in " + file.name + ": " + key)
            for kind in kinds:
                if kind not in row:
                    continue
                steps = row[kind]
                if not isinstance(steps, list):
                    raise ValueError("Expected array in " + file.name)
                field_count = "sourceEnglishAttackStepCount" if kind == "attack" else ("sourceEnglish" + kind.capitalize() + "Count")
                if field_count in row and len(steps) != int(row[field_count]):
                    raise ValueError("Witness count mismatch: " + file.name + ": " + key)
                english = "sourceEnglishAttack" if kind == "attack" else "sourceEnglish" + kind.capitalize()
                if english in row and len(row[english]) != len(steps):
                    raise ValueError("Witness steps mismatch: " + file.name + ": " + key)
                entries[key][kind] = steps
                counts[kind] = counts.get(kind, 0) + 1

def make_technical(old, new, locale, old_ru):
    old_defs = blocks((old / "src/modules/Core/adPEAS-FindingDefinitions.ps1").read_text(encoding="utf-8-sig"), FIND)
    new_defs = blocks((new / "src/modules/Core/adPEAS-FindingDefinitions.ps1").read_text(encoding="utf-8-sig"), FIND)
    entries = {}
    for filename in BASE_FILES:
        for key, row in read_json(locale / filename)["translations"].items():
            if key in entries:
                raise ValueError("Duplicate FullTechnical: " + key)
            entries[key] = {field: row.get(field) for field in ("description", "impact", "attack", "remediation")}
    if set(entries) != set(old_defs) or len(entries) != 392 or len(new_defs) != 408:
        raise ValueError("Technical dictionaries do not cover original 392 IDs")
    witness_counts = {}
    overlay_source_verified(entries, locale, "SourceVerifiedCore-*.ru-RU.json",
                            ("impact", "remediation"), witness_counts)
    overlay_source_verified(entries, locale, "SourceVerifiedAttack-*.ru-RU.json",
                            ("attack",), witness_counts)
    parity = read_json(locale / "SourceFieldParity392.json")
    if parity["FindingCount"] != 392:
        raise ValueError("Old source parity count drift")
    expected = {r["FindingId"]: r for r in parity["Fields"]}
    if set(expected) != set(old_defs):
        raise ValueError("Old field count index incomplete")
    for key, row in entries.items():
        for name in ("impact", "attack", "remediation"):
            value = row[name]
            if not isinstance(value, list):
                raise ValueError("Missing field in full technical dictionary " + key + "." + name)
            count = expected[key][name.capitalize() + "RU"]
            if len(value) != count:
                raise ValueError("DOC6j EN/RU list parity mismatch in " + key + "." + name +
                                 ": expected " + str(count) + " got " + str(len(value)))
    result = {}
    transferred = {"description": 0, "impact": 0, "attack": 0, "remediation": 0}
    withheld = {}
    for key, row in entries.items():
        item = {}
        for name in ("description", "impact", "attack", "remediation"):
            value = row.get(name)
            if value is None:
                continue
            if not identical(old_defs[key], new_defs[key], name.capitalize()):
                withheld.setdefault(key, []).append(name)
                continue
            if name == "description" and not isinstance(value, str):
                raise ValueError("Invalid description: " + key)
            if name != "description" and not isinstance(value, list):
                raise ValueError("Invalid list: " + key)
            item[name] = value
            transferred[name] += 1
        result[key] = item
    new_titles = read_json(old_ru / "Migration/v2.11.0/NewFindingTitles.ru-RU.json")["Translations"]
    if set(new_titles) != (set(new_defs) - set(old_defs)):
        raise ValueError("New finding ID set mismatch")
    for key, value in new_titles.items():
        result[key] = {"description": value["RussianSummary"]}
    if len(result) != 408:
        raise ValueError("Invalid final technical coverage")
    return result, transferred, withheld, witness_counts

def make_checks(old, new, locale, old_ru):
    path = "src/modules/Core/adPEAS-ObjectTypes.ps1"
    old_defs = blocks((old / path).read_text(encoding="utf-8-sig"), OBJ)
    new_defs = blocks((new / path).read_text(encoding="utf-8-sig"), OBJ)
    old_details = {}
    for file in sorted(locale.glob("CheckTooltipDetails-*.ru-RU.json")):
        for key, row in read_json(file)["translations"].items():
            if key in old_details:
                raise ValueError("Duplicate CheckTooltipDetails: " + key)
            old_details[key] = row
    secure = {}
    for file in sorted(locale.glob("CheckSecureMessages-*.ru-RU.json")):
        for key, msg in read_json(file)["translations"].items():
            if key in secure:
                raise ValueError("Duplicate CheckSecureMessages: " + key)
            secure[key] = msg
    result = {}
    withheld = {}
    transferred = 0
    for key in old_defs:
        row = {}
        if key not in new_defs:
            raise ValueError("Old check removed: " + key)
        for name, oldname in (("whyItMatters", "WhyItMatters"), ("whatWeCheck", "WhatWeCheck")):
            if key in old_details and name in old_details[key]:
                if identical(old_defs[key], new_defs[key], oldname):
                    row[name] = old_details[key][name]
                    transferred += 1
                else:
                    withheld.setdefault(key, []).append(name)
        if key in secure:
            if identical(old_defs[key], new_defs[key], "SecureMessage"):
                row["secureMessage"] = secure[key]
                transferred += 1
            else:
                withheld.setdefault(key, []).append("secureMessage")
        if row:
            result[key] = row
    new_details = read_json(old_ru / "Migration/v2.11.0/NewObjectTypes.ru-RU.json")["Translations"]
    if set(new_details) != (set(new_defs) - set(old_defs)):
        raise ValueError("New check ID mismatch")
    for key, v in new_details.items():
        result[key] = {"whyItMatters": v["WhyItMatters"],
                       "whatWeCheck": v["WhatWeCheck"],
                       "secureMessage": v["SecureMessage"]}
    return result, transferred, withheld

def js_catalog(value):
    # Avoid breaking a script tag if a translation ever contains literal HTML.
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")

def patch_js(candidate, tech, checks):
    path = candidate / "src/modules/Reporting/templates/report-scripts.js"
    source = path.read_text(encoding="utf-8-sig")
    mark = "        // Scoring context data for context-aware risk calculation"
    if source.count(mark) != 1:
        raise ValueError("Missing MIG2 JS catalog anchor")
    defs = ("        // MIG2 UI strings only; keep canonical finding/check definitions unchanged.\n"
            "        const ruMIG2Technical = " + js_catalog(tech) + ";\n"
            "        const ruMIG2CheckDetails = " + js_catalog(checks) + ";\n\n")
    source = source.replace(mark, defs + mark, 1)
    begin = source.index("function buildTooltipHtml(finding, findingId, actualSeverity) {")
    end = source.index("        function escapeHtml(", begin)
    sub = source[begin:end]
    anchor = "function buildTooltipHtml(finding, findingId, actualSeverity) {"
    prelude = """
            // Localize only display values. No changes to risk, triggers or commands.
            const ru = ruMIG2Technical[findingId] || {};
            const displayTitle = ruMIG1Titles[finding.title] || finding.title;
            const displayDescription = typeof ru.description === 'string' ? ru.description : finding.description;
            const displayImpact = Array.isArray(ru.impact) ? ru.impact : finding.impact;
            const displayAttack = Array.isArray(ru.attack) ? ru.attack : finding.attack;
            const displayRemediation = Array.isArray(ru.remediation) ? ru.remediation : finding.remediation;
"""
    if sub.count(anchor) != 1:
        raise ValueError("Duplicate tooltip anchor")
    sub = sub.replace(anchor, anchor + prelude, 1)
    replacements = {
        "escapeHtml(finding.title)": "escapeHtml(displayTitle)",
        "escapeHtml(finding.description)": "escapeHtml(displayDescription)",
        "finding.impact": "displayImpact",
        "finding.attack": "displayAttack",
        "finding.remediation": "displayRemediation",
    }
    # Replace only the render body, not the prelude. Preserve commands, references and scoring.
    pre, body = sub.split(prelude, 1)
    for before, after in replacements.items():
        body = re.sub(r"\b" + re.escape(before) + r"\b", lambda _: after, body)
    if "finding.impact.map(" in body or "finding.attack.map(" in body:
        raise ValueError("Technical arrays not switched to display variables")
    sub = pre + prelude + body
    source = source[:begin] + sub + source[end:]
    check_anchor = "const check = checkDescriptions[objectType];"
    replacement = "const check = Object.assign({}, checkDescriptions[objectType], ruMIG2CheckDetails[objectType] || {});"
    if source.count(check_anchor) != 1:
        raise ValueError("Check tooltip lookup drift")
    source = source.replace(check_anchor, replacement, 1)
    if source.count("const ruMIG2Technical = ") != 1:
        raise ValueError("MIG2 script injection duplicate")
    path.write_text(source, encoding="utf-8-sig")

def main():
    parser = argparse.ArgumentParser()
    for arg in ("old", "new", "ru", "candidate", "report"):
        parser.add_argument("--" + arg, required=True, type=Path)
    args = parser.parse_args()
    if not args.candidate.is_dir():
        raise ValueError("MIG1 preview candidate missing")
    locale = args.ru / "Localization"
    technical, transferred, withheld, witnesses = make_technical(args.old, args.new, locale, args.ru)
    checks, check_fields, check_withheld = make_checks(args.old, args.new, locale, args.ru)
    patch_js(args.candidate, technical, checks)
    report = {
        "Schema": "adPEAS-RU.2.11.0.MIG2.1",
        "UpstreamCommit": "477696f48d6b486be5d9a99b598f72e3ccfcc0c0",
        "OldRUBaseline": "778d03e13c98bd357fe369b7300b1d59801e3f1e",
        "FindingCount": len(technical), "NewFindingDescriptions": 16,
        "OldTranslatedFieldsRetained": transferred,
        "OldTranslatedFieldsWithheldDueToSourceChange": withheld,
        "VerifiedSourceOverlayApplications": witnesses,
        "CheckTooltipsLocalized": len(checks),
        "CheckTooltipFieldsTransferred": check_fields,
        "CheckTooltipFieldsWithheld": check_withheld,
        "FindingsSourcePreserved": True, "ProductionReady": False,
        "Caveat": "16 new findings only have short RU descriptions; their Attack/Impact/Remediation remain original English. Other new 2.11 console/docs language is pending."
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8-sig")
    print("MIG2 PASS: 408 IDs; translated 2.9 technical fields transferred " + str(transferred) +
          "; original fields changed " + str(withheld) + "; check tooltips " + str(len(checks)))
if __name__ == "__main__":
    main()
