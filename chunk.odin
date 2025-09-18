package main

import "core:fmt"

Op_Code :: enum u8 {
	// literals
	TRUE,
	FALSE,
	NIL,

	// stack
	CONSTANT,
	POP,

	// locals
	GET_LOCAL,
	SET_LOCAL,

	// globals
	GET_GLOBAL,
	DEFINE_GLOBAL,
	SET_GLOBAL,

	// closures
	CLOSURE,
	GET_UPVALUE,
	SET_UPVALUE,
	CLOSE_UPVALUE,

	// classes
	GET_PROPERTY,
	SET_PROPERTY,
	GET_SUPER,
	INVOKE,
	SUPER_INVOKE,
	CLASS,
	INHERIT,
	METHOD,

	// value comparisons
	EQUAL,
	GREATER,
	LESS,

	// arithmetic
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,

	// jumps
	JUMP,
	JUMP_IF_FALSE,
	LOOP,

	// functions
	CALL,

	// other
	NOT,
	NEGATE,
	PRINT,
	RETURN,
}

Chunk :: struct {
	code:      [dynamic]byte,
	lines:     [dynamic]int,
	constants: [dynamic]Value,
}

chunk: Chunk

init_chunk :: proc(chunk: ^Chunk) {
	chunk.code = make([dynamic]byte)
	chunk.lines = make([dynamic]int)
	chunk.constants = make([dynamic]Value)
}

free_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.lines)
	delete(chunk.constants)
}

write_chunk :: proc(chunk: ^Chunk, b: byte, line: int) {
	append(&chunk.code, b)
	append(&chunk.lines, line)
}

add_constant :: proc(chunk: ^Chunk, value: Value) -> int {
	vm_push(value)
	append(&chunk.constants, value)
	vm_pop()
	return len(chunk.constants) - 1
}
