package main

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

FRAMES_MAX :: 64
U8_COUNT :: int(max(u8)) + 1
STACK_MAX :: FRAMES_MAX * U8_COUNT

Call_Frame :: struct {
	closure: ^Obj_Closure,
	ip:      int,
	slots:   []Value,
}

Vm :: struct {
	frames:                   [FRAMES_MAX]Call_Frame,
	frame_count:              int,
	stack:                    [STACK_MAX]Value,
	stack_top:                int, // TODO: consider renaming to stack_count
	globals:                  Table,
	interned_strings:         Table,
	init_string:              ^Obj_String,
	open_upvalues:            ^Obj_Upvalue,
	bytes_allocated, next_gc: int,
	objects:                  ^Obj,
	gray_stack:               [dynamic]^Obj,
	print_output:             [dynamic]string,
	error_output:             [dynamic]string,
}

Interpreter_Result :: enum {
	OK,
	COMPILE_ERROR,
	RUNTIME_ERROR,
}

vm: Vm

clock_native :: proc(args: []Value) -> Value {
	return f64(libc.clock()) / libc.CLOCKS_PER_SEC
}

reset_stack :: proc() {
	vm.stack_top = 0
	vm.frame_count = 0
	vm.open_upvalues = nil
}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintf(format, args)
	fmt.eprint("\n")

	for i := vm.frame_count - 1; i >= 0; i -= 1 {
		frame := &vm.frames[i]
		function := frame.closure.function
		instruction := frame.ip - 1
		fmt.eprintf("[line %d] in ", function.chunk.lines[instruction])

		if (function.name == nil) {
			fmt.eprintf("script\n")
		} else {
			fmt.eprintf("%s()\n", function.name.chars)
		}
	}

	reset_stack()
}

define_native :: proc(name: string, function: Native_Fn) {
	str := copy_string(name)
	vm_push(&str.obj)
	vm_push(&new_native(function).obj)
	table_set(&vm.globals, vm.stack[0].(^Obj).variant.(^Obj_String), vm.stack[1])
	vm_pop()
	vm_pop()
}

vm_push :: proc(value: Value) {
	vm.stack[vm.stack_top] = value
	vm.stack_top += 1
}

vm_pop :: proc() -> Value {
	vm.stack_top -= 1
	return vm.stack[vm.stack_top]
}

init_vm :: proc() {
	vm = {}

	reset_stack()
	vm.objects = nil
	vm.bytes_allocated = 0
	vm.next_gc = 1024 * 1024

	vm.gray_stack = make([dynamic]^Obj)

	vm.init_string = nil
	vm.init_string = copy_string("init")
	vm.print_output = make([dynamic]string)

	define_native("clock", clock_native)
}

free_vm :: proc() {
	free_table(&vm.globals)
	free_table(&vm.interned_strings)
	vm.init_string = nil
	free_objects()
	delete(vm.print_output)
}

peek :: proc(distance: int) -> Value {
	return vm.stack[vm.stack_top - 1 - distance]
}

call_closure :: proc(closure: ^Obj_Closure, arg_count: int) -> bool {
	if arg_count != closure.function.arity {
		runtime_error("Expected %d arguments but got %d.", closure.function.arity, arg_count)
		return false
	}

	if vm.frame_count == FRAMES_MAX {
		runtime_error("Stack overflow.")
		return false
	}

	frame := &vm.frames[vm.frame_count]
	vm.frame_count += 1
	frame.closure = closure
	frame.ip = 0
	frame.slots = vm.stack[vm.stack_top - arg_count - 1:]
	return true
}

