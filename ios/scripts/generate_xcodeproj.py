#!/usr/bin/env python3
"""Generate QGram.xcodeproj from the sources on disk.

The project file lists every Swift file explicitly (classic pbxproj, objectVersion
56) so it opens in Xcode 14 and later. Re-run this script after adding or
removing files:

    python3 scripts/generate_xcodeproj.py

Object ids are derived from a hash of each path, so regenerating an unchanged
tree produces an identical project file (no noisy diffs).
"""

from __future__ import annotations

import hashlib
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "QGram"
SOURCE_ROOT = "QGram"
BUNDLE_ID = "fun.qgram.ios"
DEPLOYMENT_TARGET = "16.0"
MARKETING_VERSION = "1.0"
BUILD_VERSION = "1"


def oid(*parts: str) -> str:
    digest = hashlib.sha1("::".join(parts).encode("utf-8")).hexdigest().upper()
    return digest[:24]


def collect() -> tuple[list[str], list[str]]:
    """Returns (swift sources, resources) as paths relative to the repo root."""
    sources: list[str] = []
    resources: list[str] = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, SOURCE_ROOT)):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        rel_dir = os.path.relpath(dirpath, ROOT)
        if rel_dir.endswith(".xcassets") or ".xcassets/" in rel_dir.replace(os.sep, "/"):
            continue
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            rel = os.path.join(rel_dir, name).replace(os.sep, "/")
            if name.endswith(".swift"):
                sources.append(rel)
            elif name.endswith(".xcassets"):
                resources.append(rel)
        for name in list(dirnames):
            if name.endswith(".xcassets"):
                resources.append(os.path.join(rel_dir, name).replace(os.sep, "/"))
                dirnames.remove(name)
    return sources, resources


class Group:
    def __init__(self, name: str, path: str | None = None):
        self.name = name
        self.path = path
        self.children: dict[str, "Group"] = {}
        self.files: list[str] = []

    def add(self, rel_path: str) -> None:
        parts = rel_path.split("/")
        if len(parts) == 1:
            self.files.append(rel_path)
            return
        head, rest = parts[0], "/".join(parts[1:])
        if head not in self.children:
            self.children[head] = Group(head, head)
        self.children[head].add(rest)


def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    return "text"


