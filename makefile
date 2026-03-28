# -default-to-panic-allocator also defaults the TEMPORARY allocator to the panic allocator!

# Single-threaded: all tests share the global `vm` (see vm.odin). Parallel `odin test` races.
# Memory tracking off: test runner's per-thread allocator clashes with VM heap frees (noisy bad-free reports).
test:
	odin test . -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false

run:
	odin run . -sanitize:address

debug:
	odin run . -sanitize:address -debug

watch:
	watchexec -c -e odin -w . 'make run'

wasm:
	./build_wasm.sh

wasm-debug:
	./build_wasm_debug.sh