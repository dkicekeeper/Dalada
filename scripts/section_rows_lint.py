#!/usr/bin/env python3
"""Section rows lint: every row of a glass section pads itself and starts its divider at its text.

A DesignKit `FormSection` or `CardList(layout: .section)` puts its rows back to back with a
divider between them (DesignKit 8.0.0). So each row:

- pads itself vertically: a DesignKit row that does (`UniversalRow`, `ItemRow` and
  `ChecklistRow` since 8.1.0, …) or `.padding(.vertical, …)` on the row. A row without it has
  its text on the dividers (Tenra#88: backups, Ten's memory, subcategories);
- under an icon, starts the divider at its text. A row says where with `.rowDividerInset(_:)`
  (`UniversalRow` and `ItemRow` set it themselves); a `Button`, `NavigationLink` or `Link`
  around the row keeps that to its label, so the link carries it.

The lint reads each section's rows, follows a helper (`row(item)`, `private var header`) or a
row struct of the app to its body, and fails on:

- `no-padding`: a row with no vertical padding of its own;
- `inset-lost`: a link around a row with a leading icon and no `.rowDividerInset` on the link
  (in a section with more than one row);
- `inset-missing`: a row of the app's own (an `HStack`, a helper, a row struct) that starts with
  an icon and sets no `.rowDividerInset` (in a section with more than one row).

A row it cannot read (a view it does not know) is listed with `--report`, never failed.
A justified exception carries `// section-rows-lint:ignore <reason>` on the row's first line.

Usage:
    python3 scripts/section_rows_lint.py            # check (CI)
    python3 scripts/section_rows_lint.py --report   # also the rows it could not read
"""

import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
# The app's Swift sources: Tenra/ (Tenra), ios/ (Dalada).
SOURCES = [d for d in ("Tenra", "ios") if os.path.isdir(os.path.join(ROOT, d))]
EXCLUDED = ("/Debug/", "/Experiments/", "Previews.swift", "/Tests/", "Tests.swift")
IGNORE_MARK = "section-rows-lint:ignore"

# DesignKit views that pad themselves vertically in a section.
SELF_PADDED = {
    "UniversalRow", "UniversalRowSkeleton", "ItemRow", "ItemRowSkeleton", "ChecklistRow",
    "ChecklistRowSkeleton", "ChecklistSummaryRow", "ChecklistSummaryRowSkeleton",
    "FormTextField", "SliderRow", "StepperRow", "TransactionCard", "TransactionRow",
    "TransactionRowSkeleton", "SkeletonRow", "InlineStatusText", "ScheduleRow", "NetAmountRow",
    "InfoRow", "PersonRow", "PersonRowSkeleton", "DownloadRow", "SearchSuggestionRow",
    "SegmentedPicker", "ChipPicker", "TagInput", "MessageComposer",
}
# DesignKit views made for a List: no vertical padding of their own.
NO_PADDING = {"CommentRow", "CurrencyRow", "ThumbnailRow", "MetaLine", "AmountRowListStyle"}
WRAPPERS = {"Button", "NavigationLink", "Link", "ShareLink", "Menu", "PhotosPicker"}
LEADING_ICON = re.compile(
    r"^\s*(Icon|Image|SelectionIndicator|PersonAvatar|Avatar|RemotePhoto|BrandLogo)\s*\(")
PADDING = re.compile(
    r"\.padding\((\.vertical|\.top|\.bottom|\[\s*\.vertical|AppSpacing\.\w+\s*\)|EdgeInsets)"
    r"|\.cardContentPadding\(\)|\.frame\(minHeight")
NOT_ROWS = {"let", "var", "EmptyView", "RowDivider", "Divider", "Spacer", "ForEach", "if",
            "else", "switch", "case", "default", "Group", "Section", "?"}
SECTION = re.compile(
    r"FormSection\b(\((?:[^(){}]|\([^()]*\))*\))?\s*\{"
    r"|CardList\((?:[^(){}]|\([^()]*\))*layout:\s*\.section(?:[^(){}]|\([^()]*\))*\)\s*\{")


