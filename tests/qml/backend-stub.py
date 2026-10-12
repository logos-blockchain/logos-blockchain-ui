#!/usr/bin/env python3
"""Writes a QML stand-in for the generated Logos.BlockchainBackend module.

The real module is built from src/BlockchainBackend.rep and only exists inside
the app, so QML tests and qmllint can't see its enums. This copies every ENUM
from the .rep into a plain QML type, so `BlockchainBackend.BlendActive` and
friends resolve, and a misspelled value is an error.

    backend-stub.py <BlockchainBackend.rep> <output dir for the import path>
"""
import os
import re
import sys

rep_path, out_root = sys.argv[1], sys.argv[2]
enums = re.findall(r"ENUM\s+(\w+)\s*\{([^}]*)\}", open(rep_path).read())
if not enums:
    sys.exit(f"no ENUM found in {rep_path}")

module_dir = os.path.join(out_root, "Logos", "BlockchainBackend")
os.makedirs(module_dir, exist_ok=True)
lines = ["import QtQuick", "", "QtObject {"]
for name, body in enums:
    values = [v.strip() for v in body.replace("\n", " ").split(",") if v.strip()]
    lines.append(f"    enum {name} {{ {', '.join(values)} }}")
lines.append("}")
with open(os.path.join(module_dir, "BlockchainBackend.qml"), "w") as f:
    f.write("\n".join(lines) + "\n")
with open(os.path.join(module_dir, "qmldir"), "w") as f:
    f.write("module Logos.BlockchainBackend\nBlockchainBackend 1.0 BlockchainBackend.qml\n")
