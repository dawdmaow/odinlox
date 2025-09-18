package main

import "core:fmt"
import "core:strconv"
import "core:strings"

Parser :: struct {
	current, previous:     Token,
	had_error, panic_mode: bool,
}

Precedence :: enum {
	None,
	Assignment,
	Or,
	And,
	Equality,
	Comparison,
	Term,
	Factor,
	Unary,
	Call,
	Primary,
}

Parse_Fn :: proc(had_error: bool)

Parse_Rule :: struct {
	prefix, infix: Parse_Fn,
	precedence:    Precedence,
}

Local :: struct {
	name:        Token,
	depth:       int,
	is_captured: bool,
}

Upvalue :: struct {
	index:    u8,
	is_local: bool,
}

Function_Kind :: enum {
	Function,
	Initializer,
	Method,
	Script,
}

Compiler :: struct {
	enclosing:   ^Compiler,
	function:    ^Obj_Function,
	kind:        Function_Kind,
	locals:      [max(u8)]Local,
	local_count: int,
	upvalues:    [max(u8)]Upvalue,
	scope_depth: int,
}

Class_Compiler :: struct {
	enclosing:      ^Class_Compiler,
	has_superclass: bool,
}

parser: Parser
current: ^Compiler
current_class: ^Class_Compiler

current_chunk :: proc() -> ^Chunk {
	return &current.function.chunk
}

error_at :: proc(token: ^Token, message: string) {
	if (parser.panic_mode) do return
	parser.panic_mode = true

	sb := strings.builder_make()

	fmt.sbprintf(&sb, "[line %v] Error", token.line)

	if (token.kind == .EOF) {
		fmt.sbprintf(&sb, " at end")
	} else if (token.kind != .ERROR) {
		fmt.sbprintf(&sb, " at '%.*s'", len(token.lexeme), token.lexeme)
	}

	fmt.sbprintf(&sb, ": %s", message)
	msg := strings.to_string(sb)

	fmt.print("\x1b[31m") // start red
	defer fmt.print("\x1b[0m") // end red
	fmt.eprintln(msg)
	append(&vm.error_output, msg)

	parser.had_error = true
}

error :: proc(message: string) {
	error_at(&parser.previous, message)
}

error_at_current :: proc(message: string) {
	error_at(&parser.current, message)
}

advance :: proc() {
	parser.previous = parser.current

	for {
		parser.current = scan_token()
		if (parser.current.kind != .ERROR) do break

		error_at_current(parser.current.lexeme)
	}
}

consume :: proc(type: Token_Kind, message: string) {
	if (parser.current.kind == type) {
		advance()
		return
	}

	error_at_current(message)
}
check :: proc(type: Token_Kind) -> bool {
	return parser.current.kind == type
}

match :: proc(type: Token_Kind) -> bool {
	if !check(type) do return false
	advance()
	return true
}

emit_byte :: proc(byte: byte) {
	write_chunk(current_chunk(), byte, parser.previous.line)
}

emit_bytes :: proc(byte1: byte, byte2: byte) {
	emit_byte(byte1)
	emit_byte(byte2)
}

emit_loop :: proc(loopStart: int) {
	emit_byte(byte(Op_Code.LOOP))

	offset := len(current_chunk().code) - loopStart + 2
	if (offset > int(max(u16))) do error("Loop body too large.")

	emit_byte(byte((offset >> 8) & 0xff))
	emit_byte(byte(offset & 0xff))
}

emit_jump :: proc(instruction: byte) -> int {
	emit_byte(instruction)
	emit_byte(0xff)
	emit_byte(0xff)
	return len(current_chunk().code) - 2
}

emit_return :: proc() {
	if (current.kind == .Initializer) {
		emit_bytes(byte(Op_Code.GET_LOCAL), 0)
	} else {
		emit_byte(byte(Op_Code.NIL))
	}

	emit_byte(byte(Op_Code.RETURN))
}

make_constant :: proc(value: Value) -> byte {
	constant := add_constant(current_chunk(), value)
	if (constant > int(max(u8))) {
		error("Too many constants in one chunk.")
		return 0
	}

	return byte(constant)
}

emit_constant :: proc(value: Value) {
	emit_bytes(byte(Op_Code.CONSTANT), make_constant(value))
}