call_value :: proc(callee: Value, arg_count: int) -> bool {
	if callee == nil do return false

	if obj, ok := callee.(^Obj); ok {
		#partial switch v in obj.variant {

		case ^Obj_Bound_Method:
			vm.stack[vm.stack_top - arg_count - 1] = v.receiver
			return call_closure(v.method, arg_count)

		case ^Obj_Class:
			vm.stack[vm.stack_top - arg_count - 1] = &new_instance(v).obj
			initializer: Value
			if table_get(&v.methods, vm.init_string, &initializer) {
				if init_obj, init_ok := initializer.(^Obj); init_ok {
					if init_closure, init_closure_ok := init_obj.variant.(^Obj_Closure);
					   init_closure_ok {
						return call_closure(init_closure, arg_count)
					}
				}
			} else if arg_count != 0 {
				runtime_error("Expected 0 arguments but got %d.", arg_count)
				return false
			}
			return true

		case ^Obj_Closure:
			return call_closure(v, arg_count)

		case ^Obj_Native:
			result := v.function(vm.stack[vm.stack_top - arg_count:vm.stack_top])
			vm.stack_top -= arg_count + 1
			vm_push(result)
			return true
		}
	}

	runtime_error("Can only call functions and classes.")
	return false
}
invoke_from_class :: proc(klass: ^Obj_Class, name: ^Obj_String, arg_count: int) -> bool {
	method: Value
	if !table_get(&klass.methods, name, &method) {
		runtime_error("Undefined property '%s'.", name.chars)
		return false
	}
	if method_obj, ok := method.(^Obj); ok {
		if method_closure, closure_ok := method_obj.variant.(^Obj_Closure); closure_ok {
			return call_closure(method_closure, arg_count)
		}
	}
	return false
}

invoke :: proc(name: ^Obj_String, arg_count: int) -> bool {
	instance, ok := peek(arg_count).(^Obj).variant.(^Obj_Instance)

	if !ok {
		runtime_error("Only instances have methods.")
		return false
	}

	value: Value
	if table_get(&instance.fields, name, &value) {
		vm.stack[vm.stack_top - arg_count - 1] = value
		return call_value(value, arg_count)
	}

	return invoke_from_class(instance.class, name, arg_count)
}
bind_method :: proc(klass: ^Obj_Class, name: ^Obj_String) -> bool {
	method: Value
	if !table_get(&klass.methods, name, &method) {
		runtime_error("Undefined property '%s'.", name.chars)
		return false
	}

	if method_obj, ok := method.(^Obj); ok {
		if method_closure, closure_ok := method_obj.variant.(^Obj_Closure); closure_ok {
			bound := new_bound_method(peek(0), method_closure)
			vm_pop()
			vm_push(&bound.obj)
			return true
		}
	}
	return false
}
capture_upvalue :: proc(local: ^Value) -> ^Obj_Upvalue {
	prev_upvalue: ^Obj_Upvalue = nil
	upvalue := vm.open_upvalues
	for upvalue != nil && upvalue.location > local {
		prev_upvalue = upvalue
		upvalue = upvalue.next.variant.(^Obj_Upvalue) // TODO: how do we know this is an upvalue?
	}

	if upvalue != nil && upvalue.location == local {
		return upvalue
	}

	created_upvalue := new_upvalue(local)
	created_upvalue.next = upvalue

	if prev_upvalue == nil {
		vm.open_upvalues = created_upvalue
	} else {
		prev_upvalue.next = created_upvalue
	}

	return created_upvalue
}

close_upvalues :: proc(last: ^Value) {
	for vm.open_upvalues != nil && vm.open_upvalues.location >= last {
		upvalue := vm.open_upvalues
		upvalue.closed = upvalue.location^
		upvalue.location = &upvalue.closed
		if upvalue.next != nil {
			vm.open_upvalues = upvalue.next.variant.(^Obj_Upvalue) // TODO: how do we know this is an upvalue?
		} else {
			vm.open_upvalues = nil
		}
	}
}

define_method :: proc(name: ^Obj_String) {
	method := peek(0)
	class := peek(1).(^Obj).variant.(^Obj_Class)
	table_set(&class.methods, name, method)
	vm_pop()
}

is_falsey :: proc(value: Value) -> bool {
	return value == nil || (value == false)
}

concatenate :: proc(a, b: ^Obj_String) {
	length := len(a.chars) + len(b.chars)
	chars := make([]u8, length + 1)
	copy(chars[:len(a.chars)], a.chars)
	copy(chars[len(a.chars):], b.chars)
	chars[length] = 0

	result := take_string(string(chars[:length]))
	vm_pop()
	vm_pop()
	vm_push(&result.obj)
}

read_byte :: proc(frame: ^Call_Frame) -> (result: byte) {
	result = frame.closure.function.chunk.code[frame.ip]
	frame.ip += 1
	return
}

read_short :: proc(frame: ^Call_Frame) -> (result: u16) {
	frame.ip += 2
	return(
		(u16(frame.closure.function.chunk.code[frame.ip - 2]) << 8) |
		u16(frame.closure.function.chunk.code[frame.ip - 1]) \
	)

}

read_constant :: proc(frame: ^Call_Frame) -> Value {
	return frame.closure.function.chunk.constants[read_byte(frame)]
}

