package main

import "core:fmt"
import "core:strings"

disassemble_chunk :: proc(chunk: ^Chunk, name: string) {
	fmt.printf("\n\033[93m== %s ==\033[0m\n", name)
	fmt.print("\033[96m")
	defer fmt.print("\033[0m\n")

	offset := 0
	for offset < len(chunk.code) {
		offset = disassemble_instruction(chunk, offset)
	}
}

disassemble_instruction :: proc(chunk: ^Chunk, offset: int) -> int {
	fmt.printf("%04d ", offset)
	offset := offset

	if offset > 0 && chunk.lines[offset] == chunk.lines[offset - 1] {
		fmt.printf("   | ")
	} else {
		fmt.printf("% 4d ", chunk.lines[offset])
	}

	op := Op_Code(chunk.code[offset])
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
		// 1 byte instructions
		fmt.printf("%-16v\n", op)
		return offset + 1

	case .GET_LOCAL, .SET_LOCAL, .GET_UPVALUE, .SET_UPVALUE, .CALL:
		// 2 byte instructions
		slot := chunk.code[offset + 1]
		fmt.printf("%-16v %d\n", op, slot)
		return offset + 2

	case .CONSTANT,
	     .GET_GLOBAL,
	     .DEFINE_GLOBAL,
	     .SET_GLOBAL,
	     .GET_PROPERTY,
	     .SET_PROPERTY,
	     .GET_SUPER,
	     .CLASS,
	     .METHOD:
		// constant instructions
		constant := chunk.code[offset + 1]
		fmt.printf("%-16v %d ", op, constant)
		fmt.print(print_value(chunk.constants[constant]))
		fmt.printf("\n")
		return offset + 2

	case .JUMP, .JUMP_IF_FALSE, .LOOP:
		// jump instructions
		sign := op == .LOOP ? -1 : 1
		jump := u16(chunk.code[offset + 1]) << 8
		jump |= u16(chunk.code[offset + 2])
		fmt.printf("%16-v %4d -> %d\n", op, offset, offset + 3 + sign * int(jump))
		return offset + 3

	case .INVOKE, .SUPER_INVOKE:
		// invoke instructions
		constant := chunk.code[offset + 1]
		arg_count := chunk.code[offset + 2]
		fmt.printf("%-16v (%d args) %d ", op, arg_count, constant)
		fmt.print(print_value(chunk.constants[constant]))
		fmt.printf("\n")
		return offset + 3

	case .CLOSURE:
		offset += 1
		constant := chunk.code[offset]
		offset += 1
		fmt.printf("%-16v %d ", op, constant)
		fmt.print(print_value(chunk.constants[constant]))
		fmt.printf("\n")

		function := chunk.constants[constant].(^Obj).variant.(^Obj_Function)

		for j in 0 ..< function.upvalue_count {
			is_local := chunk.code[offset]
			offset += 1
			index := chunk.code[offset]
			offset += 1
			fmt.printf(
				"%04d      |                     %s %d\n",
				offset - 2,
				is_local == 1 ? "local" : "upvalue",
				index,
			)
		}

		return offset
	}
	fmt.printf("\033[95mUnknown opcode %v\033[0m\n", byte(op))
	return offset + 1
}
