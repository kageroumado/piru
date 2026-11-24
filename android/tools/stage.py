#!/usr/bin/env python3
"""Stage Piru's iOS sources as the Skip Fuse package that builds the Android app.

    stage.py            rebuild the staged package in $PIRU_ANDROID_STAGE
    stage.py --check    stage into a scratch tree and report patches that no longer apply

The iOS tree is the only source. Every Android difference is one of:

  exclude.txt        upstream files the Android build does not compile (glob per line)
  patches/series     patches applied in order to the staged copy, `git apply -p1`
  substitutions.txt  regex rewrites applied to every staged Swift file after the patches
  app/               the Skip package around the sources, and Android-only Swift
  ../Compat          stand-ins for Apple modules, and in-module compat sources
  vendor/<package>/  patches for a dependency, applied to a pinned clone that a SwiftPM
                     mirror substitutes for the original

Staging is deterministic: the same commit, patches and pins produce the same tree. Files
whose content did not change keep their timestamps, so an incremental build stays one.
"""

import argparse
import filecmp
import fnmatch
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from android_paths import PIRU_ANDROID, STAGE

ANDROID = Path(__file__).resolve().parents[1]
REPO = ANDROID.parent
MODULE = Path("Sources/Piru")
UPSTREAM_DIRS = ["Piru", "Shared"]
# Every SwiftPM scratch path build-app.sh builds the stage in: the transpile phase's and the
# bridge phase's. Each keeps its own checkouts and resolved revisions.
SCRATCH_PATHS = [Path(".build"), Path(".build/Android/Piru/swift")]
SQLITE = "sqlite-amalgamation-3530400"
# google/material-design-icons, the source of the glyphs android/symbols.tsv names (Apache-2.0).
MATERIAL_SYMBOLS = "bd8cb85bd4bad964fe6918f79665bb40c3a8efef"

# Pinned dependencies replaced by a patched local clone: (url, tag, version). The mirror maps
# the original URL to the clone, so no manifest names the substitute. `skip` is patched to build
# its tool from skipstone source, which is how skipstone's own patches reach the build.
VENDORED = {
    "GRDB.swift": ("https://github.com/groue/GRDB.swift.git", "v7.11.1", "7.11.1"),
    "skip": ("https://github.com/skiptools/skip.git", "1.9.13", "1.9.13"),
    "skipstone": ("https://github.com/skiptools/skipstone.git", "1.9.13", "1.9.13"),
    "skip-fuse-ui": ("https://github.com/skiptools/skip-fuse-ui.git", "1.19.4", "1.19.4"),
    "skip-ui": ("https://github.com/skiptools/skip-ui.git", "1.66.4", "1.66.4"),
    "skip-android-bridge": (
        "https://github.com/skiptools/skip-android-bridge.git",
        "0.7.4",
        "0.7.4",
    ),
}


def run(*args, cwd=None, check=True):
    return subprocess.run(args, cwd=cwd, check=check, capture_output=True, text=True)


def excluded_patterns():
    lines = (ANDROID / "exclude.txt").read_text().splitlines()
    return [line.split("#", 1)[0].strip() for line in lines if line.split("#", 1)[0].strip()]


def is_excluded(relative: str, patterns) -> bool:
    return any(fnmatch.fnmatch(relative, pattern) for pattern in patterns)


def stage_sources(tree: Path):
    """Upstream Swift into Sources/Piru/Upstream, keeping the repo-relative layout patches name."""
    patterns = excluded_patterns()
    upstream = tree / MODULE / "Upstream"
    count = 0
    for top in UPSTREAM_DIRS:
        for source in sorted((REPO / top).rglob("*.swift")):
            relative = source.relative_to(REPO).as_posix()
            if is_excluded(relative, patterns):
                continue
            target = upstream / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            count += 1
    return count


