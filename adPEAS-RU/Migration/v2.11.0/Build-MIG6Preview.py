#!/usr/bin/env python3
"""MIG6: translate only report-rendered Show-Line text and scalar attribute displays."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAM = "477696f48d6b486be5d9a99b598f72e3ccfcc0c0"
ENC = "utf-8-sig"

def read(path):
    return path.read_text(encoding=ENC)

def save(path, content):
    path.write_text(content, encoding=ENC)

def exact_one(src, old, new, name):
    count = src.count(old)
    if count != 1:
        raise ValueError("MIG6 canonical anchor %s count %d" % (name, count))
    return src.replace(old, new, 1)

def psquote(value):
    if not isinstance(value, str) or "\r" in value or "\n" in value or "\0" in value:
        raise ValueError("MIG6 invalid display string")
    return "'" + value.replace("'", "''") + "'"

def make_table(values, name, indent="    "):
    entries = [indent + "$" + name + " = @{"]
    for en, ru in values.items():
        entries.append(indent + "    " + psquote(en) + " = " + psquote(ru))
    entries.append(indent + "}")
    return "\n".join(entries)

def make_rules(rules, name, indent="    "):
    entries = [indent + "$" + name + " = @("]
    for item in rules:
        entries.append(indent + "    @{ Pattern = " + psquote(item["pattern"]) +
                       "; Russian = " + psquote(item["ru"]) + " }")
    entries.append(indent + ")")
    return "\n".join(entries)

def fn(name, exact, rules):
    result = ["# MIG6: presentation-only translation; preserves original findings and AD data.",
              "function " + name + " {",
              "    param([AllowNull()][string]$Text)",
              "    if ([string]::IsNullOrEmpty($Text)) { return $Text }"]
    result.append(make_table(exact, "ruExact"))
    result.append("    if ($ruExact.ContainsKey($Text)) { return $ruExact[$Text] }")
    result.append(make_rules(rules, "ruPatterns"))
    result.extend([
        "    foreach ($rule in $ruPatterns) {",
        "        if ($Text -cmatch $rule.Pattern) {",
        "            return [regex]::Replace($Text, [string]$rule.Pattern, [string]$rule.Russian)",
        "        }",
        "    }",
        "    return $Text",
        "}",
        ""
    ])
    return "\n".join(result) + "\n"

# Generic synthetic examples; no user-domain findings or object names.
CASES = [
    "No non-privileged principal holds a delegated read of the BitLocker recovery passwords, but 3 privileged one(s) hold a right on them - use -IncludePrivileged to see them",
    "This account can read 4 deleted object(s) - as a member of Administrators",
    "None of the 4 deleted object(s) holds a credential in a free-text or password attribute",
    "5 further user right assignment(s) from 2 policies are not on the list of this check - not judged",
    "No principal beyond the expected ones can change the 5 privileged group(s) AdminSDHolder does not protect - 4 expected or privileged holder(s) hidden, use -IncludePrivileged to see them",
    "No principal beyond the expected ones can take over the 6 privileged account(s) read - 2 expected or privileged holder(s) hidden, use -IncludePrivileged to see them",
    "145 further registry value(s) from 6 policies are not on the list of this check - not judged",
    "Обнаружены настройки LDAP security configuration в групповых политиках: 1",
    "Обнаружены настройки null session configuration в групповых политиках: 2",
    "Группа Account Operators (no members) по умолчанию имеет права управления: all 5 группами, не защищёнными AdminSDHolder"
]
ATTR_CASES = [
    "7 characters", "24 passwords remembered", "10 hours (default)",
    "7 days (default)", "600 minutes (default)", "180 days",
    "10 minutes", "321 days (last changed: 2026-01-02)",
    "Not required (Windows default before Server 2025)",
    "Yes - in force on the domain controllers: LDAP signing",
    "None (signing is set on the DC OU only)"
]
def simulate(text, exact, rules):
    if text in exact:
        return exact[text]
    for row in rules:
        matched = re.fullmatch(row["pattern"], text)
        if matched:
            result = row["ru"]
            for idx in range(len(matched.groups()), 0, -1):
                result = result.replace("$" + str(idx), matched.group(idx))
            return result
    return text

def catalog_gates(cat):
    if cat["OriginalCommit"] != UPSTREAM:
        raise ValueError("Source commit drift")
    if len(cat["Exact"]) != 9 or len(cat["Patterns"]) != 10 or len(cat["Statuses"]) < 12 or len(cat["AttributePatterns"]) < 11:
        raise ValueError("Catalog coverage reduced")
    for group in ("Patterns", "AttributePatterns"):
        for row in cat[group]:
            re.compile(row["pattern"])
            if not row["pattern"].startswith("^") or not row["pattern"].endswith("$"):
                raise ValueError("Unanchored pattern " + row["pattern"])
    for i, sample in enumerate(CASES):
        if re.fullmatch(cat["Patterns"][i]["pattern"], sample) is None:
            raise ValueError("Generic line regex fixture %d does not match" % i)
        rendered = simulate(sample, cat["Exact"], cat["Patterns"])
        if rendered == sample or not re.search(r"[\u0400-\u04ff]", rendered):
            raise ValueError("Line regex fixture %d not localized" % i)
    for i, sample in enumerate(ATTR_CASES):
        if re.fullmatch(cat["AttributePatterns"][i]["pattern"], sample) is None:
            raise ValueError("Generic attribute regex fixture %d does not match" % i)
        if simulate(sample, cat["Statuses"], cat["AttributePatterns"]) == sample:
            raise ValueError("Attribute regex fixture %d not localized" % i)
    for en,ru in cat["Exact"].items():
        if en == ru or not re.search(r"[\u0400-\u04ff]", ru):
            raise ValueError("Untranslated exact phrase")
    for sentinel in ("S-1-5-21-0-0-0", "user@domain.example", "CN=Users,DC=example,DC=local",
                     "aes256-cts-hmac-sha1-96", "149b2f2e", "NT AUTHORITY\\Authenticated Users"):
        if simulate(sentinel, cat["Statuses"], cat["AttributePatterns"]) != sentinel:
            raise ValueError("Opaque AD value was changed in renderer")
    return {"ExactLines":len(cat["Exact"]), "PatternLines":len(cat["Patterns"]),
            "StatusWords":len(cat["Statuses"]), "AttributePatterns":len(cat["AttributePatterns"]),
            "SyntheticLineFixtures":len(CASES), "SyntheticAttributeFixtures":len(ATTR_CASES)}

def patch_export(candidate, cat):
    file = candidate / "src/modules/Reporting/Export-HTMLReport.ps1"
    src = read(file)
    if "function ConvertTo-RuReportSectionTitle {" not in src or "MIG6:" in src:
        raise ValueError("MIG5 report source missing or MIG6 applied twice")
    injected = fn("ConvertTo-RuReportLine", cat["Exact"], cat["Patterns"])
    injected += fn("ConvertTo-RuReportAttributeValue", cat["Statuses"], cat["AttributePatterns"])
    src = exact_one(src, "function ConvertTo-RuReportSectionTitle {",
                    injected + "function ConvertTo-RuReportSectionTitle {", "MIG5 existing report function")
    src = exact_one(src,
                    "$textHtml = ConvertTo-HtmlEncode $finding.Text",
                    "$textHtml = ConvertTo-HtmlEncode (ConvertTo-RuReportLine -Text $finding.Text)",
                    "Line HTML only")
    save(file, src)

def patch_attr(candidate, canonical):
    file = candidate / "src/modules/Core/Render-HtmlObject.ps1"
    if read(file) != read(canonical / "src/modules/Core/Render-HtmlObject.ps1"):
        raise ValueError("Rendering module unexpectedly differed from pinned upstream")
    source = read(file)
    anchor = "        'Image' {"
    if source.count(anchor) != 1:
        raise ValueError("Canonical Image rendering boundary changed")
    before, after = source.split(anchor, 1)
    original = "ConvertTo-HtmlEncode $val.Display"
    if before.count(original) != 2:
        raise ValueError("Expected exactly two SingleValue/MultiValue display calls")
    before = before.replace(original, "ConvertTo-HtmlEncode (ConvertTo-RuReportAttributeValue -Text $val.Display)")
    save(file, before + anchor + after)

def main():
    parser = argparse.ArgumentParser()
    for param in ("new", "candidate", "report"):
        parser.add_argument("--" + param, type=Path, required=True)
    args = parser.parse_args()
    cat = json.loads(read(ROOT / "MIG6-ReportLineStatus.ru-RU.json"))
    result = catalog_gates(cat)
    patch_export(args.candidate, cat)
    patch_attr(args.candidate, args.new)
    result.update({
        "Schema":"adPEAS-RU.2.11.0.MIG6.1",
        "PinnedUpstream":UPSTREAM,
        "ReportLineTranslationOnly":True,
        "AttributeDisplayOnly":True,
        "RawADObjectMutation":False,
        "FindingDefinitionsModified":False,
        "RealADRuntimeTestPerformed":False,
        "ProductionReady":False
    })
    args.report.parent.mkdir(parents=True, exist_ok=True)
    save(args.report, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print("MIG6 PASS: %d exact, %d regex lines, %d attribute statuses, %d value patterns; rendered HTML only" %
          (result["ExactLines"], result["PatternLines"], result["StatusWords"], result["AttributePatterns"]))
if __name__ == "__main__":
    main()
