package main

WASM :: #config(WASM, false)
LOX_TRACE_GC :: #config(LOX_TRACE_GC, false)
// Verbose intern-table logging on JS (table_find_string + new_string); use build_wasm_debug.sh or -define:LOX_TABLE_DEBUG=true
LOX_TABLE_DEBUG :: #config(LOX_TABLE_DEBUG, false)
