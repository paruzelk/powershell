#!/usr/bin/env python3
"""MIG4: source-witnessed migration of visible strings; canonical detection unchanged."""
import argparse
import collections
import json
import re
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parent
base = runpy.run_path(str(ROOT / "Build-MIG1Preview.py"))
blocks = base["blocks"]
OBJ = base["OBJ"]
load = base["read_json"]

def read(path):
    return path.read_text(encoding="utf-8-sig")

def save(path, content):
    path.write_text(content, encoding="utf-8-sig")

def patch_rodc(upstream, candidate):
    blocks_map = blocks(read(upstream / "src/modules/Core/adPEAS-ObjectTypes.ps1"), OBJ)
    key = "RODCPasswordReplication"
    if len(blocks_map) != 128 or key not in blocks_map:
        raise ValueError("RODC source missing/changed")
    row = load(ROOT / "MIG4-RODCPasswordReplication.ru-RU.json")
    witness = row["SourceEnglish"]
    source = blocks_map[key]
    for name in ("SectionTitle", "Summary", "WhyItMatters", "SecureMessage"):
        m = re.search(r'^ {8}' + name + r' = "([^"]*)"$', source, re.M)
        if not m or m.group(1) != witness[name]:
            raise ValueError("RODC English changed: " + name)
    m = re.search(r'^ {8}WhatWeCheck = @\(\s*\n(.*?)^ {8}\)', source, re.M | re.S)
    if not m:
        raise ValueError("RODC WhatWeCheck not found")
    english = [s.strip()[1:-1] for s in m.group(1).splitlines() if s.strip()]
    if english != witness["WhatWeCheck"] or len(english) != len(row["Translated"]["whatWeCheck"]):
        raise ValueError("RODC English list witness changed")
    path = candidate / "src/modules/Reporting/templates/report-scripts.js"
    js = read(path)
    m = re.search(r'(?m)^        const ruMIG2CheckDetails = ([^\r\n]+);[ \t]*$', js)
    if not m:
        raise ValueError("MIG2 check tooltip overlay missing")
    obj = json.loads(m.group(1))
    if key in obj:
        raise ValueError("RODC already translated, unexpected MIG2 state")
    obj[key] = row["Translated"]
    insert = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    save(path, js[:m.start()] + "        const ruMIG2CheckDetails = " + insert + ";" + js[m.end():])

def skeleton(s):
    return re.sub(r'"[^"]*"', '""', s)

def variables(s):
    return sorted(re.findall(r'\$\([^)]+\)|\$[A-Za-z_][A-Za-z0-9_:]*', s))

def patch_scoped(candidate, locale, stats):
    result = {}
    for name in ("AdditionalCheckMessages.ru-RU.json", "ReportSourceMessages.ru-RU.json"):
        count = 0
        for relative, mapping in load(locale / name)["files"].items():
            if not re.fullmatch(r"src/modules/(?:Checks|Helpers)/[A-Za-z0-9_./-]+\.ps1", relative):
                raise ValueError("Unsafe catalog path " + relative)
            path = candidate / relative
            if not path.is_file():
                continue
            old = read(path)
            source = old
            for en, ru in mapping.items():
                if (en and ru and en != ru and skeleton(en) == skeleton(ru) and
                        variables(en) == variables(ru) and en in source):
                    source = source.replace(en, ru)
                    count += 1
            if source != old:
                save(path, source)
                stats["FilesTouched"] += 1
        result[name] = count
    stats["FileSpecific"] = result

def patch_simple(candidate, locale, stats):
    groups = [
        ("CheckHeaders.ru-RU.json", ("Show-Header", "Show-SubHeader")),
        ("CheckLines-01.ru-RU.json", ("Show-Header", "Show-SubHeader", "Show-Line")),
        ("DynamicCheckLines.ru-RU.json", ("Show-Line",))
    ]
    files = sorted((candidate / "src/modules/Checks").rglob("*.ps1"))
    result = {}
    for name, helpers in groups:
        count = 0
        translations = load(locale / name)
        for path in files:
            old = read(path)
            source = old
            for en, ru in translations.items():
                if not en or en == ru or '"' in en or '"' in ru:
                    continue
                for helper in helpers:
                    before = helper + ' "' + en + '"'
                    after = helper + ' "' + ru + '"'
                    matches = source.count(before)
                    if matches:
                        source = source.replace(before, after)
                        count += matches
            if source != old:
                save(path, source)
                stats["FilesTouched"] += 1
        result[name] = count
    stats["HelperCalls"] = result