def apply_patches(tree: Path):
    series = ANDROID / "patches" / "series"
    applied = []
    for line in series.read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        patch = ANDROID / "patches" / name
        result = run(
            "git",
            "apply",
            "-p1",
            "--whitespace=nowarn",
            f"--directory={MODULE}/Upstream",
            str(patch),
            cwd=tree,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"patch does not apply: {name}\n{result.stderr}")
        applied.append(name)
    return applied


def apply_substitutions(tree: Path):
    """After the patches, as ungoogled-chromium orders it: patches keep upstream context and
    so keep applying, and one rule covers every file that matches it."""
    rules = []
    for line in (ANDROID / "substitutions.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        pattern, _, replacement = line.partition("\t")
        rules.append((re.compile(pattern, re.M), replacement))
    changed = 0
    for path in sorted((tree / MODULE).rglob("*.swift")):
        text = path.read_text()
        new = text
        for pattern, replacement in rules:
            new = pattern.sub(replacement, new)
        if new != text:
            path.write_text(new)
            changed += 1
    return changed


CHART_OPEN = re.compile(r"\bChart\s*(?:\([^()]*\)\s*)?\{")


def rewrite_chart_bodies(tree: Path):
    """Inside a `Chart { }` body SwiftUI's ForEach builds chart content, which SkipFuseUI's
    ForEach cannot, so there it becomes ChartForEach (Android/Platform/Charts+Android.swift).
    Brace-matched per body, which a line regex cannot do."""
    changed = 0
    for path in sorted((tree / MODULE / "Upstream").rglob("*.swift")):
        text = path.read_text()
        pieces, cursor = [], 0
        for match in CHART_OPEN.finditer(text):
            if match.start() < cursor:
                continue
            depth, index = 1, match.end()
            while depth and index < len(text):
                depth += {"{": 1, "}": -1}.get(text[index], 0)
                index += 1
            body = re.sub(r"\bForEach\(", "ChartForEach(", text[match.end() : index])
            pieces.append(text[cursor : match.end()] + body)
            cursor = index
        if pieces:
            new = "".join(pieces) + text[cursor:]
            if new != text:
                path.write_text(new)
                changed += 1
    return changed


# Launcher icon densities: (folder, pixels per dp).
DENSITIES = [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]


def p3_to_srgb(components: str) -> tuple[int, int, int, int]:
    """An icon.json `display-p3:r,g,b,a` color as 8-bit sRGB."""
    r, g, b, a = (float(v) for v in components.split(":", 1)[1].split(","))

    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def encode(c: float) -> int:
        c = min(1.0, max(0.0, c))
        return round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))

    lr, lg, lb = linear(r), linear(g), linear(b)
    return (
        encode(1.2249 * lr - 0.2247 * lg),
        encode(-0.0420 * lr + 1.0419 * lg),
        encode(-0.0197 * lr - 0.0786 * lg + 1.0979 * lb),
        round(255 * a),
    )