patch_jump :: proc(offset: int) {
	jump := len(current_chunk().code) - offset - 2

	if (jump > int(max(u16))) {
		error("Too much code to jump over.")
	}

	current_chunk().code[offset] = byte((jump >> 8) & 0xff)
	current_chunk().code[offset + 1] = byte(jump & 0xff)
}

init_compiler :: proc(compiler: ^Compiler, kind: Function_Kind) {
	compiler.enclosing = current
	compiler.function = nil
	compiler.kind = kind
	compiler.function = new_function()
	current = compiler
	if (kind != .Script) {
		current.function.name = copy_string(parser.previous.lexeme)
	}

	local := &current.locals[current.local_count]
	current.local_count += 1
	local.is_captured = false

	if (kind != .Function) {
		local.name.lexeme = "this"
	} else {
		local.name.lexeme = ""
	}
}

end_compiler :: proc() -> ^Obj_Function {
	emit_return()
	function := current.function

	when true {
		if (!parser.had_error) {
			disassemble_chunk(
				current_chunk(),
				function.name != nil ? function.name.chars : "<script>",
			)
		}
	}
	current = current.enclosing
	return function
}

begin_scope :: proc() {
	current.scope_depth += 1
}

end_scope :: proc() {
	current.scope_depth -= 1

	for (current.local_count > 0 &&
		    current.locals[current.local_count - 1].depth > current.scope_depth) {
		if (current.locals[current.local_count - 1].is_captured) {
			emit_byte(byte(Op_Code.CLOSE_UPVALUE))
		} else {
			emit_byte(byte(Op_Code.POP))
		}
		current.local_count -= 1
	}
}

identifier_constant :: proc(name: Token) -> byte {
	return make_constant(&copy_string(name.lexeme).obj)
}

identifiers_equal :: proc(a, b: Token) -> bool {
	return a.lexeme == b.lexeme
}

resolve_local :: proc(compiler: ^Compiler, name: Token) -> int {
	for i := compiler.local_count - 1; i >= 0; i -= 1 {
		local := &compiler.locals[i]
		if (identifiers_equal(name, local.name)) {
			if (local.depth == -1) {
				error("Can't read local variable in its own initializer.")
			}
			return i
		}
	}

	return -1
}

add_upvalue :: proc(compiler: ^Compiler, index: u8, is_local: bool) -> (result: int) {
	upvalue_count := compiler.function.upvalue_count

	for i in 0 ..< upvalue_count {
		upvalue := &compiler.upvalues[i]
		if (upvalue.index == index && upvalue.is_local == is_local) {
			return i
		}
	}

	if (upvalue_count == U8_COUNT) {
		error("Too many closure variables in function.")
		return 0
	}

	compiler.upvalues[upvalue_count].is_local = is_local
	compiler.upvalues[upvalue_count].index = index
	result = compiler.function.upvalue_count
	compiler.function.upvalue_count += 1
	return
}

resolve_upvalue :: proc(compiler: ^Compiler, name: Token) -> (result: int) {
	if (compiler.enclosing == nil) {
		return -1
	}

	local := resolve_local(compiler.enclosing, name)
	if (local != -1) {
		compiler.enclosing.locals[local].is_captured = true
		return add_upvalue(compiler, u8(local), true)
	}

	upvalue := resolve_upvalue(compiler.enclosing, name)
	if (upvalue != -1) {
		return add_upvalue(compiler, u8(upvalue), false)
	}

	return -1
}

add_local :: proc(name: Token) {
	if (current.local_count == U8_COUNT) {
		error("Too many local variables in function.")
		return
	}

	local := &current.locals[current.local_count]
	current.local_count += 1
	local.name = name
	local.depth = -1
	local.is_captured = false
}

declare_variable :: proc() {
	if (current.scope_depth == 0) {
		return
	}

	name := &parser.previous

	for i := current.local_count - 1; i >= 0; i -= 1 {
		local := &current.locals[i]
		if (local.depth != -1 && local.depth < current.scope_depth) {
			break
		}

		if (identifiers_equal(name^, local.name)) {
			error("Already a variable with this name in this scope.")
		}
	}

	add_local(name^)
}

