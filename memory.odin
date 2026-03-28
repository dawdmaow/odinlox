package main

DEBUG_STRESS_GC :: true // TODO: make sure this is not true by default
// FOO :: #config(FOO, false) // defines `FOO` as a constant with the default value of false
// BAR :: #config(BAR_DEBUG, true) // name can be different compared to the constant

import "base:runtime"
import "core:fmt"
import "core:mem"

GC_HEAP_GROW_FACTOR :: 2

mark_object :: proc(obj: ^Obj) {
	if obj == nil do return
	if obj.is_marked do return

	when LOX_TRACE_GC {
		fmt.printf("%p mark ", obj)
		fmt.println(print_value(obj)) // TODO: why does print_value accept an Obj?
		fmt.printf("\n")
	}

	obj.is_marked = true

	append(&vm.gray_stack, obj)
}

mark_value :: proc(value: Value) {
	#partial switch v in value {
	case ^Obj:
		mark_object(v)
	}
}

mark_array :: proc(values: []Value) {
	for v in values {
		mark_value(v)
	}
}

blacken_object :: proc(obj: ^Obj) {
	when LOX_TRACE_GC {
		fmt.printf("%p blacken ", obj)
		fmt.println(print_value(obj)) // TODO: why does print_value accept an Obj?
		fmt.printf("\n")
	}

	switch v in obj.variant {
	case ^Obj_Bound_Method:
		mark_value(v.receiver)
		mark_object(v.method)

	case ^Obj_Class:
		mark_object(v.name)
		mark_table(&v.methods)

	case ^Obj_Closure:
		mark_object(v.function)
		for u in v.upvalues {
			mark_object(u)
		}

	case ^Obj_Function:
		mark_object(v.name)
		mark_array(v.chunk.constants[:])

	case ^Obj_Instance:
		mark_object(v.class)
		mark_table(&v.fields)

	case ^Obj_Upvalue:
		mark_value(v.closed)

	case ^Obj_Native, ^Obj_String:
		break
	}
}

free_object :: proc(object: ^Obj) {
	when ODIN_DEBUG {
		fmt.printf("\033[90m%p free type %v\033[0m\n", object, typeid_of(type_of(object.variant)))
	}

	switch v in object.variant {
	case ^Obj_Bound_Method:
		free(v)

	case ^Obj_Class:
		free(&v.methods)
		free(v)

	case ^Obj_Closure:
		delete(v.upvalues)
		free(v)

	case ^Obj_Function:
		free_chunk(&v.chunk)
		free(v)

	case ^Obj_Instance:
		free_table(&v.fields)
		free(v)

	case ^Obj_Native:
		free(v)

	case ^Obj_String:
		delete(v.chars)
		free(v)

	case ^Obj_Upvalue:
		free(v)
	}
}
mark_roots :: proc() {
	for i in 0 ..< vm.stack_top do mark_value(vm.stack[i])
	for i in 0 ..< vm.frame_count do mark_object(vm.frames[i].closure)

	upvalue := vm.open_upvalues
	for upvalue != nil {
		mark_object(upvalue)
		upvalue = upvalue.next.variant.(^Obj_Upvalue) // TODO: why does this hold?
	}

	mark_table(vm.globals)
	mark_compiler_roots()
	mark_object(vm.init_string)
}

trace_references :: proc() {
	for len(vm.gray_stack) > 0 {
		object := vm.gray_stack[len(vm.gray_stack) - 1] // FIXME: is this correct?
		pop(&vm.gray_stack)
		blacken_object(object)
	}
}

sweep :: proc() {
	previous: ^Obj = nil
	object := vm.objects
	for object != nil {
		if object.is_marked {
			object.is_marked = false
			previous = object
			object = object.next
		} else {
			unreached := object
			object = object.next
			if previous != nil {
				previous.next = object
			} else {
				vm.objects = object
			}
			free_object(unreached)
		}
	}
}

collect_garbage :: proc() {
	when ODIN_DEBUG {
		fmt.printf("-- gc begin\n")
	}
	before := vm.bytes_allocated

	mark_roots()
	trace_references()
	table_remove_white(vm.interned_strings)
	sweep()

	vm.next_gc = vm.bytes_allocated * GC_HEAP_GROW_FACTOR

	when ODIN_DEBUG {
		fmt.printf("-- gc end\n")
		fmt.printf(
			"   collected %d bytes (from %d to %d) next at %d\n",
			before - vm.bytes_allocated,
			before,
			vm.bytes_allocated,
			vm.next_gc,
		)
	}
}

free_objects :: proc() {
	when ODIN_DEBUG {
		fmt.printf("\033[90mfree_objects: starting, vm.objects = %p\033[0m\n", vm.objects)
	}
	object := vm.objects
	for object != nil {
		next := object.next
		free_object(object)
		object = next
	}
	when ODIN_DEBUG {
		fmt.printf("\033[90mfree_objects: completed \033[0m\n")
	}
	vm.objects = nil
	delete(vm.gray_stack)
}

allocator_proc: mem.Allocator_Proc : proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]u8,
	mem.Allocator_Error,
) {
	switch mode {
	case .Alloc, .Free, .Resize, .Alloc_Non_Zeroed, .Resize_Non_Zeroed:
	// TODO: fix gc memory bug (seems to be use after free...)
	// when DEBUG_STRESS_GC {
	// 	collect_garbage()
	// }
	// if vm.bytes_allocated > vm.next_gc {
	// 	collect_garbage()
	// }
	case .Query_Features, .Query_Info, .Free_All:
	}
	return runtime.heap_allocator_proc(
		allocator_data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

make_allocator :: proc() -> mem.Allocator {
	return mem.Allocator{procedure = allocator_proc, data = nil}
	// return runtime.heap_allocator()
}
