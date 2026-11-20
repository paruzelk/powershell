#!/usr/bin/env python3
"""MIG7: 106 visible HTML attribute labels and narrow, field-specific value translations.

This modifies only the HTML attribute renderer. Source AD values, finding definitions,
JSON, LDAP metadata and the original data-attr-name identifiers are preserved.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENC = "utf-8-sig"
RENDER = Path("src/modules/Core/Render-HtmlObject.ps1")
UPSTREAM = "477696f48d6b486be5d9a99b598f72e3ccfcc0c0"

def read(path):
    return path.read_text(encoding=ENC)

def write(path, value):
    path.write_text(value, encoding=ENC)

def ps_string(value):
    if not isinstance(value, str) or "\n" in value or "\r" in value or "\0" in value:
        raise ValueError("Unsafe literal in MIG7 dictionary")
    return "'" + value.replace("'", "''") + "'"

def table(name, rows, indent="    "):
    out = [indent + "$" + name + " = @{"]
    for k, v in rows.items():
        out.append(indent + "    " + ps_string(k) + " = " + ps_string(v))
    out.append(indent + "}")
    return "\n".join(out)

def ru_function_label(labels):
    return "\n".join([
        "# MIG7: UI-only attribute captions; data-attr-name uses the original $Row.Name.",
        "function ConvertTo-RuReportAttributeLabel7 {",
        "    param([AllowNull()][string]$Text)",
        "    if ([string]::IsNullOrEmpty($Text)) { return $Text }",
        table("ruLabel7", labels),
        "    if ($ruLabel7.ContainsKey($Text)) { return $ruLabel7[$Text] }",
        "    return $Text",
        "}",
        ""
    ])

def ru_function_context(exact, patterns):
    body = [
        "# MIG7: field-specific display translations; preserves all other attribute values.",
        "function ConvertTo-RuReportAttributeContext7 {",
        "    param([AllowNull()][string]$Name, [AllowNull()][string]$Text)",
        "    if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($Text)) { return $Text }",
        "    $key = $Name + '|' + $Text",
        table("ruExact7", exact),
        "    if ($ruExact7.ContainsKey($key)) { return $ruExact7[$key] }",
        "    $ruRules7 = @("
    ]
    for row in patterns:
        body.append("        @{ Name = " + ps_string(row["name"]) +
                    "; Pattern = " + ps_string(row["pattern"]) +
                    "; Russian = " + ps_string(row["ru"]) + " }")
    body += [
        "    )",
        "    foreach ($rule in $ruRules7) {",
        "        if ($Name -cne [string]$rule.Name) { continue }",
        "        if ($Text -cmatch [string]$rule.Pattern) {",
        "            return [regex]::Replace($Text, [string]$rule.Pattern, [string]$rule.Russian)",
        "        }",
        "    }",
        "    return $Text",
        "}",
        ""
    ]
    return "\n".join(body)

SAMPLES = [
    ("activityStatus", "INACTIVE (no logon recorded, password not changed for >90 days)"),
    ("activityStatus", "INACTIVE (no login for >90 days)"),
    ("privilegeGrantedBy", "GPO 'Example Policy' grants SeMachineAccountPrivilege to NT AUTHORITY\\Authenticated Users"),
    ("decidedBy", "Default Domain Policy (LDAP signing)"),
    ("decidedBy", "Default Domain Policy (server signing)"),
    ("decidedBy", "Default Domain Policy (anonymous SID/name translation)"),
    ("domainControllerTime", "2026-01-01 12:00:00 UTC (skew: +0s)")
]

def check_catalog(cat):
    if cat["Proof"]["UniqueLabelCount"] != 106 or len(cat["Labels"]) != 106:
        raise ValueError("MIG7 expected precisely 106 witnessed unique labels")
    if len(cat["ContextExact"]) != 9 or len(cat["ContextPatterns"]) != 7:
        raise ValueError("MIG7 context dictionary coverage changed")
    folded = set()
    for key, value in cat["Labels"].items():
        if key.casefold() in folded:
            raise ValueError("PowerShell case-insensitive duplicate key " + key)
        folded.add(key.casefold())
        if not value or not re.search(r"[\u0400-\u04ff]", value):
            raise ValueError("Non-Russian attribute label " + key)
    for key,value in cat["ContextExact"].items():
        if key.count("|") != 1 or not value or not re.search(r"[\u0400-\u04ff]", value):
            raise ValueError("Unsafe context translation " + key)
        if key.split("|",1)[0] not in cat["Labels"]:
            raise ValueError("Unknown attribute in context translation " + key)
    for i,row in enumerate(cat["ContextPatterns"]):
        if row["name"] not in cat["Labels"]:
            raise ValueError("Unknown attribute in pattern " + row["name"])
        if not row["pattern"].startswith("^") or not row["pattern"].endswith("$"):
            raise ValueError("Unanchored regex " + row["pattern"])
        if not re.fullmatch(row["pattern"], SAMPLES[i][1]) or row["name"] != SAMPLES[i][0]:
            raise ValueError("MIG7 contextual regex witness " + str(i))
        if not re.search(r"[\u0400-\u04ff]", row["ru"]):
            raise ValueError("Untranslated contextual regex")
    if any(k in cat["ContextExact"] for k in ["GPOName|Default Domain Policy", "distinguishedName|CN=Users", "objectSid|S-1-5-21-0"]):
        raise ValueError("MIG7 must preserve raw AD and domain identifiers")
    return {"Labels":len(cat["Labels"]),"ContextExact":len(cat["ContextExact"]),
            "ContextPatterns":len(cat["ContextPatterns"]),"PatternSyntheticWitnesses":len(SAMPLES)}

def only_once(text, old, new, identifier):
    count = text.count(old)
    if count != 1:
        raise ValueError("MIG7 anchor %s changed (%d)" % (identifier,count))
    return text.replace(old,new,1)

def patch_render(candidate, upstream, cat):
    f = candidate / RENDER
    src = read(f)
    canonical = read(upstream / RENDER)
    # Strong source-parity gate: MIG6 must have changed exactly two scalar displays
    # and must have left ALL other bytes in the pinned render module untouched.
    boundary = "        'Image' {"
    if canonical.count(boundary) != 1:
        raise ValueError("Pinned renderer Image branch changed")
    pre, post = canonical.split(boundary, 1)
    pre_string = "ConvertTo-HtmlEncode $val.Display"
    new_string = "ConvertTo-HtmlEncode (ConvertTo-RuReportAttributeValue -Text $val.Display)"
    if pre.count(pre_string) != 2:
        raise ValueError("Unexpected original SingleValue/MultiValue count")
    expected = pre.replace(pre_string,new_string) + boundary + post
    if src != expected:
        raise ValueError("MIG7 expected exactly the MIG6 source-only rendering modifications")
    label_anchor = "$nameHtml = ConvertTo-HtmlEncode $Row.Name"
    src = only_once(src, label_anchor,
                    "$nameHtml = ConvertTo-HtmlEncode (ConvertTo-RuReportAttributeLabel7 -Text $Row.Name)",
                    "visible attribute caption")
    src = src.replace(new_string,
                      "ConvertTo-HtmlEncode (ConvertTo-RuReportAttributeContext7 -Name $Row.Name -Text " +
                      "(ConvertTo-RuReportAttributeValue -Text $val.Display))", 2)
    before = "function Render-HtmlRow {"
    functions = ru_function_label(cat["Labels"]) + "\n" + ru_function_context(cat["ContextExact"],cat["ContextPatterns"]) + "\n"
    src = only_once(src, before, functions + before, "render helper entry")
    # Preserve original keys used by JS, CSV, security data and original commands.
    if src.count("$attrNameEncoded = ConvertTo-HtmlEncode $Row.Name") != canonical.count("$attrNameEncoded = ConvertTo-HtmlEncode $Row.Name"):
        raise ValueError("Raw HTML attribute key semantics changed")
    if src.count("data-attr-name=") != canonical.count("data-attr-name="):
        raise ValueError("Raw HTML data-attr-name identifiers changed")
    write(f,src)

def main():
    parser = argparse.ArgumentParser()
    for param in ("new","candidate","report"):
        parser.add_argument("--"+param,type=Path,required=True)
    args=parser.parse_args()
    cat=json.loads(read(ROOT/"MIG7-ReportAttributeLabels.ru-RU.json"))
    stats=check_catalog(cat)
    patch_render(args.candidate,args.new,cat)
    stats.update({
        "Schema":"adPEAS-RU.2.11.0.MIG7.1","UpstreamCommit":UPSTREAM,
        "OnlyHTMLLabelsAndContextValues":True,"RawAttributeIdentifiersPreserved":True,
        "OriginalADObjectDataModified":False,"FindingDefinitionsModified":False,
        "OriginalDomainStringsEmbedded":False,"RealADTestPerformed":False,
        "ProductionReady":False
    })
    args.report.parent.mkdir(parents=True,exist_ok=True)
    write(args.report,json.dumps(stats,ensure_ascii=False,indent=2)+"\n")
    print("MIG7 PASS: 106 witnessed attribute captions, 9 exact and 7 regex contextual values. Source-parity gate passed.")
if __name__=="__main__":
    main()