read_string :: proc(frame: ^Call_Frame) -> (result: ^Obj_String) {
	v := read_constant(frame)
	result = v.(^Obj).variant.(^Obj_String)
	return
}

binary_op :: proc(op: proc(_, _: f64) -> Value) {
	b, ok := vm_pop().(f64)
	a, ok2 := vm_pop().(f64)
	if !ok || !ok2 {
		runtime_error("Operands must be numbers.")
		return
	}
	vm_push(op(a, b))
}

run :: proc() -> Interpreter_Result {
	frame := &vm.frames[vm.frame_count - 1]

	// fmt.printf("Running...\n")

	for {
		when false {
			fmt.printf("\033[95m") // Pink foreground color
			fmt.printf("          ")
			fmt.printf("[")
			for slot, i in vm.stack[:vm.stack_top] {
				print_value(slot, true)
				if i < vm.stack_top - 1 {
					fmt.printf(", ")
				}
			}
			fmt.printf("]")
			fmt.printf("\033[93m") // Back to yellow
			fmt.printf("\n")
			disassemble_instruction(&frame.closure.function.chunk, frame.ip)
			fmt.printf("\033[0m") // Reset color
		}

		instruction := read_byte(frame)

		switch Op_Code(instruction) {

		case .CONSTANT:
			constant := read_constant(frame)
			vm_push(constant)

		case .NIL:
			vm_push(nil)

		case .TRUE:
			vm_push(true)

		case .FALSE:
			vm_push(false)

		case .POP:
			vm_pop()

		case .GET_LOCAL:
			slot := read_byte(frame)
			vm_push(frame.slots[slot])

		case .SET_LOCAL:
			slot := read_byte(frame)
			frame.slots[slot] = peek(0)

		case .GET_GLOBAL:
			name := read_string(frame)
			value: Value
			if !table_get(&vm.globals, name, &value) {
				runtime_error("Undefined variable '%s'.", name.chars)
				return .RUNTIME_ERROR
			}
			vm_push(value)

		case .DEFINE_GLOBAL:
			name := read_string(frame)
			table_set(&vm.globals, name, peek(0))
			vm_pop()

		case .SET_GLOBAL:
			name := read_string(frame)
			if table_set(&vm.globals, name, peek(0)) {
				table_delete(&vm.globals, name)
				runtime_error("Undefined variable '%s'.", name.chars)
				return .RUNTIME_ERROR
			}

		case .GET_UPVALUE:
			slot := read_byte(frame)
			vm_push(frame.closure.upvalues[slot].location^)

		case .SET_UPVALUE:
			slot := read_byte(frame)
			frame.closure.upvalues[slot].location^ = peek(0)

		case .GET_PROPERTY:
			instance, ok := peek(0).(^Obj).variant.(^Obj_Instance)

			if !ok {
				runtime_error("Only instances have properties.")
				return .RUNTIME_ERROR
			}

			name := read_string(frame)

			value: Value
			if table_get(&instance.fields, name, &value) {
				vm_pop()
				vm_push(value)
			} else if !bind_method(instance.class, name) {
				return .RUNTIME_ERROR
			}

		case .SET_PROPERTY:
			instance, ok := peek(1).(^Obj).variant.(^Obj_Instance)

			if !ok {
				runtime_error("Only instances have fields.")
				return .RUNTIME_ERROR
			}

			table_set(&instance.fields, read_string(frame), peek(0))
			value := vm_pop()
			vm_pop()
			vm_push(value)

		case .GET_SUPER:
			name := read_string(frame)
			superclass := vm_pop().(^Obj).variant.(^Obj_Class)

			if !bind_method(superclass, name) {
				return .RUNTIME_ERROR
			}

		case .EQUAL:
			b := vm_pop()
			a := vm_pop()
			vm_push(a == b)

		case .GREATER:
			binary_op(proc(a, b: f64) -> Value {return a > b})

		case .LESS:
			binary_op(proc(a: f64, b: f64) -> Value {return a < b})

		case .ADD:
			b, ok1 := value_to_string(peek(0))
			a, ok2 := value_to_string(peek(1))

			if ok1 && ok2 {
				concatenate(a, b)
			} else {
				b := vm_pop().(f64)
				a := vm_pop().(f64)
				vm_push(a + b)
			}

		case .SUBTRACT:
			binary_op(proc(a: f64, b: f64) -> Value {return a - b})

		case .MULTIPLY:
			binary_op(proc(a: f64, b: f64) -> Value {return a * b})

		case .DIVIDE:
			binary_op(proc(a: f64, b: f64) -> Value {return a / b})

		case .NOT:
			vm_push(is_falsey(vm_pop()))

		case .NEGATE:
			if num, ok := vm_pop().(f64); ok {
				vm_push(-num)
			} else {
				runtime_error("Operand must be a number.")
				return .RUNTIME_ERROR
			}

		case .PRINT:
			s := print_value(vm_pop())
			fmt.println(s)
			append(&vm.print_output, s)

		case .JUMP:
			offset := read_short(frame)
			frame.ip += int(offset)

		case .JUMP_IF_FALSE:
			offset := read_short(frame)
			if is_falsey(peek(0)) {
				frame.ip += int(offset)
			}

		case .LOOP:
			offset := read_short(frame)
			frame.ip -= int(offset)

		case .CALL:
			arg_count := int(read_byte(frame))
			if !call_value(peek(arg_count), arg_count) {
				return .RUNTIME_ERROR
			}
			frame = &vm.frames[vm.frame_count - 1]

		case .INVOKE:
			method := read_string(frame)
			arg_count := int(read_byte(frame))
			if !invoke(method, arg_count) {
				return .RUNTIME_ERROR
			}
			frame = &vm.frames[vm.frame_count - 1]

		case .SUPER_INVOKE:
			method := read_string(frame)
			arg_count := int(read_byte(frame))
			superclass := vm_pop().(^Obj).variant.(^Obj_Class)
			if !invoke_from_class(superclass, method, arg_count) {
				return .RUNTIME_ERROR
			}
			frame = &vm.frames[vm.frame_count - 1]

		case .CLOSURE:
			// fmt.println("!!!")
			// fmt.println(instruction)
			// fmt.println(frame.closure.function.chunk.code[frame.ip])
			// fmt.printfln("%#v", frame.closure.function.chunk.constants)
			// fmt.println("!!!")
			c := read_constant(frame)
			function := c.(^Obj).variant.(^Obj_Function)
			closure := new_closure(function)
			vm_push(&closure.obj)

			for i in 0 ..< function.upvalue_count {
				is_local := read_byte(frame)
				index := read_byte(frame)
				if is_local != 0 {
					closure.upvalues[i] = capture_upvalue(&frame.slots[index])
				} else {
					closure.upvalues[i] = frame.closure.upvalues[index]
				}
			}

		case .CLOSE_UPVALUE:
			close_upvalues(&vm.stack[vm.stack_top - 1])
			vm_pop()

		case .RETURN:
			result := vm_pop()
			close_upvalues(&frame.slots[0])
			vm.frame_count -= 1
			if vm.frame_count == 0 {
				vm_pop()
				return .OK
			}

			vm.stack_top = len(vm.stack) - len(frame.slots)
			vm_push(result)
			frame = &vm.frames[vm.frame_count - 1]

		case .CLASS:
			vm_push(&new_class(read_string(frame)).obj)

		case .INHERIT:
			superclass, ok := peek(1).(^Obj).variant.(^Obj_Class)
			if !ok {
				runtime_error("Superclass must be a class.")
				return .RUNTIME_ERROR
			}

			subclass := peek(0).(^Obj).variant.(^Obj_Class)
			table_add_all(&superclass.methods, &subclass.methods)
			vm_pop()

		case .METHOD:
			define_method(read_string(frame))

		case:
			fmt.print("\n")
			runtime_error("Unknown opcode: %d", instruction)
			return .RUNTIME_ERROR
		}
	}
}

// reset_vm :: proc() {
// 	free_table(&vm.globals)
// 	free_table(&vm.interned_strings)
// 	vm.init_string = nil
// 	free_objects()
// 	// delete(vm.output)
// 	clear(&vm.output)
// }

interpret :: proc(source: string) -> Interpreter_Result {
	free_vm()
	init_vm()
	function := compile(source)
	if function == nil do return .COMPILE_ERROR

	vm_push(&function.obj)

	closure := new_closure(function)
	vm_pop()
	vm_push(&closure.obj)
	// prev := context.allocator
	// context.allocator = make_allocator()
	// defer {
	// 	free_all()
	// 	// free_all(context.allocator) // FIXME: possible?
	// 	context.allocator = prev
	// }
	call_closure(closure, 0)

	return run()
}
