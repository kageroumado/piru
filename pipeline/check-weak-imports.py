#!/usr/bin/env python3
"""Fail a build whose binaries weak-import a symbol that early betas of the SDK's own OS lack.

`@backDeployed(before: iOS 27.2)` makes the compiler call the OS's real symbol on any OS that
reports 27.2 or later, and inline a fallback copy below it. The symbol is weak-imported. An early
27.2 beta reports 27.2 yet does not export it yet, so the weak import binds to null and the first
call jumps to address 0, which App Review's beta devices hit at launch.

For every Mach-O in the given bundles (app, app extensions, watch app, frameworks):

  * ERROR (exit 1): a weak-imported Swift symbol that the SDK it was built with declares
    `@backDeployed(before: <that SDK's own OS version or later>)`, or one on DENYLIST.
  * WARN: a weak-imported Swift symbol declared `@available(<platform> <SDK version>)`. Those are
    reached only behind a compiler-emitted `#available` check, which an early beta of the same
    version also passes, so they carry the same hazard on code paths that run on that OS.

The platform and SDK version come from each binary's LC_BUILD_VERSION, and the declarations from
that SDK's `.swiftinterface` files, so the check follows the Xcode that built the archive.

Usage:
    pipeline/check-weak-imports.py <.xcarchive | .app | Mach-O> [...]
    pipeline/check-weak-imports.py --list <.app>   # also print every weak import, demangled
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Weak imports that always fail, whatever the interfaces say. A safety net for the parser: add the
# mangled substring of any symbol that has crashed a beta before (`xcrun swift-demangle` reads it).
DENYLIST = {
    "10Foundation4DateV2leoiy": "static Foundation.Date.<= (@backDeployed before the 27.2 OSes)",
    "10Foundation4DateV2geoiy": "static Foundation.Date.>= (@backDeployed before the 27.2 OSes)",
}

PLATFORMS = {
    # LC_BUILD_VERSION platform → (xcrun SDK name, platform word in availability attributes)
    "IOS": ("iphoneos", "iOS"),
    "WATCHOS": ("watchos", "watchOS"),
    "MACOS": ("macosx", "macOS"),
    "TVOS": ("appletvos", "tvOS"),
    "VISIONOS": ("xros", "visionOS"),
    "XROS": ("xros", "visionOS"),
}

MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xfe\xed\xfa\xce",
    b"\xca\xfe\xba\xbe",
    b"\xca\xfe\xba\xbf",
}

ACCESSOR_SUFFIX = re.compile(
    r"\.(getter|setter|modify|read|_modify|_read|unsafeAddressor|unsafeMutableAddressor|"
    r"didset|willset|init)$"
)
DEMANGLE_PREFIXES = (
    "dispatch thunk of ",
    "method descriptor for ",
    "merged ",
    "static ",
    "class ",
)


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


# MARK: - Binaries


def macho_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    base = root / "Products" if (root / "Products").is_dir() else root
    found = []
    for path in sorted(base.rglob("*")):
        if not path.is_file() or path.is_symlink() or ".dSYM" in path.as_posix():
            continue
        with path.open("rb") as handle:
            if handle.read(4) in MACHO_MAGICS:
                found.append(path)
    return found


def build_version(binary: Path) -> tuple[str, tuple[int, ...]] | None:
    """The binary's platform and the SDK version it was linked against."""
    text = run("xcrun", "vtool", "-show-build", str(binary))
    platform = re.search(r"^\s*platform\s+(\S+)", text, re.M)
    sdk = re.search(r"^\s*sdk\s+([\d.]+)", text, re.M)
    if not platform or not sdk:
        return None
    return platform.group(1), version_tuple(sdk.group(1))


def weak_imports(binary: Path) -> set[str]:
    text = run("dyld_info", "-imports", str(binary))
    return set(re.findall(r"^\s*0x[0-9A-Fa-f]+\s+(\S+)\s+\[weak-import\]", text, re.M))