def closing(s, i, open_ch, close_ch):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == open_ch:
            depth += 1
        elif s[j] == close_ch:
            depth -= 1
            if depth == 0:
                return j
    return len(s) - 1


def blank_strings_and_comments(s):
    """Same length, so offsets and lines stay; keeps the ignore marks."""
    s = re.sub(r'"""[\s\S]*?"""', lambda m: re.sub(r"[^\n]", "x", m.group(0)), s)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', lambda m: '"' + "x" * (len(m.group(0)) - 2) + '"', s)
    return re.sub(r"//(?!\s*" + IGNORE_MARK + r")[^\n]*", lambda m: " " * len(m.group(0)), s)


class App:
    def __init__(self, texts):
        self.texts = texts
        self.structs = {}  # name -> body
        self.helpers = {}  # (file, name) -> [bodies]
        for path, text in texts.items():
            for m in re.finditer(r"\bstruct\s+([A-Z]\w*)[^{]*\{", text):
                self.structs.setdefault(m.group(1), text[m.end(): closing(text, m.end() - 1, "{", "}")])
            for m in re.finditer(
                    r"\bfunc\s+([a-z]\w*)\s*(?:<[^>]*>)?\(((?:[^()]|\([^()]*\))*)\)\s*->\s*some View\s*\{"
                    r"|\bvar\s+([a-z]\w*)\s*:\s*some View\s*\{", text):
                name = m.group(1) or m.group(3)
                if name != "body":
                    end = closing(text, m.end() - 1, "{", "}")
                    params = re.findall(r"(?:^|,)\s*(?:(\w+)\s+)?(\w+)\s*:", m.group(2) or "")
                    self.helpers.setdefault((path, name), []).append((params, text[m.end(): end]))

    def body(self, path, name, call=""):
        if (path, name) in self.helpers:
            overloads = self.helpers[(path, name)]
            if len(overloads) > 1 and call:
                # Overloads by type: the one whose parameter has the argument's name or label.
                args = call[call.find("(") + 1:] if "(" in call else ""
                first = re.match(r"\s*(?:(\w+)\s*:\s*)?(\w+)", args)
                if first:
                    label, value = first.group(1), first.group(2)
                    chosen = [b for params, b in overloads
                              if params and (params[0][0] == label if label else params[0][1] == value)]
                    if chosen:
                        return chosen
            return [b for _, b in overloads]
        struct = self.structs.get(name)
        if struct:
            m = re.search(r"var body: some View\s*\{", struct)
            if m:
                return [struct[m.end(): closing(struct, m.end() - 1, "{", "}")]]
        return None

    def first_views(self, path, name, seen=(), call=""):
        """The view statements of a helper's or a row struct's body, or None."""
        if name in seen:
            return None
        bodies = self.body(path, name, call)
        if bodies is None:
            return None
        out = []
        for b in bodies:
            b = re.sub(r"^\s*(let|var)\s[^\n]*\n", "", b.strip() + "\n", flags=re.M)
            b = re.sub(r"^\s*return\s+", "", b.strip())
            out += [v for v in statements(b) if head_of(v) not in NOT_ROWS]
        return out

    def padded(self, path, stmt, seen=()):
        """True, False, or None when the row is a view this lint does not know."""
        head = head_of(stmt)
        if PADDING.search(outer(stmt)):
            return True
        args = stmt[stmt.find("("): closing(stmt, stmt.find("("), "(", ")") + 1] if "(" in stmt[:80] else ""
        if re.search(r"verticalPadding:\s*0\b", args):
            # A row told not to pad (its own or an app's row struct that passes it on).
            return False
        if head in WRAPPERS:
            label = label_of(stmt)
            if label is None:
                return None
            return self.padded(path, label, seen)
        if head == "ItemRow" or head == "ChecklistRow" or head.endswith("Skeleton") and head in SELF_PADDED:
            return not re.search(r"verticalPadding:\s*0\b", stmt)
        if head in SELF_PADDED:
            return True
        if head == "AmountRow":
            return "style: .list" not in stmt
        if head in NO_PADDING:
            return False
        if head in ("HStack", "ZStack"):
            # As tall as its tallest view: padded when a view in it pads itself.
            inner = stmt[stmt.find("{") + 1: closing(stmt, stmt.find("{"), "{", "}")] if "{" in stmt else ""
            return any(self.padded(path, v, seen) is True for v in statements(inner)
                       if head_of(v) not in NOT_ROWS)
        if head in ("VStack", "Text", "Label", "LabeledContent"):
            return False
        views = self.first_views(path, head, seen, stmt)
        if views is None:
            return None
        results = [self.padded(path, v, seen + (head,)) for v in views]
        if any(r is False for r in results):
            return False
        if all(r is True for r in results):
            return True
        return None

    def effective(self, path, stmt, mods="", seen=()):
        """A row with helpers and row structs replaced by their views: [(view, modifiers)]."""
        head = head_of(stmt)
        mods = mods + outer(stmt)
        if head in WRAPPERS or head in SELF_PADDED or head in NO_PADDING or head in seen \
                or head in ("HStack", "VStack", "ZStack", "Label", "Text"):
            return [(stmt, mods)]
        views = self.first_views(path, head, seen, stmt)
        if not views:
            return [(stmt, mods)]
        out = []
        for v in views:
            out += self.effective(path, v, mods, seen + (head,))
        return out

    def leading_icon(self, path, stmt, seen=()):
        head = head_of(stmt)
        if head == "ItemRow":
            return bool(re.search(r"leading:\s*\.(symbol|glyph)", stmt))
        if head == "UniversalRow":
            args = stmt[stmt.find("("): closing(stmt, stmt.find("("), "(", ")")] if "(" in stmt else ""
            return bool(re.search(r"\b(leadingIcon|icon):", args))
        if head in ("HStack", "Label"):
            inner = stmt[stmt.find("{") + 1:] if "{" in stmt else ""
            return bool(LEADING_ICON.match(inner.lstrip() + "\n")) or bool(
                re.match(r"\s*Button\s*\{[\s\S]*?\}\s*label:\s*\{\s*(Icon|Image|SelectionIndicator)\b", inner))
        if head in WRAPPERS or head in SELF_PADDED or head in NO_PADDING:
            return False
        views = self.first_views(path, head, seen, stmt)
        return bool(views) and any(self.leading_icon(path, v, seen + (head,)) for v in views)


