#+build !js
package main

import "core:slice"
import "core:strings"
import "core:testing"

// `vm` is a single global; the default Odin test runner uses multiple threads, so run with
// `-define:ODIN_TEST_THREADS=1` (see makefile `test` target). Optional: `-define:ODIN_TEST_TRACK_MEMORY=false`
// avoids spurious leak/bad-free noise from the runner allocator vs. VM heap.

// Shared checks so failures name the scenario instead of a generic assert trap.
expect_ok_prints :: proc(t: ^testing.T, source: string, want: []string) {
	result := interpret(source)
	testing.expect_value(t, result, Interpreter_Result.OK)
	testing.expect(t, slice.equal(vm.print_output[:], want), "unexpected print_output")
}

expect_compile_error :: proc(
	t: ^testing.T,
	source: string,
	want_prints: []string,
	want_errors: []string,
) {
	result := interpret(source)
	testing.expect_value(t, result, Interpreter_Result.COMPILE_ERROR)
	testing.expect(t, slice.equal(vm.print_output[:], want_prints), "unexpected print_output")
	testing.expect(t, slice.equal(vm.error_output[:], want_errors), "unexpected error_output")
}

@(test)
interpret_assignment_on_rhs_variable :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
		// Assignment on RHS of variable.
		var a = "before";
		var c = a = "var";
		print a;
		print c;
		`,
		[]string{"var", "var"},
	)
}

@(test)
interpret_string_concat :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				var beverage = "cafe au lait";
				var breakfast = "beignets with " + beverage;
				print breakfast;
				`,
		[]string{"beignets with cafe au lait"},
	)
}

@(test)
interpret_local_in_own_initializer :: proc(t: ^testing.T) {
	expect_compile_error(
		t,
		`{ var a = a; }`,
		[]string{},
		[]string{"[line 1] Error at 'a': Can't read local variable in its own initializer."},
	)
}

@(test)
interpret_nested_scope_shadowing :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
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
				`,
		[]string{"a", "b", "c", "b", "a"},
	)
}

@(test)
interpret_if_true_branch :: proc(t: ^testing.T) {
	expect_ok_prints(t, `
				if (true) {
					print "true";
				}
				`, []string{"true"})
}

@(test)
interpret_if_else :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
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
				`,
		[]string{"true", "false"},
	)
}

@(test)
interpret_while_loop :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				var i = 0;

			    while (i < 3) {
			      	print i;
			      	i = i + 1;
			    }
				`,
		[]string{"0", "1", "2"},
	)
}

@(test)
interpret_for_loop :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				for (var i = 0; i < 3; i = i + 1) {
					print i;
				}
			`,
		[]string{"0", "1", "2"},
	)
}

@(test)
interpret_print_function_value :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun areWeHavingItYet() {
					print "Yes we are!";
				}

				print areWeHavingItYet;
			`,
		[]string{"<fn areWeHavingItYet>"},
	)
}

@(test)
interpret_call_void_function :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun areWeHavingItYet() {
					print "Yes we are!";
				}

				areWeHavingItYet();
			`,
		[]string{"Yes we are!"},
	)
}

@(test)
interpret_function_two_args :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun foo(a, b) {
					print a + b;
				}

				foo(1, 2);
			`,
		[]string{"3"},
	)
}

@(test)
interpret_return_and_print :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun foo(a, b) {
					return a + b;
				}

				print foo(1, 2);
			`,
		[]string{"3"},
	)
}

@(test)
interpret_nested_function_calls :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun bar(a, b) {
					return a + b;
				}

				fun foo(a, b) {
					return bar(a, b);
				}

				print foo(1, 2);
			`,
		[]string{"3"},
	)
}

@(test)
interpret_fibonacci :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun fib(n) {
					if (n < 2) return n;
					return fib(n - 1) + fib(n - 2);
				}

				print fib(5);
			`,
		[]string{"5"},
	)
}

@(test)
interpret_fibonacci_with_clock :: proc(t: ^testing.T) {
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
	testing.expect_value(t, result, Interpreter_Result.OK)
	testing.expect_value(t, len(vm.print_output), 2)
	testing.expect_value(t, vm.print_output[0], "5")
	testing.expect(
		t,
		strings.has_prefix(vm.print_output[1], "0."),
		"clock delta should look fractional",
	)
}

@(test)
interpret_inner_function_closure :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				fun foo(a, b) {
					fun bar(a, b) {
						return a + b;
					}
					return bar(a, b);
				}

				print foo(1, 2);
			`,
		[]string{"3"},
	)
}

@(test)
interpret_call_chain :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
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
			`,
		[]string{"c"},
	)
}

@(test)
interpret_closure_lexical_capture :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
				var x = "global";
				fun outer() {
					var x = "outer";
					fun inner() {
						print x;
					}
					inner();
				}
				outer();
			`,
		[]string{"outer"},
	)
}

@(test)
interpret_closure_via_globals :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`var globalSet;
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
		globalGet();`,
		[]string{"updated"},
	)
}

@(test)
interpret_closure_distinct_cells :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`var globalOne;
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
		globalTwo();`,
		[]string{"one", "two"},
	)
}

@(test)
interpret_class_inheritance :: proc(t: ^testing.T) {
	expect_ok_prints(
		t,
		`
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
	`,
		[]string{"Dunk in the fryer.", "Glaze with icing."},
	)
}
