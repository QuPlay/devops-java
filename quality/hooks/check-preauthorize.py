#!/usr/bin/env python3
"""
Pre-commit check: @PreAuthorize enforcement for merchant-service Controllers.

BLOCKER: Endpoint missing @PreAuthorize
WARNING: Permission naming convention violation

Derivation chain (fully automatic, no config file):
  1. Scan ALL Controllers in same directory → build base_path → prefix mapping
  2. @RequestMapping base path → lookup auto-built mapping → prefix
  3. @XxxMapping method path → standard action rules → hierarchy + action suffix
  4. Combined → full permission string suggestion

Usage: echo "file1.java file2.java" | python3 check-preauthorize.py
"""
import sys
import re
import os
import glob

# --------------------------------------------------------------------------
# Action suffix mapping: last path segment → standard perm suffix
# --------------------------------------------------------------------------
PATH_ACTION_MAP = {
    # View/query → Tab-level permission (no action suffix)
    "page":     None,
    "list":     None,
    "get":      None,
    "info":     None,
    "query":    None,
    # CRUD
    "save":     "_add",
    "add":      "_add",
    "create":   "_add",
    "update":   "_update",
    "edit":     "_update",
    "modify":   "_update",
    "delete":   "_delete",
    "remove":   "_delete",
    # Other
    "export":   "_export",
    "import":   "_import",
    "sort":     "_sort",
    "detail":   "_detail",
    "status":   "_status",
}


def kebab_to_camel(s):
    """install-guide → installGuide"""
    parts = s.split("-")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def extract_base_path(content):
    """Extract class-level @RequestMapping path."""
    m = re.search(r'@RequestMapping\s*\(\s*"([^"]+)"', content)
    return m.group(1).strip("/") if m else ""


def extract_common_prefix(perms):
    """Extract longest common prefix from permission strings by underscore segments."""
    if not perms:
        return ""
    if len(perms) == 1:
        return perms[0]
    split_perms = [p.split("_") for p in perms]
    min_len = min(len(sp) for sp in split_perms)
    parts = []
    for idx in range(min_len):
        values = set(sp[idx] for sp in split_perms)
        if len(values) == 1:
            parts.append(values.pop())
        else:
            break
    return "_".join(parts) if parts else ""


def build_prefix_mapping(controller_dirs):
    """
    Scan ALL Controller files in given directories.
    Build: base_path → perm_prefix mapping automatically.
    """
    mapping = {}
    for d in controller_dirs:
        if not os.path.isdir(d):
            continue
        for fpath in glob.glob(os.path.join(d, "**", "*.java"), recursive=True):
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()
            base = extract_base_path(content)
            if not base:
                continue
            perms = re.findall(r"@PreAuthorize.*?'([^']+)'", content)
            if not perms:
                continue
            prefix = extract_common_prefix(perms)
            if prefix:
                mapping[base] = prefix
    return mapping


def guess_perm(prefix, method_path):
    """
    Derive permission string from prefix + method path.

    /group/save         → prefix_group_add
    /page               → prefix (Tab-level view)
    /install-guide/update → prefix_installGuide_update
    /batch/replace      → prefix_batch_replace
    """
    segments = [s for s in method_path.strip("/").split("/")
                if s and not s.startswith("{")]
    if not segments:
        return prefix

    last = segments[-1]

    if last in PATH_ACTION_MAP:
        action = PATH_ACTION_MAP[last]
        middle = segments[:-1]
    else:
        action = None
        middle = segments

    if middle:
        hierarchy = "_".join(kebab_to_camel(s) for s in middle)
        result = "%s_%s" % (prefix, hierarchy)
    else:
        result = prefix

    if action:
        result += action

    return result


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
files = sys.stdin.read().strip().split()
if not files or files == ['']:
    print("OK")
    sys.exit(0)

# Auto-discover controller directories from input file paths
controller_dirs = set()
for f in files:
    idx = f.find("/controller/")
    if idx != -1:
        controller_dirs.add(f[:idx + len("/controller")])
    else:
        controller_dirs.add(os.path.dirname(f))

# Build mapping by scanning ALL Controllers in the directory
prefix_mapping = build_prefix_mapping(controller_dirs)

missing = []
convention = []

for filepath in files:
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
            content = "".join(lines)
    except (FileNotFoundError, PermissionError):
        continue

    # Determine prefix: mapping lookup → fallback to same-file extraction
    base_path = extract_base_path(content)
    prefix = prefix_mapping.get(base_path, "")
    if not prefix:
        perms = re.findall(r"@PreAuthorize.*?'([^']+)'", content)
        prefix = extract_common_prefix(perms)

    short_file = (filepath.split("/controller/")[-1]
                  if "/controller/" in filepath else filepath)

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        mapping_match = re.search(r"@(Post|Get|Put|Delete|Patch)Mapping", line)
        if mapping_match:
            path = ""
            pm = re.search(r'["\'](/[^"\']*)["\']', line)
            if pm:
                path = pm.group(1)

            has_preauth = False
            preauth_perms = []
            method_sig = ""
            for j in range(i + 1, min(len(lines), i + 7)):
                pline = lines[j].strip()
                if re.search(r"@PreAuthorize", pline):
                    has_preauth = True
                    block = ""
                    for k in range(j, min(len(lines), j + 5)):
                        block += lines[k]
                        if ")" in lines[k] and "@ss" in block:
                            break
                    preauth_perms = re.findall(r"'([^']+)'", block)
                ms = re.search(r"public\s+\S+\s+(\w+)\s*\(", pline)
                if ms:
                    method_sig = ms.group(1) + "()"
                    break

            if not has_preauth:
                suggested = guess_perm(prefix, path) if prefix else "TODO"
                missing.append((short_file, i + 1, method_sig, path, suggested))
            else:
                for perm in preauth_perms:
                    camel = re.search(
                        r"[a-z](Add|Edit|Delete|Remove|View|Export|Import"
                        r"|Create|Update|Sort|Status|Detail)$", perm)
                    if camel:
                        action = camel.group(1)
                        convention.append((short_file, i + 1, perm,
                            "action suffix should use underscore: _%s not %s"
                            % (action.lower(), action)))
                    if perm.endswith("_edit") or perm.endswith("Edit"):
                        convention.append((short_file, i + 1, perm,
                            "use _update instead of _edit (standard suffix)"))
        i += 1

# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
if missing:
    print("MISSING")
    for f, ln, m, p, suggested in missing:
        print("  %s:%d %s [%s]" % (f, ln, m, p))
        print("    @PreAuthorize(\"@ss.hasPermission('%s')\")" % suggested)
    if convention:
        print("CONVENTION")
        for f, ln, perm, issue in convention:
            print("  %s:%d %s -> %s" % (f, ln, perm, issue))
elif convention:
    print("CONVENTION")
    for f, ln, perm, issue in convention:
        print("  %s:%d %s -> %s" % (f, ln, perm, issue))
else:
    print("OK")
