#!/usr/bin/env bash
set -euo pipefail
mkdir -p web
odin_js="$(odin root)/core/sys/wasm/js/odin.js"
cp "$odin_js" odin.js
# Verbose intern-table logging: ./build_wasm_debug.sh or add -define:LOX_TABLE_DEBUG=true
odin build . -define:WASM=true -target:js_wasm32 -out:index.wasm -o:speed
