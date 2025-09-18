package main

// import "core:fmt"
// import "core:slice"
// import "core:testing"

// @(test)
// test_print :: proc(t: ^testing.T) {
// 	source := (`print 1; print "foo";`)
// 	defer delete(source)
// 	result := interpret(source)
// 	testing.expect_value(t, result, Interpreter_Result.OK)
// 	testing.expectf(
// 		t,
// 		slice.equal(vm.print_output[:], []string{"1", "foo"}),
// 		"%#v",
// 		vm.print_output[:],
// 	)
// }

// @(test)
// test_scope :: proc(t: ^testing.T) {
// 	source :=
// 		(`
// 	var foo = "a";
// 	{
// 		print foo;
// 		var foo = "b";
// 		{
// 			var foo = "c";
// 			print foo;
// 		}
// 		print foo;
// 	}
// 	print foo;
// 	`)
// 	defer delete(source)
// 	// result := interpret(source)
// 	// testing.expect_value(t, result, Interpreter_Result.OK)
// 	// testing.expectf(
// 	// 	t,
// 	// 	slice.equal(vm.prints[:], []string{"a", "b", "c", "b", "a"}),
// 	// 	"%#v",
// 	// 	vm.prints[:],
// 	// )
// }

// // @(test)
// // test_print :: proc(t: ^testing.T) {
// // 	source := `
// // 	print 1;
// // 	print 2;
// // 	`


// // 	result := interpret(source)
// // 	testing.expect_value(t, result, Interpreter_Result.OK)
// // 	testing.expect(t, slice.equal(vm.output[:], []string{"1", "2"}))
// // }