parse_variable :: proc(error_msg: string) -> byte {
	consume(.IDENTIFIER, error_msg)

	declare_variable()
	if (current.scope_depth > 0) do return 0

	return identifier_constant(parser.previous)
}

mark_initialized :: proc() {
	if (current.scope_depth == 0) do return
	current.locals[current.local_count - 1].depth = current.scope_depth
}

define_variable :: proc(global: byte) {
	if (current.scope_depth > 0) {
		mark_initialized()
		return
	}

	emit_bytes(byte(Op_Code.DEFINE_GLOBAL), global)
}

//< Global Variables define-variable
//> Calls and Functions argument-list
argument_list :: proc() -> u8 {
	arg_count := u8(0)
	if !check(.RIGHT_PAREN) {
		for {
			expression()
			if arg_count == 255 {
				error("Can't have more than 255 arguments.")
			}
			arg_count += 1
			if !match(.COMMA) do break
		}
	}
	consume(.RIGHT_PAREN, "Expect ')' after arguments.")
	return arg_count
}

and :: proc(can_assign: bool) {
	end_jump := emit_jump(byte(Op_Code.JUMP_IF_FALSE))

	emit_byte(byte(Op_Code.POP))
	parse_precedence(.And)

	patch_jump(end_jump)
}

binary :: proc(can_assign: bool) {
	operator_kind := parser.previous.kind
	rule := get_rule(operator_kind)
	parse_precedence(Precedence(int(rule.precedence) + 1))

	#partial switch operator_kind {
	case .BANG_EQUAL:
		emit_bytes(byte(Op_Code.EQUAL), byte(Op_Code.NOT))
	case .EQUAL_EQUAL:
		emit_byte(byte(Op_Code.EQUAL))
	case .GREATER:
		emit_byte(byte(Op_Code.GREATER))
	case .GREATER_EQUAL:
		emit_bytes(byte(Op_Code.LESS), byte(Op_Code.NOT))
	case .LESS:
		emit_byte(byte(Op_Code.LESS))
	case .LESS_EQUAL:
		emit_bytes(byte(Op_Code.GREATER), byte(Op_Code.NOT))
	case .PLUS:
		emit_byte(byte(Op_Code.ADD))
	case .MINUS:
		emit_byte(byte(Op_Code.SUBTRACT))
	case .STAR:
		emit_byte(byte(Op_Code.MULTIPLY))
	case .SLASH:
		emit_byte(byte(Op_Code.DIVIDE))
	case:
		unreachable()
	}
}

call :: proc(can_assign: bool) {
	arg_count: u8 = argument_list()
	emit_bytes(byte(Op_Code.CALL), arg_count)
}

dot :: proc(can_assign: bool) {
	consume(.IDENTIFIER, "Expect property name after '.'.")
	name := identifier_constant(parser.previous)

	if can_assign && match(.EQUAL) {
		expression()
		emit_bytes(byte(Op_Code.SET_PROPERTY), name)
	} else if match(.LEFT_PAREN) {
		arg_count := argument_list()
		emit_bytes(byte(Op_Code.INVOKE), name)
		emit_byte(arg_count)
	} else {
		emit_bytes(byte(Op_Code.GET_PROPERTY), name)
	}
}

literal :: proc(can_assign: bool) {
	#partial switch parser.previous.kind {
	case .FALSE:
		emit_byte(byte(Op_Code.FALSE))
	case .NIL:
		emit_byte(byte(Op_Code.NIL))
	case .TRUE:
		emit_byte(byte(Op_Code.TRUE))
	case:
		unreachable()
	}
}

grouping :: proc(can_assign: bool) {
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after expression.")
}

number :: proc(can_assign: bool) {
	value, ok := strconv.parse_f64(parser.previous.lexeme, nil)
	if !ok {
		error("Invalid number.")
	}
	emit_constant(value)
}

or :: proc(can_assign: bool) {
	else_jump := emit_jump(byte(Op_Code.JUMP_IF_FALSE))
	end_jump := emit_jump(byte(Op_Code.JUMP))

	patch_jump(else_jump)
	emit_byte(byte(Op_Code.POP))

	parse_precedence(.Or)
	patch_jump(end_jump)
}

parse_string :: proc(can_assign: bool) {
	emit_constant(&copy_string(parser.previous.lexeme).obj)
}

