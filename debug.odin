package main

import "core:fmt"
import "core:strings"

// Column data colors (normal) and header colors (inverted: black on bright bg).
DISASM_C0 :: "\033[96m" // offset: bright cyan
DISASM_C0H :: "\033[30;106m"
DISASM_C1 :: "\033[95m" // line: bright magenta
DISASM_C1H :: "\033[30;105m"
DISASM_C2 :: "\033[93m" // opcode: bright yellow
DISASM_C2H :: "\033[30;103m"
DISASM_C3 :: "\033[92m" // index: pool idx, slot, jump from, etc.
DISASM_C3H :: "\033[30;102m"
DISASM_C4 :: "\033[94m" // value: pool value, jump target, etc.
DISASM_C4H :: "\033[30;104m"
DISASM_RS :: "\033[0m"
DISASM_CHUNK_TITLE :: "\033[37;41m" // chunk name line: white fg on red bg

disassemble_chunk :: proc(chunk: ^Chunk, name: string) {
	when WASM {
		wasm_disasm_append_chunk(chunk, name)
	} else {
		b := strings.builder_make(context.temp_allocator)
		disassemble_chunk_into(&b, chunk, name, true, false)
		fmt.print(strings.to_string(b))
	}
}

// wasm_compact: when true with ansi, same spacing as plain WASM (no leading newline before first "==";
// no trailing newline after reset) so wasm_disasm_append_chunk can separate chunks with a single \n.
disassemble_chunk_into :: proc(
	b: ^strings.Builder,
	chunk: ^Chunk,
	name: string,
	ansi: bool,
	wasm_compact: bool,
) {
	if ansi {
		if wasm_compact {
			fmt.sbprintf(b, "%s%s%s\n", DISASM_CHUNK_TITLE, name, DISASM_RS)
		} else {
			fmt.sbprintf(b, "\n%s%s%s\n", DISASM_CHUNK_TITLE, name, DISASM_RS)
		}
		disasm_write_column_header(b)
	} else {
		fmt.sbprintf(b, "== %s ==\n", name)
		fmt.sbprintf(b, "%-4s %-5s%-16s%-8s%-8s\n", "PC", "Line", "Opcode", "Idx", "Value")
	}

	offset := 0
	for offset < len(chunk.code) {
		offset = disassemble_instruction_into(b, chunk, offset, ansi)
	}

	if ansi {
		fmt.sbprintf(b, "\033[0m")
		if !wasm_compact {
			strings.write_byte(b, '\n')
		}
	}
}

disasm_write_column_header :: proc(b: ^strings.Builder) {
	fmt.sbprintf(
		b,
		"%s%-4s %s%s%-5s%s%s%-16s%s%s%-8s%s%s%-8s%s\n",
		DISASM_C0H,
		"PC",
		DISASM_RS,
		DISASM_C1H,
		"Line",
		DISASM_RS,
		DISASM_C2H,
		"Opcode",
		DISASM_RS,
		DISASM_C3H,
		"Idx",
		DISASM_RS,
		DISASM_C4H,
		"Value",
		DISASM_RS,
	)
}

// line5 must be exactly 5 runes: either "   | " or "% 4d " style (space-padded line number + space).
disasm_emit_row :: proc(
	b: ^strings.Builder,
	ansi: bool,
	offset: int,
	line5: string,
	op16: string,
	op_idx: string,
	op_val: string,
) {
	if ansi {
		fmt.sbprintf(
			b,
			"%s%04d %s%s%s%s%s%-16s%s%s%-8s%s%s%-8s%s\n",
			DISASM_C0,
			offset,
			DISASM_RS,
			DISASM_C1,
			line5,
			DISASM_RS,
			DISASM_C2,
			op16,
			DISASM_RS,
			DISASM_C3,
			op_idx,
			DISASM_RS,
			DISASM_C4,
			op_val,
			DISASM_RS,
		)
	} else {
		fmt.sbprintf(b, "%04d %s%-16s%-8s%-8s\n", offset, line5, op16, op_idx, op_val)
	}
}

