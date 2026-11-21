#!/usr/bin/env python3
# =============================================================================
#                  SP BOUCHER | SOFTWARE & RESEARCH
#             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
# =============================================================================
#
# PROJECT METADATA
# -----------------------------------------------------------------------------
# Project          : ORIX Clean
# File             : Scripts/localize.py
# Description      : Extracts every L("…") key from the sources and writes
#                    App/Resources/Localizable.xcstrings (en + fr-CA) from
#                    Scripts/translations-fr.json. Fails when a key has no
#                    French translation (use --keys to list keys).
# Module           : Scripts
# Repository       : https://git.spboucher.ai/orix-clean
# Created          : 2026-11-21
# Last Modified    : 2026-11-21
#
# =============================================================================
# AUTHOR & PROFESSIONAL AFFILIATION
# =============================================================================
#
# Author           : Simon-Pierre Boucher
# Position         : Professor of Finance
# Institution      : Université du Québec en Outaouais (UQO)
# Department       : Département des sciences administratives
# Organization     : SP Boucher
#
# Website          : https://spboucher.ai
# Git              : https://git.spboucher.ai
#
# =============================================================================
# OFFICIAL CONTACT DIRECTORY
# =============================================================================
#
# General          : info@spboucher.ai
# Professional     : contact@spboucher.ai
# Direct           : simon@spboucher.ai
# Research         : research@spboucher.ai
# Development      : dev@spboucher.ai
# Support          : support@spboucher.ai
# Security/Admin   : admin@spboucher.ai
# Notifications    : notifications@spboucher.ai
#
# Preferred Contact: support@spboucher.ai
#
# =============================================================================
# COPYRIGHT & INTELLECTUAL PROPERTY
# =============================================================================
#
# Copyright (c) 2026
# Simon-Pierre Boucher
#
# All rights reserved where applicable.
#
# This file is governed by the applicable project license,
# copyright notices, institutional agreements and relevant law.
#
# Unless expressly authorized by the applicable license or
# rights holder, copying, redistribution, sublicensing,
# publication and commercial exploitation are not permitted.
#
# Existing third-party rights and notices remain unaffected.
#
# =============================================================================
# CONFIDENTIALITY & SECURITY
# =============================================================================
#
# Classification   : Public
# Distribution     : Public repository; use is governed by the project license
# Security Contact : admin@spboucher.ai
#
# Access to this source does not independently grant permission
# to redistribute or disclose confidential materials.
#
# Do not embed credentials, private keys, access tokens,
# certificates or confidential personal information.
#
# =============================================================================
# LICENSE & MAINTENANCE
# =============================================================================
#
# License          : Proprietary, all rights reserved (see license file)
# License File     : LICENSE
# Maintainer       : Simon-Pierre Boucher
# Technical Contact: dev@spboucher.ai
#
# =============================================================================
# END OF SP BOUCHER SOURCE HEADER
# =============================================================================

import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PATTERN = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
# Keys passed to L() through a variable.
EXTRA = ["Analyze", "Clean", "Track", "Any age", "Not modified for 30 days", "Not modified for 6 months", "Not modified for 1 year",
         "Not modified for 2 years", "Modified in the last 7 days", "Scan Downloads", "Scan Home Folder", "Find duplicates (1 MB+)",
         "Analyze caches and logs", "Analyze developer data", "Collect downloads older than 90 days", "Review and confirm",
         "Move to Trash", "Create report"]
INFO = {
    "NSDesktopFolderUsageDescription": "ORIX Clean mesure les fichiers de votre dossier Bureau quand vous l’analysez. Rien ne quitte ce Mac.",
    "NSDocumentsFolderUsageDescription": "ORIX Clean mesure les fichiers de votre dossier Documents quand vous l’analysez. Rien ne quitte ce Mac.",
    "NSDownloadsFolderUsageDescription": "ORIX Clean mesure les fichiers de votre dossier Téléchargements quand vous l’analysez. Rien ne quitte ce Mac.",
    "NSRemovableVolumesUsageDescription": "ORIX Clean mesure les fichiers des volumes amovibles quand vous les analysez. Rien ne quitte ce Mac.",
    "NSNetworkVolumesUsageDescription": "ORIX Clean mesure les fichiers des volumes réseau quand vous les analysez. Rien ne quitte ce Mac.",
}

def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")

def keys():
    found = set(EXTRA)
    for base in ("App/Sources", "Packages/ORIXCleanCore/Sources/ORIXCleanCore"):
        for f in sorted((ROOT / base).rglob("*.swift")):
            for m in PATTERN.finditer(f.read_text()):
                found.add(unescape(m.group(1)))
    return sorted(found)

def placeholders(s):
    return re.findall(r"%(?:\d+\$)?[@d]", s)

def main():
    ks = keys()
    if "--keys" in sys.argv:
        print(json.dumps(ks, ensure_ascii=False, indent=0))
        return 0
    fr = json.loads((ROOT / "Scripts/translations-fr.json").read_text())
    missing = [k for k in ks if k not in fr]
    bad = [k for k in ks if k in fr and sorted(p[-1] for p in placeholders(k)) != sorted(p[-1] for p in placeholders(fr[k]))]
    if missing or bad:
        for k in missing: print("MISSING:", k)
        for k in bad: print("PLACEHOLDERS DIFFER:", k, "=>", fr[k])
        return 1
    strings = {}
    for k in ks:
        strings[k] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": k}},
                                        "fr-CA": {"stringUnit": {"state": "translated", "value": fr[k]}}}}
    out = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    (ROOT / "App/Resources/Localizable.xcstrings").write_text(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    info = {k: {"localizations": {"fr-CA": {"stringUnit": {"state": "translated", "value": v}}}} for k, v in INFO.items()}
    (ROOT / "App/Resources/InfoPlist.xcstrings").write_text(json.dumps({"sourceLanguage": "en", "strings": info, "version": "1.0"}, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    stale = [k for k in fr if k not in ks]
    print(f"{len(ks)} keys written (en, fr-CA); {len(stale)} unused translations")
    return 0

sys.exit(main())