def statements(block):
    """The view statements of a builder block, with ForEach / if / else bodies flattened."""
    block = re.sub(r"^\s*\(?[\w$]+(?:\s*,\s*[\w$]+)*\)?\s+in\b", "", block)
    out, i, n = [], 0, len(block)
    while i < n:
        i = re.compile(r"\s*").match(block, i).end()
        if i >= n:
            break
        if re.match(r"(ForEach\b|if\b|else\b|\} else\b|switch\b|case\b|Group\s*\{)", block[i:]):
            j = i
            if block.startswith("ForEach", i):
                # Past its arguments, which may hold a closure (a filter).
                p = block.find("(", i)
                if p >= 0:
                    j = closing(block, p, "(", ")")
            j = block.find("{", j)
            if j < 0:
                break
            k = closing(block, j, "{", "}")
            inner = block[j + 1: k]
            if block[i:].startswith("switch"):
                inner = re.sub(r"^\s*(case [^:\n]*|default):", "", inner, flags=re.M)
            out += statements(inner)
            i = k + 1
            continue
        if block[i] in "}{)":
            i += 1
            continue
        j = i
        while j < n:
            ch = block[j]
            if ch == "(":
                j = closing(block, j, "(", ")") + 1
                continue
            if ch == "{":
                j = closing(block, j, "{", "}") + 1
                continue
            if ch == "\n":
                rest = block[j:].lstrip()
                if rest.startswith(".") or rest.startswith("label:") or rest.startswith("} label:"):
                    j += 1
                    continue
                break
            j += 1
        out.append(block[i:j])
        i = j
    return out