def stage_launcher_icon(tree: Path):
    """The Android launcher icon from the iOS icon's Icon Composer layers (Piru/Piru.icon),
    as adaptive layers: the icon.json gradient is the background, and the artwork layers
    composited in icon.json order are the foreground, scaled so the pill stays inside the
    72 dp every launcher mask shows. The rendered iOS icon cannot serve: its squircle rim
    shows as a ring inside a round mask. No monochrome layer: without one Android shows the
    icon itself. Needs rsvg-convert (librsvg)."""
    from PIL import Image

    bundle = REPO / "Piru/Piru.icon"
    spec = json.loads((bundle / "icon.json").read_text())
    top, bottom = (p3_to_srgb(c) for c in spec["fill"]["linear-gradient"])

    def gradient(size: int) -> Image.Image:
        image = Image.new("RGBA", (size, size))
        for y in range(size):
            t = y / max(1, size - 1)
            image.paste(
                tuple(round(a + (b - a) * t) for a, b in zip(top, bottom, strict=True)),
                (0, y, size, y + 1),
            )
        return image

    artwork = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    with tempfile.TemporaryDirectory() as scratch:
        for group in reversed(spec["groups"]):
            for layer in reversed(group["layers"]):
                if layer.get("hidden"):
                    continue
                source = bundle / "Assets" / layer["image-name"]
                if source.suffix == ".svg":
                    png = Path(scratch) / (source.stem + ".png")
                    run("rsvg-convert", "-w", "1024", "-h", "1024", str(source), "-o", str(png))
                    image = Image.open(png).convert("RGBA")
                else:
                    image = Image.open(source).convert("RGBA")
                scale = layer.get("position", {}).get("scale", 1)
                size = round(image.width * scale)
                if size != 1024 or image.width != 1024:
                    image = image.resize((size, size), Image.LANCZOS)
                placed = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
                placed.paste(image, ((1024 - size) // 2, (1024 - size) // 2))
                artwork = Image.alpha_composite(artwork, placed)

    res = tree / "Android/app/src/main/res"
    for folder, scale in DENSITIES:
        out = res / f"mipmap-{folder}"
        out.mkdir(parents=True, exist_ok=True)
        canvas = round(108 * scale)
        inner = round(88 * scale)
        foreground = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        offset = (canvas - inner) // 2
        foreground.paste(artwork.resize((inner, inner), Image.LANCZOS), (offset, offset))
        foreground.save(out / "ic_launcher_foreground.png", optimize=True)
        gradient(canvas).save(out / "ic_launcher_background.png", optimize=True)
        legacy = round(48 * scale)
        flat = Image.alpha_composite(gradient(1024), artwork).resize(
            (legacy, legacy), Image.LANCZOS
        )
        mask = Image.new("L", (legacy, legacy), 0)
        from PIL import ImageDraw

        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, legacy - 1, legacy - 1), radius=legacy // 4, fill=255
        )
        flat.putalpha(mask)
        flat.save(out / "ic_launcher.png", optimize=True)
    (res / "mipmap-anydpi").mkdir(parents=True, exist_ok=True)
    (res / "mipmap-anydpi/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '<background android:drawable="@mipmap/ic_launcher_background" />\n'
        '<foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )


def stage_template(tree: Path):
    # Compat/InModule is not staged: Skip aliases LocalizedStringResource to its own Android
    # implementation inside the app module. It serves the headless PiruCore build.
    shutil.copytree(ANDROID / "app", tree, dirs_exist_ok=True)
    package = tree / "Package.swift"
    package.write_text(package.read_text().replace("@COMPAT_PATH@", str(ANDROID / "Compat")))
    env = tree / "Skip.env"
    marketing, build = project_versions()
    text = re.sub(
        r"(?m)^MARKETING_VERSION = .*$", f"MARKETING_VERSION = {marketing}", env.read_text()
    )
    env.write_text(
        re.sub(r"(?m)^CURRENT_PROJECT_VERSION = .*$", f"CURRENT_PROJECT_VERSION = {build}", text)
    )


def project_versions():
    pbxproj = (REPO / "Piru.xcodeproj/project.pbxproj").read_text()
    marketing = re.search(r"MARKETING_VERSION = ([\d.]+);", pbxproj).group(1)
    build = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", pbxproj).group(1)
    return marketing, build


def stage_resources(tree: Path):
    """The resources the iOS bundle carries that the shared code reads at runtime."""
    resources = tree / MODULE / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    catalog = verified_catalog()
    for source in [
        catalog,
        REPO / "Piru/Data/MoleculeShapes.json",
        REPO / "Piru/Localizable.xcstrings",
        *sorted((REPO / "Piru/Fonts").glob("*")),
    ]:
        shutil.copy2(source, resources / source.name)
    flatten_asset_catalog(REPO / "Shared/Assets.xcassets", resources / "Module.xcassets")
    shutil.copytree(REPO / "Piru/Resources/Licenses", resources / "Licenses", dirs_exist_ok=True)
    shutil.copytree(ANDROID / "licenses", resources / "Licenses", dirs_exist_ok=True)
    stage_symbols(resources / "Module.xcassets")
    stage_materials(resources / "Module.xcassets")
    (tree / MODULE / "Generated").mkdir(exist_ok=True)
    generate_asset_symbols(
        REPO / "Shared/Assets.xcassets", tree / MODULE / "Generated/AssetSymbols.swift"
    )
    generate_info_plist(
        tree / MODULE / "Generated/InfoPlist.swift",
        {"PiruResourceStamp": resource_stamp(resources)},
    )


def verified_catalog() -> Path:
    """The bundled catalog, refused unless it is the one Piru/Data/manifest.json describes: an
    older or newer file would ship data the build was not made with."""
    catalog = REPO / "Piru/Data/piru-substances.sqlite"
    if not catalog.exists():
        raise SystemExit("Piru/Data/piru-substances.sqlite is missing: run pipeline/fetch-db.sh")
    expected = json.loads((REPO / "Piru/Data/manifest.json").read_text())["sqlite_sha256"]
    actual = hashlib.sha256(catalog.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(
            f"Piru/Data/piru-substances.sqlite is {actual[:12]}…, the manifest expects {expected[:12]}…:"
            " run pipeline/fetch-db.sh --force"
        )
    return catalog


def resource_stamp(resources: Path) -> str:
    """One hash over every staged resource file. The app re-copies its resources out of the
    APK when this changes (Android/Platform/Resources+Android.swift)."""
    digest = hashlib.sha256()
    for path in sorted(p for p in resources.rglob("*") if p.is_file()):
        digest.update(path.relative_to(resources).as_posix().encode())
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


# MARK: - Symbols


def material_symbol(name: str, filled: bool) -> Path:
    """The Material Symbols Rounded SVG at the pinned commit, fetched once into downloads/."""
    cache = PIRU_ANDROID / "downloads" / "material-symbols" / MATERIAL_SYMBOLS
    file = f"{name}{'_fill1' if filled else ''}_24px.svg"
    local = cache / file
    if not local.exists():
        cache.mkdir(parents=True, exist_ok=True)
        url = (
            f"https://raw.githubusercontent.com/google/material-design-icons/{MATERIAL_SYMBOLS}"
            f"/symbols/web/{name}/materialsymbolsrounded/{file}"
        )
        run(
            "curl",
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--retry",
            "3",
            url,
            "-o",
            str(local),
        )
    return local


def stage_symbols(catalog: Path):
    """Every SF Symbol android/symbols.tsv maps becomes a `.symbolset` of that name holding the
    Material glyph, laid out as an SF Symbols export (Symbols > Regular-S > path): SkipUI looks
    a system image up in the catalog before its own few Material fallbacks. SF Symbols may not
    ship on Android (Apple's license), so every glyph drawn there is Material's."""
    for line in (ANDROID / "symbols.tsv").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        sf, material, fill = line.split("\t")
        svg = material_symbol(material, fill == "1").read_text()
        paths = re.findall(r'<path d="([^"]+)"', svg)
        if not paths:
            raise SystemExit(f"no path in Material symbol {material} (for {sf})")
        folder = catalog / f"{sf}.symbolset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{sf}.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960">'
            '<g id="Symbols"><g id="Regular-S">'
            + "".join(f'<path d="{d}"/>' for d in paths)
            + "</g></g></svg>\n"
        )
        (folder / "Contents.json").write_text(
            json.dumps(
                {
                    "info": {"author": "stage.py", "version": 1},
                    "symbols": [{"filename": f"{sf}.svg", "idiom": "universal"}],
                },
                indent=2,
            )
            + "\n"
        )


# MARK: - Materials

# iOS materials as the fills they read as on a plain page, since Compose has no blur behind a
# view: a neutral at partial opacity, so over white a card is iOS's measured #F5F5F5 and over a
# colored surface the color still shows through as it would through the blur.
# (material, light gray, light alpha, dark gray, dark alpha)
MATERIALS = [
    ("ultraThin", 0.94, 0.72, 0.11, 0.72),
    ("thin", 0.94, 0.80, 0.12, 0.80),
    ("regular", 0.95, 0.88, 0.13, 0.88),
    ("thick", 0.96, 0.94, 0.14, 0.94),
    ("ultraThick", 0.97, 0.97, 0.15, 0.97),
]


def stage_materials(catalog: Path):
    def color(gray: float, alpha: float, dark: bool) -> dict:
        entry = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "red": f"{gray:.3f}",
                    "green": f"{gray:.3f}",
                    "blue": f"{min(1.0, gray + 0.01):.3f}",
                    "alpha": f"{alpha:.3f}",
                },
            },
            "idiom": "universal",
        }
        if dark:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        return entry

    for name, light, light_alpha, dark, dark_alpha in MATERIALS:
        folder = catalog / f"android__material__{name}.colorset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Contents.json").write_text(
            json.dumps(
                {
                    "colors": [color(light, light_alpha, False), color(dark, dark_alpha, True)],
                    "info": {"author": "stage.py", "version": 1},
                },
                indent=2,
            )
            + "\n"
        )


