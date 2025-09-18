package main

import "core:fmt"
import "core:strings"

Value :: union {
	bool,
	f64,
	^Obj,
}

@(require_results)
print_value :: proc(value: Value) -> string {
	switch v in value {
	case bool:
		return v ? "true" : "false"
	case nil:
		return "nil"
	case f64:
		s := fmt.tprintf("%.10f", v) // TODO: this leaks memory (because trim_right returns a slice ofo the original string), we should use a temporary allocator for this (and clean it after every instruction?)
		s = strings.trim_right(s, "0")
		s = strings.trim_right(s, ".")
		return s
	case ^Obj:
		return print_object(v^)
	}
	unreachable()
}

value_to_string :: proc(value: Value) -> (^Obj_String, bool) {
	#partial switch v in value {
	case ^Obj:
		#partial switch v in v.variant {
		case ^Obj_String:
			return v, true
		}
	}
	return nil, false
}
