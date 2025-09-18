package main

import "core:fmt"
import "core:io"
import "core:strings"

Native_Fn :: proc(_: []Value) -> Value

Obj :: struct {
	is_marked: bool,
	next:      ^Obj,
	variant:   union {
		^Obj_String,
		^Obj_Function,
		^Obj_Upvalue,
		^Obj_Closure,
		^Obj_Class,
		^Obj_Instance,
		^Obj_Bound_Method,
		^Obj_Native,
	},
}

Obj_Native :: struct {
	using obj: Obj,
	function:  Native_Fn,
}

Obj_String :: struct {
	using obj: Obj,
	chars:     string,
	hash:      u32,
}

Obj_Function :: struct {
	using obj:     Obj,
	arity:         int,
	upvalue_count: int,
	chunk:         Chunk,
	name:          ^Obj_String,
}

Obj_Upvalue :: struct {
	using obj: Obj,
	location:  ^Value,
	closed:    Value,
	next:      ^Obj_Upvalue,
}

Obj_Closure :: struct {
	using obj: Obj,
	function:  ^Obj_Function,
	upvalues:  [dynamic]^Obj_Upvalue,
}

Obj_Class :: struct {
	using obj: Obj,
	name:      ^Obj_String,
	methods:   Table,
}

Obj_Instance :: struct {
	using obj: Obj,
	class:     ^Obj_Class,
	fields:    Table,
}

Obj_Bound_Method :: struct {
	using obj: Obj,
	receiver:  Value,
	method:    ^Obj_Closure,
}

new_obj :: proc($T: typeid) -> ^T {
	obj := new(T)
	obj.variant = obj
	obj.next = vm.objects
	vm.objects = obj
	when ODIN_DEBUG {
		fmt.printf("\033[96m%p allocate %i for %v\033[0m\n", &obj, size_of(T), typeid_of(T))
	}
	return obj
}

new_bound_method :: proc(receiver: Value, method: ^Obj_Closure) -> ^Obj_Bound_Method {
	bound := new_obj(Obj_Bound_Method)
	bound.receiver = receiver
	bound.method = method
	return bound
}

new_class :: proc(name: ^Obj_String) -> ^Obj_Class {
	class := new_obj(Obj_Class)
	class.name = name
	return class
}

new_closure :: proc(function: ^Obj_Function) -> ^Obj_Closure {
	upvalues := make([dynamic]^Obj_Upvalue, function.upvalue_count)
	closure := new_obj(Obj_Closure)
	closure.function = function
	closure.upvalues = upvalues
	return closure
}

new_function :: proc() -> ^Obj_Function {
	function := new_obj(Obj_Function)
	function.arity = 0
	function.upvalue_count = 0
	function.name = nil
	init_chunk(&function.chunk)
	return function
}

new_instance :: proc(class: ^Obj_Class) -> ^Obj_Instance {
	instance := new_obj(Obj_Instance)
	instance.class = class
	return instance
}

new_native :: proc(function: Native_Fn) -> ^Obj_Native {
	native := new_obj(Obj_Native)
	native.function = function
	return native
}

Hash :: u32

new_string :: proc(chars: string, hash: Hash) -> ^Obj_String {
	assert(hash != 0)

	obj := new_obj(Obj_String)
	obj.chars = chars
	obj.hash = hash

	vm_push(&obj.obj)
	table_set(&vm.interned_strings, obj, nil)
	vm_pop()

	return obj
}

take_string :: proc(s: string) -> ^Obj_String {
	hash := hash_string(s)
	interned := table_find_string(&vm.interned_strings, s, hash)
	if (interned != nil) {
		delete(s)
		return interned
	}

	return new_string(s, hash)
}

copy_string :: proc(chars: string) -> ^Obj_String {
	hash := hash_string(chars)
	interned := table_find_string(&vm.interned_strings, chars, hash)
	if (interned != nil) {
		return interned
	}

	return new_string(strings.clone(chars), hash)
}

new_upvalue :: proc(slot: ^Value) -> ^Obj_Upvalue {
	upvalue := new_obj(Obj_Upvalue)
	upvalue.location = slot
	return upvalue
}

@(require_results)
print_function :: proc(function: ^Obj_Function) -> string {
	if (function.name == nil) {
		return "<script>"
	} else {
		return fmt.tprintf("<fn %s>", function.name.chars)
	}
}

@(require_results)
print_object :: proc(obj: Obj) -> string {
	switch v in obj.variant {
	case ^Obj_Bound_Method:
		return print_function(v.method.function)
	case ^Obj_Class:
		return fmt.tprintf("%s", v.name.chars) // TODO: tprintf allocated in temporary allocator, fyi. make sure tprinf is used responsibly and not for long-term values.
	case ^Obj_Closure:
		return print_function(v.function)
	case ^Obj_Function:
		return print_function(v)
	case ^Obj_Instance:
		return fmt.tprintf("%s instance", v.class.name.chars)
	case ^Obj_Native:
		return "<native fn>"
	case ^Obj_String:
		return fmt.tprintf("%s", v.chars)
	case ^Obj_Upvalue:
		return "upvalue"
	}
	unreachable()
}

@(require_results)
hash_string :: proc(key: string) -> Hash {
	hash: u32 = 2166136261
	for c in key {
		hash ~= u32(c)
		hash *= 16777619
	}
	return hash
}