# MARK: - Info.plist


def build_settings() -> dict[str, str]:
    """The app target's plain build settings (first definition wins), plus the ones Xcode
    derives that Piru/Info.plist reads."""
    pbxproj = (REPO / "Piru.xcodeproj/project.pbxproj").read_text()
    settings: dict[str, str] = {}
    for key, value in re.findall(r"(?m)^\s*([A-Z][A-Z0-9_]*) = \"?([^\";\n]*)\"?;", pbxproj):
        settings.setdefault(key, value)
    marketing, build = project_versions()
    settings["MARKETING_VERSION"] = marketing
    settings["CURRENT_PROJECT_VERSION"] = build
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = settings["PIRU_BUNDLE_ID"]
    return settings


def expand(value: str, settings: dict[str, str]) -> str | None:
    """`value` with every $(SETTING) expanded, or None when one is undefined."""
    for _ in range(8):
        names = re.findall(r"\$\((\w+)\)", value)
        if not names:
            return value
        if any(name not in settings for name in names):
            return None
        value = re.sub(r"\$\((\w+)\)", lambda m: settings[m.group(1)], value)
    return None


def generate_info_plist(out: Path, extra: dict[str, str]):
    """Piru/Info.plist's string values with build settings expanded, for the code that reads
    `Bundle.main`'s Info dictionary: Android's main bundle has none (substitutions.txt points
    those reads here). `extra` adds values the Android build derives itself."""
    settings = build_settings()
    info = plistlib.loads((REPO / "Piru/Info.plist").read_bytes())
    info.update(extra)
    info.setdefault("CFBundleShortVersionString", "$(MARKETING_VERSION)")
    info.setdefault("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)")
    info.setdefault("CFBundleIdentifier", "$(PRODUCT_BUNDLE_IDENTIFIER)")
    entries = []
    for key in sorted(info):
        if isinstance(info[key], str) and (value := expand(info[key], settings)) is not None:
            entries.append(f"        {json.dumps(key)}: {json.dumps(value)},")
    out.write_text(
        "\n".join(
            [
                "// Generated by android/tools/stage.py from Piru/Info.plist and the project's build",
                "// settings.",
                "",
                "import Foundation",
                "",
                "nonisolated enum AndroidInfoPlist {",
                "    static var infoDictionary: [String: Any]? { values }",
                "",
                "    private static let values: [String: String] = [",
                *entries,
                "    ]",
                "",
                "    static func object(forInfoDictionaryKey key: String) -> Any? {",
                "        infoDictionary?[key]",
                "    }",
                "}",
                "",
            ]
        )
    )


