# -default-to-panic-allocator also defaults the TEMPORARY allocator to the panic allocator!

run:
	odin run . -sanitize:address

debug:
	odin run . -sanitize:address -debug

watch:
	watchexec -c -e odin -w . 'make run'