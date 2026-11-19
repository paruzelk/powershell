#!/usr/bin/env python3
"""adPEAS-RU MIG1: gated, presentation-only port of title catalogs to 2.11.0."""
import argparse
import json
import re
import shutil
from pathlib import Path

FIND = re.compile(r"^    '([A-Z][A-Z0-9_]*)'\s*=\s*@\{", re.M)
OBJ = re.compile(r"^    '([^']+)'\s*=\s*@\{", re.M)

def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))

def blocks(text, pattern):
    matches = list(pattern.finditer(text))
    return {m.group(1): text[m.start():matches[i + 1].start() if i + 1 < len(matches) else len(text)]
            for i, m in enumerate(matches)}

def field(block, name):
    hit = re.search(r'^[ \t]{8}' + re.escape(name) + r'[ \t]*=[ \t]*"([^"\r\n]*)"[ \t]*$', block, re.M)
    if hit is None:
        raise ValueError("Missing canonical field: " + name)
    return hit.group(1)

def quoted(s):
    backtick = chr(96)
    return '"' + s.replace(backtick, backtick * 2).replace('"', backtick + '"').replace('$', backtick + '$') + '"'

def replace_field(block, name, old, new):
    pattern = re.compile(r'^([ \t]{8}' + re.escape(name) + r'[ \t]*=[ \t]*)"([^"\r\n]*)"([ \t]*)$', re.M)
    found = list(pattern.finditer(block))
    if len(found) != 1 or found[0].group(2) != old:
        raise ValueError("Source drift: " + name)
    return pattern.sub(lambda m: m.group(1) + quoted(new) + m.group(3), block, count=1)

def replace_blocks(text, changes, pattern):
    matches = list(pattern.finditer(text))
    for i in reversed(range(len(matches))):
        m = matches[i]
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        text = text[:m.start()] + changes[m.group(1)] + text[end:]
    return text