disassemble_instruction_into :: proc(
	b: ^strings.Builder,
	chunk: ^Chunk,
	offset: int,
	ansi: bool,
) -> int {
	ip := offset
	line5: string
	if offset > 0 && chunk.lines[offset] == chunk.lines[offset - 1] {
		line5 = "   | "
	} else {
		line5 = fmt.tprintf("% 4d ", chunk.lines[offset])
	}

	op := Op_Code(chunk.code[ip])
	switch (op) {

	case .TRUE,
	     .FALSE,
	     .NIL,
	     .POP,
	     .NOT,
	     .NEGATE,
	     .RETURN,
	     .EQUAL,
	     .GREATER,
	     .LESS,
	     .ADD,
	     .SUBTRACT,
	     .MULTIPLY,
	     .DIVIDE,
	     .PRINT,
	     .CLOSE_UPVALUE,
	     .INHERIT:
		op_s := fmt.tprintf("%v", op)
		disasm_emit_row(b, ansi, offset, line5, op_s, "", "")
		return ip + 1

	case .GET_LOCAL, .SET_LOCAL, .GET_UPVALUE, .SET_UPVALUE, .CALL:
		slot := chunk.code[ip + 1]
		op_s := fmt.tprintf("%v", op)
		disasm_emit_row(b, ansi, offset, line5, op_s, fmt.tprintf("%d", slot), "")
		return ip + 2

	case .CONSTANT,
	     .GET_GLOBAL,
	     .DEFINE_GLOBAL,
	     .SET_GLOBAL,
	     .GET_PROPERTY,
	     .SET_PROPERTY,
	     .GET_SUPER,
	     .CLASS,
	     .METHOD:
		constant := chunk.code[ip + 1]
		op_s := fmt.tprintf("%v", op)
		val := print_value(chunk.constants[constant], true)
		disasm_emit_row(b, ansi, offset, line5, op_s, fmt.tprintf("%d", constant), val)
		return ip + 2

	case .JUMP, .JUMP_IF_FALSE, .LOOP:
		sign := op == .LOOP ? -1 : 1
		jump := u16(chunk.code[ip + 1]) << 8
		jump |= u16(chunk.code[ip + 2])
		op_s := fmt.tprintf("%v", op)
		target := ip + 3 + sign * int(jump)
		disasm_emit_row(
			b,
			ansi,
			offset,
			line5,
			op_s,
			fmt.tprintf("%d", ip),
			fmt.tprintf("%d", target),
		)
		return ip + 3

	case .INVOKE, .SUPER_INVOKE:
		constant := chunk.code[ip + 1]
		arg_count := chunk.code[ip + 2]
		op_s := fmt.tprintf("%v", op)
		val := print_value(chunk.constants[constant], true)
		disasm_emit_row(
			b,
			ansi,
			offset,
			line5,
			op_s,
			fmt.tprintf("%d", constant),
			fmt.tprintf("%v (%d args)", val, arg_count),
		)
		return ip + 3

	case .CLOSURE:
		ip += 1
		constant := chunk.code[ip]
		ip += 1
		op_s := fmt.tprintf("%v", op)
		val := print_value(chunk.constants[constant], true)
		disasm_emit_row(b, ansi, offset, line5, op_s, fmt.tprintf("%d", constant), val)

		function := chunk.constants[constant].(^Obj).variant.(^Obj_Function)

		for j in 0 ..< function.upvalue_count {
			is_local := chunk.code[ip]
			ip += 1
			index := chunk.code[ip]
			ip += 1
			kind := is_local == 1 ? "local" : "upvalue"
			disasm_emit_row(b, ansi, ip - 2, "   | ", "", kind, fmt.tprintf("%d", index))
		}

		return ip
	}
	if ansi {
		op_s := fmt.tprintf("Unknown opcode %v", byte(op))
		disasm_emit_row(b, ansi, offset, line5, "", "", op_s)
	} else {
		fmt.sbprintf(b, "Unknown opcode %v\n", byte(op))
	}
	return ip + 1
}

disassemble_instruction :: proc(chunk: ^Chunk, offset: int) -> int {
	b := strings.builder_make(context.temp_allocator)
	next := disassemble_instruction_into(&b, chunk, offset, true)
	fmt.print(strings.to_string(b))
	return next
}