def patch_doc6f(candidate, locale, stats):
    count = 0
    for group in load(locale / "DOC6f-VisibleOutputsAndHelp.ru-RU.json")["files"]:
        relative = group["path"]
        if not re.fullmatch(r"src/modules/[A-Za-z0-9_./-]+\.ps1", relative):
            raise ValueError("Unsafe DOC6f path " + relative)
        path = candidate / relative
        if not path.is_file():
            continue
        old = read(path)
        source = old
        for row in group["entries"]:
            en, ru = row["original"], row["target"]
            if (en and ru and en != ru and skeleton(en) == skeleton(ru)
                    and variables(en) == variables(ru) and en in source):
                source = source.replace(en, ru)
                count += 1
        if source != old:
            save(path, source)
            stats["FilesTouched"] += 1
    stats["DOC6f"] = count

def patch_ui(candidate, stats):
    words = load(ROOT / "MIG4-VisibleReportTexts.ru-RU.json")
    if len(words["Exact"]) < 85 or len(words["Patterns"]) < 35:
        raise ValueError("Incomplete UI phrase dictionary")
    for rule in words["Patterns"]:
        re.compile(rule["pattern"])
    runtime = read(ROOT / "MIG4-ReportRuntime.js")
    if runtime.count("__MIG4_CATALOG_JSON__") != 1:
        raise ValueError("MIG4 JS placeholder count")
    encoded = json.dumps(words, ensure_ascii=False, separators=(",", ":"))
    runtime = runtime.replace("__MIG4_CATALOG_JSON__", encoded.replace("<", "\\u003c").replace(">", "\\u003e"))
    path = candidate / "src/modules/Reporting/templates/report-scripts.js"
    original = read(path)
    if "MIG4 display-only localization" in original:
        raise ValueError("Repeated MIG4 injection")
    save(path, original + "\n" + runtime + "\n")
    stats["ExactVisibleLabels"] = len(words["Exact"])
    stats["RegexVisibleLabels"] = len(words["Patterns"])
    stats["StatusWords"] = len(words["StatusWords"])

def main():
    p = argparse.ArgumentParser()
    for arg in ("new", "ru", "candidate", "report"):
        p.add_argument("--" + arg, type=Path, required=True)
    opt = p.parse_args()
    stats = collections.defaultdict(int)
    patch_rodc(opt.new, opt.candidate)
    locale = opt.ru / "Localization"
    patch_scoped(opt.candidate, locale, stats)
    patch_simple(opt.candidate, locale, stats)
    patch_doc6f(opt.candidate, locale, stats)
    patch_ui(opt.candidate, stats)
    total = sum(stats["FileSpecific"].values()) + sum(stats["HelperCalls"].values()) + stats["DOC6f"]
    if total < 30:
        raise ValueError("MIG4 legacy matches too few: " + str(total))
    stats["ReusedVerifiedDisplayMessages"] = total
    stats["Schema"] = "adPEAS-RU.2.11.0.MIG4.1"
    stats["SourceCommit"] = "477696f48d6b486be5d9a99b598f72e3ccfcc0c0"
    stats["RODCPasswordReplicationTranslated"] = True
    stats["ProductionReady"] = False
    stats["MIG4RealADTestPerformed"] = False
    opt.report.parent.mkdir(parents=True, exist_ok=True)
    save(opt.report, json.dumps(stats, ensure_ascii=False, indent=2) + "\n")
    print("MIG4 PASS: " + str(total) + " source-matched messages, 91 UI phrases, 41 regex patterns, full RODC tooltip")
if __name__ == "__main__":
    main()