# MARK: - Asset symbols

# SkipUI finds an asset by its folder's name alone (`<name>.colorset` anywhere in the
# catalog), so a namespaced set (`surface/background`) never matches, and the leaf names
# repeat across namespaces. The staged catalog holds every set at the top level under its
# namespaced name joined by this separator, and the symbols ask for that name.
NAMESPACE_SEPARATOR = "__"


def asset_sets(catalog: Path, suffix: str, prefix: list[str] | None = None):
    """(namespace path, set folder) for every `suffix` set, by Xcode's naming: a folder adds
    its name to the path only when it provides a namespace."""
    prefix = prefix or []
    for child in sorted(catalog.iterdir()):
        if child.suffix == suffix:
            yield [*prefix, child.stem], child
        elif child.is_dir() and child.suffix == "":
            contents = child / "Contents.json"
            namespaced = contents.exists() and json.loads(contents.read_text()).get(
                "properties", {}
            ).get("provides-namespace", False)
            yield from asset_sets(child, suffix, [*prefix, child.name] if namespaced else prefix)


def flatten_asset_catalog(catalog: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy2(catalog / "Contents.json", out / "Contents.json")
    seen: set[str] = set()
    for suffix in (".colorset", ".imageset"):
        for path, folder in asset_sets(catalog, suffix):
            name = NAMESPACE_SEPARATOR.join(path)
            if name in seen:
                raise SystemExit(f"two assets flatten to {name}")
            seen.add(name)
            shutil.copytree(folder, out / f"{name}{suffix}", dirs_exist_ok=True)


def symbol_name(component: str, is_type: bool) -> str:
    """Xcode's asset-symbol naming: split on non-alphanumerics, camelCase, and for a
    namespace capitalize the first letter. `AccentColor` becomes `accent`, as Xcode does."""
    words = [w for w in re.split(r"[^A-Za-z0-9]+", component) if w]
    name = words[0][:1].lower() + words[0][1:] + "".join(w[:1].upper() + w[1:] for w in words[1:])
    if not is_type and name.endswith("Color") and name != "Color":
        name = name[: -len("Color")]
    if is_type:
        name = name[:1].upper() + name[1:]
    return f"_{name}" if name[:1].isdigit() else name


def generate_asset_symbols(catalog: Path, out: Path):
    """The Color and ImageResource symbols Xcode generates from the catalog, resolved by name
    from the module's asset catalog through AndroidResources.bundle."""
    lines = [
        "// Generated by android/tools/stage.py from Shared/Assets.xcassets: the symbols",
        "// Xcode's asset-symbol generation provides the iOS build.",
        "",
        "import SwiftUI",
        "",
    ]

    def walk(directory: Path, prefix: list[str], depth: int, suffix: str, emit) -> list[str]:
        out_lines: list[str] = []
        pad = "    " * depth
        for child in sorted(directory.iterdir()):
            if child.suffix == suffix:
                out_lines.append(
                    pad + emit(child.stem, NAMESPACE_SEPARATOR.join([*prefix, child.stem]))
                )
            elif child.is_dir() and child.suffix == "":
                contents = child / "Contents.json"
                namespaced = contents.exists() and json.loads(contents.read_text()).get(
                    "properties", {}
                ).get("provides-namespace", False)
                if namespaced:
                    inner = walk(child, [*prefix, child.name], depth + 1, suffix, emit)
                    if inner:
                        out_lines.append(f"{pad}enum {symbol_name(child.name, True)} {{")
                        out_lines.extend(inner)
                        out_lines.append(f"{pad}}}")
                else:
                    out_lines.extend(walk(child, prefix, depth, suffix, emit))
        return out_lines

    colors = walk(
        catalog,
        [],
        1,
        ".colorset",
        lambda stem, name: (
            f'static var {symbol_name(stem, False)}: Color {{ Color("{name}", bundle: AndroidResources.bundle) }}'
        ),
    )
    lines += ["extension Color {", *colors, "}", ""]
    lines += [
        "extension ShapeStyle where Self == Color {",
        *[line for line in colors if line.startswith("    static var")],
        "}",
        "",
    ]
    images = walk(
        catalog,
        [],
        1,
        ".imageset",
        lambda stem, name: f'static let {symbol_name(stem, False)} = ImageResource(name: "{name}")',
    )
    lines += [
        "/// An asset-catalog image, as Xcode's generated `ImageResource` names it.",
        "struct ImageResource: Hashable, Sendable {",
        "    let name: String",
        "}",
        "",
        "nonisolated extension Image {",
        "    init(_ resource: ImageResource) {",
        "        self.init(resource.name, bundle: AndroidResources.bundle)",
        "    }",
        "}",
        "",
        "extension ImageResource {",
        *images,
        "}",
    ]
    out.write_text("\n".join(lines) + "\n")


# MARK: - Vendored dependencies


def stage_vendored(tree: Path):
    """Clones go straight into the stage, outside the byte-for-byte sync: git writes into a
    clone's .git on its own schedule. The fixed-date commit keeps each clone's revision, and so
    SwiftPM's resolution, the same across runs."""
    cache = PIRU_ANDROID / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    mirrors = []
    for name, (url, tag, version) in VENDORED.items():
        bare = cache / f"{name}.git"
        if not bare.exists():
            run("git", "clone", "--bare", "--quiet", url, str(bare))
        if run(
            "git", "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}", cwd=bare, check=False
        ).returncode:
            run("git", "fetch", "--quiet", "--tags", url, cwd=bare)
        clone = tree / "Vendor" / name
        if clone.exists():
            shutil.rmtree(clone)
        run(
            "git",
            "-c",
            "maintenance.auto=false",
            "clone",
            "--quiet",
            "--branch",
            tag,
            str(bare),
            str(clone),
        )
        run("git", "config", "maintenance.auto", "false", cwd=clone)
        run("git", "config", "gc.auto", "0", cwd=clone)
        if name == "GRDB.swift":
            add_sqlite_amalgamation(clone)
        for patch in sorted((ANDROID / "vendor" / name).glob("*.patch")):
            result = run("git", "apply", "--whitespace=nowarn", str(patch), cwd=clone, check=False)
            if result.returncode != 0:
                raise SystemExit(
                    f"vendor patch does not apply: {name}/{patch.name}\n{result.stderr}"
                )
        run("git", "add", "-A", cwd=clone)
        # Fixed identity and dates make the commit, and so Package.resolved, identical per run.
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=stage",
                "-c",
                "user.email=stage@localhost",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "--allow-empty",
                "--no-verify",
                "-m",
                "Android patches",
            ],
            cwd=clone,
            check=True,
            capture_output=True,
            env={
                **os.environ,
                "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
                "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
            },
        )
        run("git", "tag", "--force", version, cwd=clone)
        mirrors.append({"original": url, "mirror": (STAGE / "Vendor" / name).as_uri()})
    forget_moved_vendors(tree)
    config = tree / ".swiftpm/configuration"
    config.mkdir(parents=True, exist_ok=True)
    (config / "mirrors.json").write_text(
        json.dumps({"object": mirrors, "version": 1}, indent=2) + "\n"
    )


