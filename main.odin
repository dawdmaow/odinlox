package main

import "core:fmt"
import "core:slice"
import "core:strings"

main :: proc() {
	defer fmt.print("\n")

	// context.allocator = make_allocator() // FIXME: causes use after free in table.find_entry

	{
		source := `
		// Assignment on RHS of variable.
		var a = "before";
		var c = a = "var";
		print a;
		print c;
		`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"var", "var"}))
	}

	{
		source := `
				var beverage = "cafe au lait";
				var breakfast = "beignets with " + beverage;
				print breakfast;
				`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"beignets with cafe au lait"}))
	}

	{
		source := `{ var a = a; }`


		result := interpret(source)
		assert(result == .COMPILE_ERROR)
		assert(slice.equal(vm.print_output[:], []string{}))
		assert(
			slice.equal(
				vm.error_output[:],
				[]string {
					"[line 1] Error at 'a': Can't read local variable in its own initializer.",
				},
			),
		)
	}

	{
		source := `
				var foo = "a";
				{
					print foo;
					var foo = "b";
					{
						print foo;
						var foo = "c";
						print foo;
					}
					print foo;
				}
				print foo;
				`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"a", "b", "c", "b", "a"}))
	}

	{
		source := `
				if (true) {
					print "true";
				}
				`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"true"}))
	}

	{
		source := `
				if (true) {
					print "true";
				} else {
					print "false";
				}
				if (false) {
					print "true";
				} else {
					print "false";
				}
				`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"true", "false"}))
	}

	{
		source := `
				var i = 0;

			    while (i < 3) {
			      	print i;
			      	i = i + 1;
			    }
				`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"0", "1", "2"}))
	}

	{
		source := `
				for (var i = 0; i < 3; i = i + 1) {
					print i;
				}
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"0", "1", "2"}))
	}

	{
		source := `
				fun areWeHavingItYet() {
					print "Yes we are!";
				}

				print areWeHavingItYet;
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"<fn areWeHavingItYet>"}))
	}

	{
		source := `
				fun areWeHavingItYet() {
					print "Yes we are!";
				}

				areWeHavingItYet();
			`


		result := interpret(source)
		assert(result == .OK)
		fmt.println(vm.print_output)
		assert(slice.equal(vm.print_output[:], []string{"Yes we are!"}))
	}

	{
		source := `
				fun foo(a, b) {
					print a + b;
				}

				foo(1, 2);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"3"}))
	}

	{
		source := `
				fun foo(a, b) {
					print a + b;
				}

				foo(1, 2);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"3"}))
	}

	{
		source := `
				fun foo(a, b) {
					return a + b;
				}

				print foo(1, 2);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"3"}))
	}

	{
		source := `
				fun bar(a, b) {
					return a + b;
				}

				fun foo(a, b) {
					return bar(a, b);
				}

				print foo(1, 2);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"3"}))
	}

	{
		source := `
				fun fib(n) {
					if (n < 2) return n;
					return fib(n - 1) + fib(n - 2);
				}

				print fib(5);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"5"}))
	}

	{
		source := `
				fun fib(n) {
					if (n < 2) return n;
					return fib(n - 2) + fib(n - 1);
				}

				var start = clock();
				print fib(5);
				print clock() - start;
			`


		result := interpret(source)
		assert(result == .OK)
		assert(len(vm.print_output) == 2)
		assert(vm.print_output[0] == "5")
		assert(strings.has_prefix(vm.print_output[1], "0."))
	}

	{
		source := `
				fun foo(a, b) {
					fun bar(a, b) {
						return a + b;
					}
					return bar(a, b);
				}

				print foo(1, 2);
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"3"}))
	}

	{
		source := `
				fun a() {
					b();
				}

				fun b() {
					c();
				}

				fun c() {
					print "c";
				}

				a();
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"c"}))
	}

	{
		source := `
				var x = "global";
				fun outer() {
					var x = "outer";
					fun inner() {
						print x;
					}
					inner();
				}
				outer();
			`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"outer"}))
	}

	{
		source := `var globalSet;
		var globalGet;

		fun main() {
		  var a = "initial";

		  fun set() { a = "updated"; }
		  fun get() { print a; }

		  globalSet = set;
		  globalGet = get;
		}

		main();
		globalSet();
		globalGet();`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"updated"}))
	}

	{
		source := `var globalOne;
		var globalTwo;

		fun main() {
		  {
		    var a = "one";
		    fun one() {
		      print a;
		    }
		    globalOne = one;
		  }

		  {
		    var a = "two";
		    fun two() {
		      print a;
		    }
		    globalTwo = two;
		  }
		}

		main();
		globalOne();
		globalTwo();`


		result := interpret(source)
		assert(result == .OK)
		assert(slice.equal(vm.print_output[:], []string{"one", "two"}))
	}

	{
		source := `
	class Doughnut {
	  cook() {
	    print "Dunk in the fryer.";
	  }
	}

	class Cruller < Doughnut {
	  finish() {
	    print "Glaze with icing.";
	  }
	}

	var x = Cruller();
	x.cook();
	x.finish();
	`


		result := interpret(source)
		assert(result == .OK)
		assert(
			slice.equal(vm.print_output[:], []string{"Dunk in the fryer.", "Glaze with icing."}),
		)
	}

	/*
Dunk in the fryer.
Glaze with icing.
free_objects: starting, vm.objects = 0x6080000018A8
0x6080000018A8 free type union {^Obj_String, ^Obj_Function, ^Obj_Upvalue, ^Obj_Closure, ^Obj_Class, ^Obj_Instance, ^Obj_Bound_Method, ^Obj_Native}
0x608000001828 free type union {^Obj_String, ^Obj_Function, ^Obj_Upvalue, ^Obj_Closure, ^Obj_Class, ^Obj_Instance, ^Obj_Bound_Method, ^Obj_Native}
0x6080000017A8 free type union {^Obj_String, ^Obj_Function, ^Obj_Upvalue, ^Obj_Closure, ^Obj_Class, ^Obj_Instance, ^Obj_Bound_Method, ^Obj_Native}
=================================================================
==22801==ERROR: AddressSanitizer: attempting free on address which was not malloc()-ed: 0x607000004548 in thread T0
    #0 0x000100e462b0 in free+0x74 (libclang_rt.asan_osx_dynamic.dylib:arm64+0x522b0)
    #1 0x000100722f58 in runtime::[heap_allocator_unix.odin]::_heap_free+0x1c (odin_lox2:arm64+0x100042f58)
    #2 0x00010074f444 in main::free_objects+0x2a0 (odin_lox2:arm64+0x10006f444)
    #3 0x00010074b0e4 in main::free_vm+0xbc (odin_lox2:arm64+0x10006b0e4)
    #4 0x000100723ac4 in main+0xf4 (odin_lox2:arm64+0x100043ac4)

0x607000004548 is located 8 bytes inside of 71-byte region [0x607000004540,0x607000004587)
allocated by thread T0 here:
    #0 0x000100e4649c in calloc+0x78 (libclang_rt.asan_osx_dynamic.dylib:arm64+0x5249c)
    #1 0x000100722ae0 in runtime::[heap_allocator_unix.odin]::_heap_alloc+0x5c (odin_lox2:arm64+0x100042ae0)
    #2 0x000100753d38 in main::identifier_constant+0xdc (odin_lox2:arm64+0x100073d38)
    #3 0x00010075d1ec in main::declaration+0x50 (odin_lox2:arm64+0x10007d1ec)
    #4 0x00010075b694 in main::interpret+0x44 (odin_lox2:arm64+0x10007b694)
    #5 0x000100723ac4 in main+0xf4 (odin_lox2:arm64+0x100043ac4)

SUMMARY: AddressSanitizer: bad-free (odin_lox2:arm64+0x100042f58) in runtime::[heap_allocator_unix.odin]::_heap_free+0x1c
==22801==ABORTING
make[1]: *** [run] Abort trap: 6
[Command exited with 2]
FIXME:
*/
	// {
	// 	source := `
	// class A {
	//   method() {
	//     print "A method";
	//   }
	// }

	// class B < A {
	//   method() {
	//     print "B method";
	//   }

	//   test() {
	//     super.method();
	//   }
	// }

	// class C < B {}

	// C().test();`


	// 	result := interpret(source)
	// 	assert(result == .OK)
	// 	assert(slice.equal(vm.print_output[:], []string{"A method"}))
	// }

	fmt.println("\033[32mSUCCESS\033[0m")
}
