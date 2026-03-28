package main

import "core:fmt"

when !WASM {
	main :: proc() {
		fmt.println(
			"Interpreter tests: `make test` or `odin test . -define:ODIN_TEST_THREADS=1` (see tests.odin).",
		)
	}
}