def forget_moved_vendors(tree: Path):
    """A clone's commit changes when its patches do, under the same version tag. SwiftPM caches
    each repository and never refetches a moved tag, so for every vendored package whose commit
    changed since the last run, its pin and its cached clones go."""
    marker = tree / ".build" / "vendor-heads.json"
    before = json.loads(marker.read_text()) if marker.exists() else {}
    now = {
        name: run("git", "rev-parse", "HEAD", cwd=tree / "Vendor" / name).stdout.strip()
        for name in VENDORED
    }
    moved = {name for name in VENDORED if before.get(name) != now[name]}
    if moved:
        resolved = tree / "Package.resolved"
        if resolved.exists():
            pins = json.loads(resolved.read_text())
            pins["pins"] = [
                pin
                for pin in pins.get("pins", [])
                if pin["identity"] not in {m.lower() for m in moved}
            ]
            resolved.write_text(json.dumps(pins, indent=2) + "\n")
        caches = [
            *(tree / scratch / "repositories" for scratch in SCRATCH_PATHS),
            Path.home() / "Library/Caches/org.swift.swiftpm/repositories",
        ]
        for cache in caches:
            for clone in cache.glob("*") if cache.exists() else []:
                config = (
                    clone / "config" if (clone / "config").exists() else clone / ".git" / "config"
                )
                if config.exists() and any(
                    str(tree / "Vendor" / name) in config.read_text() for name in moved
                ):
                    shutil.rmtree(clone)
        for scratch in SCRATCH_PATHS:
            for name in moved:
                checkout = tree / scratch / "checkouts" / name
                if checkout.exists():
                    shutil.rmtree(checkout)
            # SwiftPM also records each dependency's resolved revision here.
            (tree / scratch / "workspace-state.json").unlink(missing_ok=True)
        # And trusts a version's first-seen commit (TOFU). Only the entries whose origin is a
        # vendored clone in this stage go; every real remote keeps its protection.
        fingerprints = Path.home() / "Library/org.swift.swiftpm/security/fingerprints"
        for record in fingerprints.glob("*.json") if fingerprints.exists() else []:
            data = json.loads(record.read_text())
            versions = data.get("versionFingerprints", {})
            kept = {
                version: kinds
                for version, kinds in versions.items()
                if not any(str(tree / "Vendor" / name) in json.dumps(kinds) for name in moved)
            }
            if kept != versions:
                data["versionFingerprints"] = kept
                record.write_text(json.dumps(data, indent=2))
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps(now, indent=2) + "\n")


