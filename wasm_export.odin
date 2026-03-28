package main

import "base:runtime"
import "core:mem"
import "core:strings"

when WASM {
	INPUT_SCRATCH_MAX :: 1024 * 1024
	OUT_ARENA_BYTES :: 512 * 1024

	input_scratch: [INPUT_SCRATCH_MAX]u8
	out_backing: [OUT_ARENA_BYTES]byte
	wasm_out_arena: mem.Arena
	wasm_arena_inited: bool
	last_out: string
	last_disasm: string
	disasm_builder: strings.Builder
	wasm_disasm_got_chunk: bool

	main :: proc() {}

	wasm_disasm_reset :: proc() {
		wasm_disasm_got_chunk = false
		out_alloc := mem.arena_allocator(&wasm_out_arena)
		disasm_builder = strings.builder_make(out_alloc)
	}

	wasm_disasm_append_chunk :: proc(chunk: ^Chunk, name: string) {
		b := &disasm_builder
		if wasm_disasm_got_chunk {
			strings.write_string(b, "\n")
		}
		wasm_disasm_got_chunk = true
		disassemble_chunk_into(b, chunk, name, true, true)
	}

	wasm_disasm_finalize :: proc() {
		last_disasm = strings.to_string(disasm_builder)
	}

	wasm_disasm_discard :: proc() {
		last_disasm = ""
	}

	@(export)
	lox_scratch_base :: proc() -> u32 {
		return u32(uintptr(raw_data(input_scratch[:])))
	}

	@(export)
	lox_scratch_cap :: proc() -> u32 {
		return INPUT_SCRATCH_MAX
	}

	@(export)
	lox_last_out_ptr :: proc() -> u32 {
		if len(last_out) == 0 {
			return 0
		}
		return u32(uintptr(raw_data(last_out)))
	}

	@(export)
	lox_last_out_len :: proc() -> u32 {
		return u32(len(last_out))
	}

	@(export)
	lox_last_disasm_ptr :: proc() -> u32 {
		if len(last_disasm) == 0 {
			return 0
		}
		return u32(uintptr(raw_data(last_disasm)))
	}

	@(export)
	lox_last_disasm_len :: proc() -> u32 {
		return u32(len(last_disasm))
	}

	// 0 = OK, 1 = COMPILE_ERROR, 2 = RUNTIME_ERROR
	@(export)
	lox_run :: proc(source_ptr: u32, source_len: u32) -> u8 {
		// Exported procs invoked from JS don't get _start's context; append/make need a real allocator.
		context = runtime.default_context()

		if !wasm_arena_inited {
			mem.arena_init(&wasm_out_arena, out_backing[:])
			wasm_arena_inited = true
		}
		mem.arena_free_all(&wasm_out_arena)
		last_out = ""
		last_disasm = ""

		if source_len > INPUT_SCRATCH_MAX {
			return 1
		}
		n := int(source_len)
		p := cast(^u8)(uintptr(source_ptr))
		src_slice := mem.slice_ptr(p, n)
		source := string(src_slice)

		res := interpret(source)

		out_alloc := mem.arena_allocator(&wasm_out_arena)
		b := strings.builder_make(out_alloc)
		for line, i in vm.print_output {
			if i > 0 {
				strings.write_byte(&b, '\n')
			}
			strings.write_string(&b, line)
		}
		if len(vm.error_output) > 0 {
			if len(vm.print_output) > 0 {
				strings.write_byte(&b, '\n')
			}
			for line, i in vm.error_output {
				if i > 0 {
					strings.write_byte(&b, '\n')
				}
				strings.write_string(&b, line)
			}
		}
		last_out = strings.to_string(b)

		return u8(res)
	}
}