named_variable :: proc(name: Token, can_assign: bool) {
	get_op, set_op: Op_Code
	arg := resolve_local(current, name)
	if arg != -1 {
		get_op = Op_Code.GET_LOCAL
		set_op = Op_Code.SET_LOCAL
	} else if arg = resolve_upvalue(current, name); arg != -1 {
		get_op = Op_Code.GET_UPVALUE
		set_op = Op_Code.SET_UPVALUE
	} else {
		arg = int(identifier_constant(name))
		get_op = Op_Code.GET_GLOBAL
		set_op = Op_Code.SET_GLOBAL
	}
	assert(arg != -1)

	if can_assign && match(.EQUAL) {
		expression()
		emit_bytes(byte(set_op), byte(arg))
	} else {
		emit_bytes(byte(get_op), byte(arg))
	}
}

variable :: proc(can_assign: bool) {
	named_variable(parser.previous, can_assign)
}

synthetic_token :: proc(text: string) -> Token {
	return Token{lexeme = text}
}

super :: proc(can_assign: bool) {
	if current_class == nil {
		error("Can't use 'super' outside of a class.")
	} else if !current_class.has_superclass {
		error("Can't use 'super' in a class with no superclass.")
	}

	consume(.DOT, "Expect '.' after 'super'.")
	consume(.IDENTIFIER, "Expect superclass method name.")
	name := identifier_constant(parser.previous)

	named_variable(synthetic_token("this"), false)

	if match(.LEFT_PAREN) {
		arg_count := argument_list()
		named_variable(synthetic_token("super"), false)
		emit_bytes(byte(Op_Code.SUPER_INVOKE), name)
		emit_byte(arg_count)
	} else {
		named_variable(synthetic_token("super"), false)
		emit_bytes(byte(Op_Code.GET_SUPER), name)
	}
}

this :: proc(can_assign: bool) {
	if current_class == nil {
		error("Can't use 'this' outside of a class.")
	} else {
		variable(false)
	}
}

unary :: proc(can_assign: bool) {
	operator_kind := parser.previous.kind

	parse_precedence(.Unary)

	#partial switch operator_kind {
	case .BANG:
		emit_byte(byte(Op_Code.NOT))
	case .MINUS:
		emit_byte(byte(Op_Code.NEGATE))
	case:
		unreachable()
	}
}

rules: [Token_Kind]Parse_Rule = {
	.LEFT_PAREN    = Parse_Rule{grouping, call, .Call},
	.RIGHT_PAREN   = {nil, nil, .None},
	.LEFT_BRACE    = {nil, nil, .None},
	.RIGHT_BRACE   = {nil, nil, .None},
	.COMMA         = {nil, nil, .None},
	.DOT           = {nil, dot, .Call},
	.MINUS         = {unary, binary, .Term},
	.PLUS          = {nil, binary, .Term},
	.SEMICOLON     = {nil, nil, .None},
	.SLASH         = {nil, binary, .Factor},
	.STAR          = {nil, binary, .Factor},
	.BANG          = {unary, nil, .None},
	.BANG_EQUAL    = {nil, binary, .Equality},
	.EQUAL         = {nil, nil, .None},
	.EQUAL_EQUAL   = {nil, binary, .Equality},
	.GREATER       = {nil, binary, .Comparison},
	.GREATER_EQUAL = {nil, binary, .Comparison},
	.LESS          = {nil, binary, .Comparison},
	.LESS_EQUAL    = {nil, binary, .Comparison},
	.IDENTIFIER    = {variable, nil, .None},
	.STRING        = {parse_string, nil, .None},
	.NUMBER        = {number, nil, .None},
	.AND           = {nil, and, .And},
	.CLASS         = {nil, nil, .None},
	.ELSE          = {nil, nil, .None},
	.FALSE         = {literal, nil, .None},
	.FOR           = {nil, nil, .None},
	.FUN           = {nil, nil, .None},
	.IF            = {nil, nil, .None},
	.NIL           = {literal, nil, .None},
	.OR            = {nil, or, .Or},
	.PRINT         = {nil, nil, .None},
	.RETURN        = {nil, nil, .None},
	.SUPER         = {super, nil, .None},
	.THIS          = {this, nil, .None},
	.TRUE          = {literal, nil, .None},
	.VAR           = {nil, nil, .None},
	.WHILE         = {nil, nil, .None},
	.ERROR         = {nil, nil, .None},
	.EOF           = {nil, nil, .None},
}

