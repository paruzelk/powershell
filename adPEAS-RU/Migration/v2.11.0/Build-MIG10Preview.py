#!/usr/bin/env python3
"""MIG10: translate presentation-only English in extended attribute controls."""
import argparse
import json
from pathlib import Path
ENC = "utf-8-sig"

def load(path):
    return path.read_text(encoding=ENC)

def save(path, content):
    path.write_text(content, encoding=ENC)

def once(text, old, new, label, count=1):
    n = text.count(old)
    if n != count:
        raise ValueError("MIG10 source witness " + label + ": expected " + str(count) + ", observed " + str(n))
    return text.replace(old, new)

def patch(candidate):
    proof = {
        "Schema": "adPEAS-RU.2.11.0.MIG10.1",
        "SourceVersion": "2.11.0",
        "Scope": "HTML display and accessibility strings",
        "ExtendedAttributesCountPreserved": True,
        "OriginalAdValuesPreserved": True,
        "OriginalAttributeKeysPreserved": True,
        "FindingDefinitionsModified": False,
        "ScoringModified": False,
        "JsonExportModified": False,
        "LicenseModified": False,
        "ProductionReady": False,
        "RealAdRuntimeVerifiedByCI": False
    }
    render = candidate / "src/modules/Core/Render-HtmlObject.ps1"
    s = load(render)
    s = once(s, "<span>Show $extendedCount more attribute(s)</span>",
             "<span>Показать дополнительные атрибуты: $extendedCount</span>",
             "PowerShell extended attribute count")
    save(render, s)

    script = candidate / "src/modules/Reporting/templates/report-scripts.js"
    s = load(script)
    first = s.index("function toggleExtendedAttrs(objectId) {")
    last = s.index("// Toggle individual object card", first)
    segment = s[first:last]
    segment = once(segment, ".replace('Show', 'Hide')",
       ".replace('Показать дополнительные атрибуты:', 'Скрыть дополнительные атрибуты:')",
       "expand additional attributes")
    segment = once(segment, ".replace('Hide', 'Show')",
       ".replace('Скрыть дополнительные атрибуты:', 'Показать дополнительные атрибуты:')",
       "collapse additional attributes")
    s = s[:first] + segment + s[last:]
    s = once(s, "theme === 'dark' ? 'Light' : 'Dark'",
       "theme === 'dark' ? 'Светлая' : 'Тёмная'", "dynamic theme label")
    save(script, s)

    template = candidate / "src/modules/Reporting/templates/report-template.html"
    s = load(template)
    s = once(s, 'alt="adPEAS Logo"', 'alt="Логотип adPEAS"', "image alternatives", count=2)
    s = once(s, 'id="themeLabel">Light', 'id="themeLabel">Светлая', "initial theme label")
    save(template, s)
    proof["ExtendedCaptionReplacements"] = 1
    proof["ExtendedToggleBranchesLocalized"] = 2
    proof["ImageAltTextLocalized"] = 2
    proof["ThemeLabelsLocalized"] = 2
    return proof

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    proof = patch(args.candidate)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    save(args.report, json.dumps(proof, ensure_ascii=False, indent=2) + "\n")
    print("MIG10 PASS: exact-source Russian extended attribute UI and accessibility text")

if __name__ == "__main__":
    main()