def main() -> None:
    sources, resources = collect()
    info_plist = f"{SOURCE_ROOT}/Resources/Info.plist"
    entitlements = f"{SOURCE_ROOT}/Resources/QGram.entitlements"
    all_files = sorted(set(sources + resources + [info_plist, entitlements]))

    tree = Group(PROJECT_NAME)
    for path in all_files:
        tree.add(path)

    lines: list[str] = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # PBXBuildFile
    add("")
    add("/* Begin PBXBuildFile section */")
    for path in sources + resources:
        add(
            f"\t\t{oid('buildfile', path)} /* {os.path.basename(path)} in "
            f"{'Sources' if path.endswith('.swift') else 'Resources'} */ = {{isa = PBXBuildFile; "
            f"fileRef = {oid('fileref', path)} /* {os.path.basename(path)} */; }};"
        )
    add("/* End PBXBuildFile section */")

    # PBXFileReference
    add("")
    add("/* Begin PBXFileReference section */")
    add(
        f"\t\t{oid('product')} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.application; includeInIndex = 0; "
        f'path = "{PROJECT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    for path in all_files:
        name = os.path.basename(path)
        add(
            f"\t\t{oid('fileref', path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(path)}; path = {name}; sourceTree = \"<group>\"; }};"
        )
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{oid('frameworks')} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    add("")
    add("/* Begin PBXGroup section */")

    def emit_group(group: Group, prefix: str) -> str:
        group_id = oid("group", prefix or "<root>")
        children: list[tuple[str, str]] = []
        for name in sorted(group.children):
            child = group.children[name]
            child_prefix = f"{prefix}/{name}" if prefix else name
            children.append((emit_group(child, child_prefix), name))
        for file_path in sorted(group.files):
            full = f"{prefix}/{file_path}" if prefix else file_path
            children.append((oid("fileref", full), os.path.basename(file_path)))

        add(f"\t\t{group_id} = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child_id, child_name in children:
            add(f"\t\t\t\t{child_id} /* {child_name} */,")
        add("\t\t\t);")
        if group.path:
            add(f"\t\t\tpath = {group.path};")
        else:
            add(f"\t\t\tname = {group.name};")
        add('\t\t\tsourceTree = "<group>";')
        add("\t\t};")
        return group_id

    products_group = oid("group", "Products")
    root_children = []
    for name in sorted(tree.children):
        child = tree.children[name]
        root_children.append((emit_group(child, name), name))

    add(f"\t\t{products_group} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{oid('product')} /* {PROJECT_NAME}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")

    add(f"\t\t{oid('group', '<root>')} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for child_id, child_name in root_children:
        add(f"\t\t\t\t{child_id} /* {child_name} */,")
    add(f"\t\t\t\t{products_group} /* Products */,")
    add("\t\t\t);")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")
    add("/* End PBXGroup section */")

    # PBXNativeTarget
    add("")
    add("/* Begin PBXNativeTarget section */")
    add(f"\t\t{oid('target')} /* {PROJECT_NAME} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(
        f"\t\t\tbuildConfigurationList = {oid('configlist', 'target')} /* Build configuration "
        f"list for PBXNativeTarget \"{PROJECT_NAME}\" */;"
    )
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{oid('sources')} /* Sources */,")
    add(f"\t\t\t\t{oid('frameworks')} /* Frameworks */,")
    add(f"\t\t\t\t{oid('resources')} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tname = {PROJECT_NAME};")
    add(f"\t\t\tproductName = {PROJECT_NAME};")
    add(f"\t\t\tproductReference = {oid('product')} /* {PROJECT_NAME}.app */;")
    add('\t\t\tproductType = "com.apple.product-type.application";')
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # PBXProject
    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{oid('project')} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{oid('target')} = {{")
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(
        f"\t\t\tbuildConfigurationList = {oid('configlist', 'project')} /* Build configuration "
        f"list for PBXProject \"{PROJECT_NAME}\" */;"
    )
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = ru;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\tru,")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {oid('group', '<root>')};")
    add(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    add('\t\t\tprojectDirPath = "";')
    add('\t\t\tprojectRoot = "";')
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{oid('target')} /* {PROJECT_NAME} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{oid('resources')} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path in resources:
        add(f"\t\t\t\t{oid('buildfile', path)} /* {os.path.basename(path)} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{oid('sources')} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path in sources:
        add(f"\t\t\t\t{oid('buildfile', path)} /* {os.path.basename(path)} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    project_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    project_debug = dict(project_common)
    project_debug.update(
        {
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        }
    )
    project_release = dict(project_common)
    project_release.update(
        {
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        }
    )

    target_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": f"{SOURCE_ROOT}/Resources/QGram.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": BUILD_VERSION,
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{SOURCE_ROOT}/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }

    def emit_config(config_id: str, name: str, settings: dict[str, str]) -> None:
        add(f"\t\t{config_id} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for key in sorted(settings):
            add(f"\t\t\t\t{key} = {settings[key]};")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")

    add("")
    add("/* Begin XCBuildConfiguration section */")
    emit_config(oid("config", "project", "Debug"), "Debug", project_debug)
    emit_config(oid("config", "project", "Release"), "Release", project_release)
    emit_config(oid("config", "target", "Debug"), "Debug", target_common)
    emit_config(oid("config", "target", "Release"), "Release", target_common)
    add("/* End XCBuildConfiguration section */")

    add("")
    add("/* Begin XCConfigurationList section */")
    for scope, comment in (
        ("project", f'Build configuration list for PBXProject "{PROJECT_NAME}"'),
        ("target", f'Build configuration list for PBXNativeTarget "{PROJECT_NAME}"'),
    ):
        add(f"\t\t{oid('configlist', scope)} /* {comment} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{oid('config', scope, 'Debug')} /* Debug */,")
        add(f"\t\t\t\t{oid('config', scope, 'Release')} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {oid('project')} /* Project object */;")
    add("}")

    project_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    if os.path.isdir(project_dir):
        shutil.rmtree(project_dir)
    os.makedirs(os.path.join(project_dir, "xcshareddata", "xcschemes"), exist_ok=True)

    with open(os.path.join(project_dir, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{oid('target')}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{oid('target')}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{oid('target')}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    scheme_path = os.path.join(project_dir, "xcshareddata", "xcschemes", f"{PROJECT_NAME}.xcscheme")
    with open(scheme_path, "w", encoding="utf-8") as handle:
        handle.write(scheme)

    print(f"{PROJECT_NAME}.xcodeproj generated: {len(sources)} Swift files, {len(resources)} resources")


if __name__ == "__main__":
    main()