parse_precedence :: proc(precedence: Precedence) {
	advance()
	prefix_rule := get_rule(parser.previous.kind).prefix
	if (prefix_rule == nil) {
		error("Expect expression.")
		return
	}

	can_assign := precedence <= .Assignment
	prefix_rule(can_assign)

	for precedence <= get_rule(parser.current.kind).precedence {
		advance()
		infix_rule := get_rule(parser.previous.kind).infix
		infix_rule(can_assign)
	}

	if (can_assign && match(.EQUAL)) {
		error("Invalid assignment target.")
	}
}

get_rule :: proc(type: Token_Kind) -> ^Parse_Rule {
	return &rules[type]
}

expression :: proc() {
	parse_precedence(.Assignment)
}

block :: proc() {
	for !check(.RIGHT_BRACE) && !check(.EOF) {
		declaration()
	}

	consume(.RIGHT_BRACE, "Expect '}' after block.")
}

function :: proc(kind: Function_Kind) {
	compiler: Compiler
	init_compiler(&compiler, kind)
	begin_scope()

	consume(.LEFT_PAREN, "Expect '(' after function name.")
	if !check(.RIGHT_PAREN) {
		for {
			current.function.arity += 1
			if current.function.arity > 255 {
				error_at_current("Can't have more than 255 parameters.")
			}
			constant := parse_variable("Expect parameter name.")
			define_variable(constant)
			if !match(.COMMA) do break
		}
	}
	consume(.RIGHT_PAREN, "Expect ')' after parameters.")
	consume(.LEFT_BRACE, "Expect '{' before function body.")
	block()

	function := end_compiler()
	emit_bytes(byte(Op_Code.CLOSURE), make_constant(&function.obj))

	for i in 0 ..< function.upvalue_count {
		emit_byte(compiler.upvalues[i].is_local ? 1 : 0)
		emit_byte(compiler.upvalues[i].index)
	}
}

method :: proc() {
	consume(.IDENTIFIER, "Expect method name.")
	constant := identifier_constant(parser.previous)

	kind: Function_Kind = .Method
	if parser.previous.lexeme == "init" {
		kind = .Initializer
	}

	function(kind)
	emit_bytes(byte(Op_Code.METHOD), constant)
}

class_declaration :: proc() {
	consume(.IDENTIFIER, "Expect class name.")
	class_name := parser.previous
	name_constant := identifier_constant(parser.previous)
	declare_variable()

	emit_bytes(byte(Op_Code.CLASS), name_constant)
	define_variable(name_constant)

	class_compiler := Class_Compiler {
		enclosing = current_class,
	}
	current_class = &class_compiler

	if match(.LESS) {
		consume(.IDENTIFIER, "Expect superclass name.")
		variable(false)

		if identifiers_equal(class_name, parser.previous) {
			error("A class can't inherit from itself.")
		}

		begin_scope()
		add_local(synthetic_token("super"))
		define_variable(0)

		named_variable(class_name, false)
		emit_byte(byte(Op_Code.INHERIT))
		class_compiler.has_superclass = true
	}

	named_variable(class_name, false)
	consume(.LEFT_BRACE, "Expect '{' before class body.")
	for !check(.RIGHT_BRACE) && !check(.EOF) {
		method()
	}
	consume(.RIGHT_BRACE, "Expect '}' after class body.")
	emit_byte(byte(Op_Code.POP))

	if class_compiler.has_superclass {
		end_scope()
	}

	current_class = current_class.enclosing
}

fun_declaration :: proc() {
	global := parse_variable("Expect function name.")
	mark_initialized()
	function(.Function)
	define_variable(global)
}

var_declaration :: proc() {
	global := parse_variable("Expect variable name.")

	if match(.EQUAL) {
		expression()
	} else {
		emit_byte(byte(Op_Code.NIL))
	}
	consume(.SEMICOLON, "Expect ';' after variable declaration.")

	define_variable(global)
}