def main():
    parser = argparse.ArgumentParser()
    for name in ("old", "new", "ru", "candidate", "report"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    path_find = "src/modules/Core/adPEAS-FindingDefinitions.ps1"
    path_obj = "src/modules/Core/adPEAS-ObjectTypes.ps1"
    old_find = blocks((args.old / path_find).read_text(encoding="utf-8-sig"), FIND)
    new_find = blocks((args.new / path_find).read_text(encoding="utf-8-sig"), FIND)
    old_obj = blocks((args.old / path_obj).read_text(encoding="utf-8-sig"), OBJ)
    obj_source = (args.new / path_obj).read_text(encoding="utf-8-sig")
    new_obj = blocks(obj_source, OBJ)
    added = sorted(set(new_find) - set(old_find))
    removed = sorted(set(old_find) - set(new_find))
    modified = sorted(i for i in old_find if i in new_find and
                      re.sub(r"\s+", " ", old_find[i]).strip() != re.sub(r"\s+", " ", new_find[i]).strip())
    new_objects = sorted(set(new_obj) - set(old_obj))
    expected = (len(old_find), len(new_find), len(old_obj), len(new_obj),
                len(added), len(removed), len(modified), len(new_objects))
    if expected != (392, 408, 125, 128, 16, 0, 63, 3):
        raise ValueError("Upstream catalog drift: " + str(expected))
    locale = args.ru / "Localization"
    old_titles = {}
    for item in ("01", "02", "03", "04"):
        data = read_json(locale / ("Findings-Titles-" + item + ".ru-RU.json"))
        for key, title in data.items():
            if key in old_titles:
                raise ValueError("Duplicate old FindingId: " + key)
            old_titles[key] = title
    new_titles = read_json(args.ru / "Migration/v2.11.0/NewFindingTitles.ru-RU.json")["Translations"]
    new_obj_ru = read_json(args.ru / "Migration/v2.11.0/NewObjectTypes.ru-RU.json")["Translations"]
    old_obj_ru = read_json(locale / "ObjectTypes.ru-RU.json")["translations"]
    if (set(old_titles) != set(old_find) or set(new_titles) != set(added) or
            set(old_obj_ru) != set(old_obj) or set(new_obj_ru) != set(new_objects)):
        raise ValueError("RU dictionary vs upstream ID mismatch")
    titles = {}
    title_changed = []
    for key in old_find:
        before = field(old_find[key], "Title")
        after = field(new_find[key], "Title")
        if before == after:
            if after in titles and titles[after] != old_titles[key]:
                raise ValueError("Title collision: " + after)
            titles[after] = old_titles[key]
        else:
            title_changed.append(key)
    for key, row in new_titles.items():
        en = field(new_find[key], "Title")
        if en != row["EnglishTitle"] or field(new_find[key], "Risk") != row["RiskWitness"]:
            raise ValueError("New finding witness changed: " + key)
        titles[en] = row["RussianTitle"]
    # An existing finding changed its English title in 2.11; review it separately.
    changed_titles_ru = read_json(args.ru / "Migration/v2.11.0/ChangedFindingTitles.ru-RU.json")["Translations"]
    if set(changed_titles_ru) != set(title_changed):
        raise ValueError("Modified English title(s) not fully reviewed")
    for key, row in changed_titles_ru.items():
        new_title = field(new_find[key], "Title")
        if new_title != row["EnglishTitle"]:
            raise ValueError("Changed finding title drift: " + key)
        titles[new_title] = row["RussianTitle"]
    if args.candidate.exists():
        raise ValueError("Candidate exists; refuse overwrite: " + str(args.candidate))
    shutil.copytree(args.new, args.candidate)
    updates = {}
    section_reused = 0
    section_review = 0
    for key, block in new_obj.items():
        patched = block
        if key in old_obj:
            for name in ("SectionTitle", "Summary"):
                if field(old_obj[key], name) == field(block, name):
                    patched = replace_field(patched, name, field(block, name), old_obj_ru[key][name])
                    section_reused += 1
                else:
                    section_review += 1
        else:
            row = new_obj_ru[key]
            for name in ("SectionTitle", "Summary", "WhyItMatters", "SecureMessage"):
                if name == "SectionTitle":
                    canonical = row["EnglishSectionTitle"]
                elif name == "Summary":
                    canonical = row["EnglishSummary"]
                else:
                    canonical = field(block, name)
                patched = replace_field(patched, name, canonical, row[name])
        updates[key] = patched
    output_obj = args.candidate / path_obj
    output_obj.write_text(replace_blocks(obj_source, updates, OBJ), encoding="utf-8-sig")
    script = args.candidate / "src/modules/Reporting/templates/report-scripts.js"
    js = script.read_text(encoding="utf-8-sig")
    marker = '        // Scoring context data for context-aware risk calculation'
    if js.count(marker) != 1:
        raise ValueError("JS marker drift")
    overlay = """
        // MIG1: display-only title translation, canonical finding metadata untouched.
        const ruMIG1Titles = __CAT__;
        document.addEventListener('DOMContentLoaded', function () {
            const root = document.querySelector('.report-content') || document.body;
            if (!root) return;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
                const p = node.parentElement;
                if (!p || p.closest('script,style,pre,code,textarea')) continue;
                const raw = node.nodeValue, key = raw.trim();
                if (!Object.prototype.hasOwnProperty.call(ruMIG1Titles, key)) continue;
                const start = raw.indexOf(key);
                node.nodeValue = raw.slice(0, start) + ruMIG1Titles[key] +
                                 raw.slice(start + key.length);
            }
        });

""".replace("__CAT__", json.dumps(titles, ensure_ascii=False, sort_keys=True))
    script.write_text(js.replace(marker, overlay + marker, 1), encoding="utf-8-sig")
    for p in args.candidate.rglob("*"):
        if p.is_file() and p.suffix.lower() in (".ps1", ".psm1", ".psd1"):
            p.write_text(p.read_text(encoding="utf-8-sig"), encoding="utf-8-sig")
    report = {
        "Schema": "adPEAS-RU.MIG1.2.11.0.1",
        "Original29": "61106960/adPEAS@ee0c9c47cddcaddae74ef3b8a43f9fef1bf2d082",
        "Original211": "61106960/adPEAS@477696f48d6b486be5d9a99b598f72e3ccfcc0c0",
        "RUBase": "paruzelk/powershell@778d03e13c98bd357fe369b7300b1d59801e3f1e",
        "NewIds": added, "RemovedIds": removed, "ChangedIdsReview": modified,
        "ChangedEnglishTitlesReview": title_changed,
        "OldTitlesReused": len(titles) - 16 - len(changed_titles_ru), "NewTitlesTranslated": 16, "ChangedTitlesTranslated": len(changed_titles_ru),
        "NewObjectTypesTranslated": new_objects,
        "OldObjectFieldsReused": section_reused, "OldObjectFieldsReview": section_review,
        "Scope": "PREVIEW ONLY: finding titles, check sections, not full technical translations",
        "SafeForProduction": False, "ADRunPerformed": False
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8-sig")
    print("MIG1 PASS: 408 findings, 16 new titles, 1 reviewed changed title, " + str(len(titles) - 16 - len(changed_titles_ru)) +
          " reused titles, " + str(len(modified)) + " altered definitions to review")
if __name__ == "__main__":
    main()