def head_of(stmt):
    m = re.match(r"\s*([A-Za-z_]\w*)", stmt)
    return m.group(1) if m else "?"


def outer(stmt):
    """The statement without its closures' bodies: the modifiers of the outermost view."""
    out, i = [], 0
    while i < len(stmt):
        if stmt[i] == "{":
            i = closing(stmt, i, "{", "}") + 1
            out.append("{}")
        else:
            out.append(stmt[i])
            i += 1
    return "".join(out)


def label_of(stmt):
    """A link's label view: its `label:` closure, or its single trailing closure."""
    m = re.search(r"label:\s*\{", stmt)
    if not m:
        m = re.match(r"\s*\w+\s*(\((?:[^()]|\([^()]*\))*\))?\s*\{", stmt)
        if not m:
            return None
    start = m.end() - 1
    inner = stmt[start + 1: closing(stmt, start, "{", "}")]
    views = statements(inner)
    return views[0] if views else None


def main():
    report = "--report" in sys.argv
    texts = {}
    for src in SOURCES:
        for dirpath, _, files in os.walk(os.path.join(ROOT, src)):
            for f in files:
                path = os.path.join(dirpath, f)
                rel = os.path.relpath(path, ROOT)
                if f.endswith(".swift") and not any(x in "/" + rel for x in EXCLUDED):
                    texts[rel] = blank_strings_and_comments(open(path, encoding="utf-8").read())
    app = App(texts)
    failures, unknown = [], []
    for path, s in sorted(texts.items()):
        for m in SECTION.finditer(s):
            start = m.end() - 1
            block = s[start + 1: closing(s, start, "{", "}")]
            rows = [r for r in statements(block) if head_of(r) not in NOT_ROWS]
            # A CardList's closure is one row per item; a FormSection's rows are its statements.
            many = len(rows) > 1 or "ForEach" in block or m.group(0).startswith("CardList")
            line = s.count("\n", 0, m.start()) + 1
            for row in rows:
                first = row.strip().splitlines()[0]
                if IGNORE_MARK in row.split("\n")[0] or IGNORE_MARK in first:
                    continue
                where = f"{path}:{line + block[:block.find(first)].count(chr(10)) if first in block else line}"
                padded = app.padded(path, row)
                if padded is False:
                    failures.append(f"{where}: no-padding: {first.strip()[:80]}")
                elif padded is None:
                    unknown.append(f"{where}: {first.strip()[:80]}")
                if not many:
                    continue
                for view, mods in app.effective(path, row):
                    head = head_of(view)
                    if ".rowDividerInset" in mods:
                        continue
                    if head in WRAPPERS:
                        label = label_of(view)
                        if label is not None and app.leading_icon(path, label):
                            failures.append(f"{where}: inset-lost: {first.strip()[:80]}")
                            break
                    elif head not in SELF_PADDED and head not in NO_PADDING \
                            and ".rowDividerInset" not in view and app.leading_icon(path, view):
                        failures.append(f"{where}: inset-missing: {first.strip()[:80]}")
                        break
    if report and unknown:
        print(f"{len(unknown)} section rows not read (not checked):")
        for u in unknown:
            print("  " + u)
    if failures:
        print(f"{len(failures)} section rows break the glass section's rules (DesignKit 8.1.0):")
        for f in failures:
            print("  " + f)
        print("no-padding: pad the row (.padding(.vertical, AppSpacing.md)) or use a row that pads itself.")
        print("inset-lost: put .rowDividerInset(<icon and the space after it>) on the link, not in its label.")
        print("inset-missing: put .rowDividerInset(<icon and the space after it>) on the row.")
        print(f"A justified exception: // {IGNORE_MARK} <reason> on the row's first line.")
        return 1
    print("section-rows-lint: every row of a glass section pads itself and keeps its divider inset.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