def demangle(symbols: list[str]) -> dict[str, str]:
    if not symbols:
        return {}
    out = subprocess.run(
        ["xcrun", "swift-demangle"],
        input="\n".join(symbols),
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    return dict(zip(symbols, out, strict=True))


def qualified_name(demangled: str) -> str | None:
    """`static Foundation.Date.<= infix(…) -> Swift.Bool` → `Foundation.Date.<=`."""
    text = re.sub(r"\(extension in \w+\):", "", demangled)
    changed = True
    while changed:
        changed = False
        for prefix in DEMANGLE_PREFIXES:
            if text.startswith(prefix):
                text, changed = text[len(prefix) :], True
    # Generic arguments follow a name; a `<` after `.` is an operator such as `<=`.
    generics = re.compile(r"(?<=[\w>])<[^<>]*>")
    while generics.search(text):
        text = generics.sub("", text)
    head = re.match(r"([^\s(]+)", text)
    if not head:
        return None
    return ACCESSOR_SUFFIX.sub("", head.group(1))


# MARK: - SDK interfaces


@dataclass
class Declarations:
    back_deployed: dict[str, tuple[int, ...]] = field(default_factory=dict)
    introduced: dict[str, tuple[int, ...]] = field(default_factory=dict)


ATTR_VERSIONS = re.compile(r"@(backDeployed|available)\(([^)]*)\)")
SCOPE_HEADER = re.compile(r"\b(extension|struct|class|enum|actor|protocol)\s+([\w.:]+)")
DECL_NAME = re.compile(
    r"\b(?:func\s+(\w+|[^\w\s(]+)|(?:var|let)\s+`?(\w+)`?|(init)\b[?!]?\s*[(<]|(subscript)\b)"
)
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')


def platform_version(arguments: str, word: str) -> tuple[int, ...] | None:
    # `anyAppleOS 27.0` stands for every Apple platform at that version.
    match = re.search(rf"(?:^|[\s,])(?:{word}|anyAppleOS)\s+([\d.]+)", arguments)
    return version_tuple(match.group(1)) if match else None


def interface_files(sdk: Path) -> list[tuple[str, Path]]:
    files = []
    for module_dir in sorted(
        sdk.glob("System/Library/Frameworks/*.framework/Modules/*.swiftmodule")
    ) + sorted(sdk.glob("usr/lib/swift/*.swiftmodule")):
        candidates = sorted(
            path
            for path in module_dir.glob("*.swiftinterface")
            if ".private." not in path.name and ".package." not in path.name
        )
        if candidates:
            preferred = [path for path in candidates if path.name.startswith("arm64e-")]
            files.append((module_dir.stem, (preferred or candidates)[0]))
    return files


def parse_interface(module: str, path: Path, word: str, into: Declarations) -> None:
    text = path.read_text(errors="replace")
    if "@backDeployed" not in text and "@available" not in text:
        return
    # Each scope: (qualified type name or None, introduced version inherited by its members)
    stack: list[tuple[str | None, tuple[int, ...] | None]] = []
    back_deployed: tuple[int, ...] | None = None
    introduced: tuple[int, ...] | None = None

    for raw in text.splitlines():
        line = STRING_LITERAL.sub('""', raw.strip())
        if not line or line.startswith(("//", "#")):
            continue
        for kind, arguments in ATTR_VERSIONS.findall(line):
            version = platform_version(arguments, word)
            if version is None:
                continue
            if kind == "backDeployed":
                back_deployed = version
            else:
                introduced = version

        header = SCOPE_HEADER.search(line) if "{" in line else None
        decl = DECL_NAME.search(line) if not header else None
        scope_type = next((name for name, _ in reversed(stack) if name), module)
        scope_introduced = next((ver for _, ver in reversed(stack) if ver), None)
        if decl:
            name = next(group for group in decl.groups() if group)
            key = f"{scope_type}.{name}"
            if back_deployed:
                into.back_deployed[key] = back_deployed
            own = max(filter(None, (introduced, scope_introduced)), default=None)
            if own:
                into.introduced[key] = max(own, into.introduced.get(key, ()))
            back_deployed = introduced = None

        pushed_header = False
        for char in line:
            if char == "{":
                if header and not pushed_header:
                    kind, name = (
                        header.group(1),
                        re.sub(r"\.\w+::", ".", header.group(2)).replace("::", "."),
                    )
                    if kind == "extension":
                        # Extensions are top-level only; resetting here also absorbs any brace
                        # drift from `#if` branches that each open the same declaration.
                        stack.clear()
                        scope_introduced = None
                        name = name if "." in name else f"{module}.{name}"
                    else:
                        name = f"{scope_type}.{name.removeprefix(module + '.')}"
                    scope_ver = max(filter(None, (introduced, scope_introduced)), default=None)
                    stack.append((name, scope_ver))
                    pushed_header = True
                    back_deployed = introduced = None
                else:
                    stack.append((None, None))
            elif char == "}" and stack:
                stack.pop()


_declaration_cache: dict[tuple[str, tuple[int, ...]], Declarations] = {}


def declarations(platform: str, sdk_version: tuple[int, ...]) -> Declarations:
    key = (platform, sdk_version)
    if key in _declaration_cache:
        return _declaration_cache[key]
    sdk_name, word = PLATFORMS[platform]
    sdk = Path(run("xcrun", "--sdk", sdk_name, "--show-sdk-path").strip())
    installed = version_tuple(run("xcrun", "--sdk", sdk_name, "--show-sdk-version").strip())
    if installed != sdk_version:
        print(
            f"warning: binaries were built with the {sdk_name} {fmt(sdk_version)} SDK but the "
            f"selected Xcode has {fmt(installed)}; reading {fmt(installed)}'s interfaces",
            file=sys.stderr,
        )
    found = Declarations()
    for module, path in interface_files(sdk):
        parse_interface(module, path, word, found)
    # A symbol moved between modules keeps the old module in its mangled name
    # (`@_originallyDefinedIn(module: "SwiftUI")` on SwiftUICore's View), so index it under both.
    for module, path in interface_files(sdk):
        text = path.read_text(errors="replace")
        for original in set(re.findall(r'@_originallyDefinedIn\(module: "(\w+)"', text)):
            for table in (found.back_deployed, found.introduced):
                for key, version in list(table.items()):
                    if key.startswith(module + "."):
                        table.setdefault(original + key[len(module) :], version)
    _declaration_cache[key] = found
    return found


def fmt(version: tuple[int, ...]) -> str:
    return ".".join(map(str, version))


# MARK: - Main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("paths", nargs="+", type=Path, help=".xcarchive, .app, or Mach-O file")
    parser.add_argument("--list", action="store_true", help="print every weak import, demangled")
    args = parser.parse_args()

    errors = warnings = 0
    for root in args.paths:
        if not root.exists():
            print(f"error: {root} does not exist", file=sys.stderr)
            return 2
        binaries = macho_files(root)
        if not binaries:
            print(f"error: no Mach-O files under {root}", file=sys.stderr)
            return 2
        for binary in binaries:
            build = build_version(binary)
            label = binary.relative_to(root) if binary != root else binary.name
            if build is None or build[0] not in PLATFORMS:
                print(f"skip  {label}: no recognised LC_BUILD_VERSION")
                continue
            platform, sdk_version = build
            word = PLATFORMS[platform][1]
            decls = declarations(platform, sdk_version)
            swift = sorted(symbol for symbol in weak_imports(binary) if symbol.startswith("_$s"))
            names = demangle(swift)
            hits = []
            for symbol in swift:
                demangled = names[symbol]
                qualified = qualified_name(demangled)
                denied = next((why for frag, why in DENYLIST.items() if frag in symbol), None)
                cutoff = decls.back_deployed.get(qualified or "")
                since = decls.introduced.get(qualified or "")
                back_deployed = cutoff is not None and cutoff >= sdk_version
                if denied or back_deployed:
                    why = (
                        f"@backDeployed(before: {word} {fmt(cutoff)})" if back_deployed else denied
                    )
                    hits.append(("ERROR", symbol, demangled, why))
                elif (
                    since
                    and since >= sdk_version
                    and not demangled.startswith(
                        (
                            "protocol ",
                            "nominal ",
                            "associated ",
                            "type metadata",
                            "method descriptor",
                        )
                    )
                ):
                    hits.append(("WARN ", symbol, demangled, f"@available({word} {fmt(since)})"))
                elif args.list:
                    hits.append(("     ", symbol, demangled, ""))
            print(f"{label}  [{word} SDK {fmt(sdk_version)}, {len(swift)} Swift weak imports]")
            for level, symbol, demangled, why in hits:
                print(f"  {level} {demangled}\n         {symbol}  {why}".rstrip())
                errors += level == "ERROR"
                warnings += level == "WARN "

    print(f"\n{errors} error(s), {warnings} warning(s)")
    if errors:
        print(
            "Weak-imported back-deployed symbols bind to null on early betas of the SDK's OS. "
            "Rewrite the call so it does not reach the back-deployed declaration "
            "(for Date <=/>=, use Date.isOnOrBefore/isOnOrAfter).",
            file=sys.stderr,
        )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