expression_statement :: proc() {
	expression()
	consume(.SEMICOLON, "Expect ';' after expression.")
	emit_byte(byte(Op_Code.POP))
}

for_statement :: proc() {
	begin_scope()
	consume(.LEFT_PAREN, "Expect '(' after 'for'.")
	if !match(.SEMICOLON) {
		if match(.VAR) {
			var_declaration()
		} else {
			expression_statement()
		}
	}

	loop_start := len(current_chunk().code)
	exit_jump := -1
	if !match(.SEMICOLON) {
		expression()
		consume(.SEMICOLON, "Expect ';' after loop condition.")

		exit_jump = emit_jump(byte(Op_Code.JUMP_IF_FALSE))
		emit_byte(byte(Op_Code.POP))
	}

	if !match(.RIGHT_PAREN) {
		body_jump := emit_jump(byte(Op_Code.JUMP))
		increment_start := len(current_chunk().code)
		expression()
		emit_byte(byte(Op_Code.POP))
		consume(.RIGHT_PAREN, "Expect ')' after for clauses.")

		emit_loop(loop_start)
		loop_start = increment_start
		patch_jump(body_jump)
	}

	statement()
	emit_loop(loop_start)

	if exit_jump != -1 {
		patch_jump(exit_jump)
		emit_byte(byte(Op_Code.POP))
	}

	end_scope()
}

if_statement :: proc() {
	consume(.LEFT_PAREN, "Expect '(' after 'if'.")
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after condition.")

	then_jump := emit_jump(byte(Op_Code.JUMP_IF_FALSE))
	emit_byte(byte(Op_Code.POP))
	statement()

	else_jump := emit_jump(byte(Op_Code.JUMP))

	patch_jump(then_jump)
	emit_byte(byte(Op_Code.POP))

	if match(.ELSE) do statement()
	patch_jump(else_jump)
}

print_statement :: proc() {
	expression()
	consume(.SEMICOLON, "Expect ';' after value.")
	emit_byte(byte(Op_Code.PRINT))
}

return_statement :: proc() {
	if current.kind == .Script {
		error("Can't return from top-level code.")
	}

	if match(.SEMICOLON) {
		emit_return()
	} else {
		if current.kind == .Initializer {
			error("Can't return a value from an initializer.")
		}

		expression()
		consume(.SEMICOLON, "Expect ';' after return value.")
		emit_byte(byte(Op_Code.RETURN))
	}
}

while_statement :: proc() {
	loop_start := len(current_chunk().code)
	consume(.LEFT_PAREN, "Expect '(' after 'while'.")
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after condition.")

	exit_jump := emit_jump(byte(Op_Code.JUMP_IF_FALSE))
	emit_byte(byte(Op_Code.POP))
	statement()
	emit_loop(loop_start)

	patch_jump(exit_jump)
	emit_byte(byte(Op_Code.POP))
}

synchronize :: proc() {
	parser.panic_mode = false

	for parser.current.kind != .EOF {
		if parser.previous.kind == .SEMICOLON do return
		#partial switch parser.current.kind {
		case .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN:
			return
		}

		advance()
	}
}

declaration :: proc() {
	if match(.CLASS) {
		class_declaration()
	} else if match(.FUN) {
		fun_declaration()
	} else if match(.VAR) {
		var_declaration()
	} else {
		statement()
	}

	if parser.panic_mode do synchronize()
}

statement :: proc() {
	if match(.PRINT) {
		print_statement()
	} else if match(.FOR) {
		for_statement()
	} else if match(.IF) {
		if_statement()
	} else if match(.RETURN) {
		return_statement()
	} else if match(.WHILE) {
		while_statement()
	} else if match(.LEFT_BRACE) {
		begin_scope()
		block()
		end_scope()
	} else {
		expression_statement()
	}
}

compile :: proc(source: string) -> ^Obj_Function {
	init_scanner(source)

	compiler: Compiler
	init_compiler(&compiler, .Script)

	parser.had_error = false
	parser.panic_mode = false

	advance()

	for !match(.EOF) {
		declaration()
	}

	function := end_compiler()
	return parser.had_error ? nil : function
}

mark_compiler_roots :: proc() {
	compiler := current
	for compiler != nil {
		mark_object(cast(^Obj)compiler.function)
		compiler = compiler.enclosing
	}
}