def add_sqlite_amalgamation(clone: Path):
    source = PIRU_ANDROID / "downloads" / SQLITE
    if not source.exists():
        raise SystemExit(f"{source} is missing: run android/tools/setup.sh")
    target = clone / "Sources/GRDBSQLite"
    (target / "include").mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "sqlite3.c", target / "sqlite3.c")
    shutil.copy2(source / "sqlite3.h", target / "include/sqlite3.h")


# MARK: - Sync


def sync(scratch: Path, stage: Path):
    """Mirror scratch onto stage, touching only files whose bytes changed. Build products and
    tool state inside the stage (.build, Android/.gradle, …) survive."""
    keep = {
        ".build",
        ".gradle",
        ".kotlin",
        "build",
        "Android/.gradle",
        "Android/app/build",
        ".swiftpm",
        "Vendor",
    }
    for path in sorted(scratch.rglob("*")):
        relative = path.relative_to(scratch)
        destination = stage / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif (
            path.is_symlink()
            or not destination.exists()
            or not filecmp.cmp(path, destination, shallow=False)
        ):
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_dir() and not destination.is_symlink():
                shutil.rmtree(destination)
            shutil.copy2(path, destination, follow_symlinks=False)
    for path in sorted(stage.rglob("*"), reverse=True):
        relative = path.relative_to(stage)
        if any(relative.as_posix() == k or relative.as_posix().startswith(k + "/") for k in keep):
            continue
        if relative.parts[0] in {".build"}:
            continue
        if not (scratch / relative).exists() and not (scratch / relative).is_symlink():
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--check", action="store_true", help="only verify that every patch applies")
    args = parser.parse_args()

    # The scratch tree sits beside the stage, on its volume, so the sync copies within one disk.
    STAGE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=STAGE.parent, prefix=".stage-") as scratch_dir:
        scratch = Path(scratch_dir)
        count = stage_sources(scratch)
        applied = apply_patches(scratch)
        verified_catalog()
        if args.check:
            print(f"{len(applied)} patches apply to {count} upstream files")
            return
        stage_template(scratch)
        substituted = apply_substitutions(scratch)
        rewrite_chart_bodies(scratch)
        stage_resources(scratch)
        stage_launcher_icon(scratch)
        STAGE.mkdir(parents=True, exist_ok=True)
        sync(scratch, STAGE)
        stage_vendored(STAGE)
    print(
        f"staged {count} upstream files, {len(applied)} patches, {substituted} files substituted → {STAGE}"
    )


if __name__ == "__main__":
    sys.exit(main())
