#!/usr/bin/env python3
"""Patch the unzipped Godot 4.6.1 Android build template to wire in
Firebase Crashlytics NDK. Called from .github/workflows/* after the
android_source.zip extraction step.

Three injection points:

1. settings.gradle — declare google-services + crashlytics plugin
   versions in the pluginManagement.plugins block.

2. build.gradle (root, which IS the app module in Godot's single-module
   layout) — apply the two plugins.

3. build.gradle dependencies block — add Firebase BOM, Crashlytics NDK,
   and Analytics (Crashlytics surfaces richer context when Analytics is
   present, per Firebase docs).

Fails loudly with exit code 1 if any expected anchor string is missing —
indicates Godot updated the template format and we need to revisit.
Idempotent: re-running on an already-patched file is a no-op, NOT an
error (matters because some CI flows may run this step twice).
"""
import sys
from pathlib import Path

# Firebase plugin + BOM versions. Update together when bumping.
GMS_GOOGLE_SERVICES_VERSION = "4.4.2"
CRASHLYTICS_PLUGIN_VERSION = "3.0.2"
FIREBASE_BOM_VERSION = "33.7.0"


def patch_settings_gradle(path: Path) -> None:
    """Add firebase plugin versions to pluginManagement.plugins block."""
    src = path.read_text()
    marker = "id 'com.google.gms.google-services'"
    if marker in src:
        print(f"  {path.name}: already patched, skipping")
        return

    anchor = "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion"
    if anchor not in src:
        raise SystemExit(
            f"FATAL: anchor not found in {path}: {anchor!r}\n"
            f"Godot Android template format may have changed."
        )

    injection = (
        f"{anchor}\n"
        f"        id 'com.google.gms.google-services' version '{GMS_GOOGLE_SERVICES_VERSION}' apply false\n"
        f"        id 'com.google.firebase.crashlytics' version '{CRASHLYTICS_PLUGIN_VERSION}' apply false"
    )
    new_src = src.replace(anchor, injection, 1)
    path.write_text(new_src)
    print(f"  {path.name}: added firebase plugin declarations")


def patch_build_gradle(path: Path) -> None:
    """Apply firebase plugins (top plugins block) + add deps."""
    src = path.read_text()

    # ------ Apply plugins ------
    if "id 'com.google.gms.google-services'" in src:
        print(f"  {path.name}: plugins already applied, skipping plugin section")
    else:
        plugins_anchor = "id 'org.jetbrains.kotlin.android'"
        if plugins_anchor not in src:
            raise SystemExit(f"FATAL: plugins anchor not found in {path}: {plugins_anchor!r}")
        plugins_injection = (
            f"{plugins_anchor}\n"
            "    id 'com.google.gms.google-services'\n"
            "    id 'com.google.firebase.crashlytics'"
        )
        src = src.replace(plugins_anchor, plugins_injection, 1)
        print(f"  {path.name}: applied firebase plugins")

    # ------ Add dependencies ------
    if "firebase-crashlytics-ndk" in src:
        print(f"  {path.name}: deps already added, skipping deps section")
    else:
        # The anchor is the start of the "Godot user plugins remote
        # dependencies" comment block — well-known marker, unlikely to
        # appear twice. Inject our deps BEFORE this comment so they end
        # up at the top of dependencies, before any user-plugin deps.
        deps_anchor = "    // Godot user plugins remote dependencies"
        if deps_anchor not in src:
            raise SystemExit(f"FATAL: deps anchor not found in {path}: {deps_anchor!r}")
        deps_injection = (
            "    // Firebase Crashlytics — added by Not_This_Again CI\n"
            f"    implementation platform('com.google.firebase:firebase-bom:{FIREBASE_BOM_VERSION}')\n"
            "    implementation 'com.google.firebase:firebase-crashlytics-ndk'\n"
            "    implementation 'com.google.firebase:firebase-analytics'\n"
            "\n"
            f"{deps_anchor}"
        )
        src = src.replace(deps_anchor, deps_injection, 1)
        print(f"  {path.name}: added Firebase BOM + Crashlytics NDK + Analytics deps")

    path.write_text(src)


def main(android_build_dir: str) -> None:
    root = Path(android_build_dir)
    if not root.is_dir():
        raise SystemExit(f"FATAL: {root} is not a directory")

    settings = root / "settings.gradle"
    build = root / "build.gradle"
    for f in (settings, build):
        if not f.is_file():
            raise SystemExit(f"FATAL: {f} missing — wrong directory?")

    print(f"Patching Godot Android template at {root}/ for Firebase Crashlytics:")
    patch_settings_gradle(settings)
    patch_build_gradle(build)
    print("Done.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <android_build_dir>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
