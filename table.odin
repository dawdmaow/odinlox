package main

import "core:fmt"

TABLE_MAX_LOAD :: 0.75

// TODO: make table generic (ex. string interning doesn't need a value, so it should be struct{})
// also more type safety, maybe.

Entry :: struct {
	key:   ^Obj_String,
	value: Value,
}

Table :: struct {
	count:    int,
	capacity: int,
	entries:  []Entry,
}

free_table :: proc(table: ^Table) {
	if table == nil do return // TODO: this should be an assert
	delete(table.entries)
	table^ = {}
}

find_entry :: proc(entries: []Entry, capacity: int, key: ^Obj_String) -> ^Entry {
	// fmt.printfln("%#v", entries)
	// fmt.printfln("%#v", key)
	if key == nil do return nil // TODO: this should be an assert
	index := key.hash & u32(capacity - 1)
	tombstone: ^Entry = nil

	for {
		entry := &entries[index]
		if entry.key == nil {
			if entry.value == nil {
				return tombstone != nil ? tombstone : entry
			} else if tombstone == nil {
				tombstone = entry
			}
		} else if entry.key == key {
			// pointer comparison (interned strings of same value should have the same address)
			return entry
		}
		index = (index + 1) & u32(capacity - 1)
	}
}

table_get :: proc(table: ^Table, key: ^Obj_String, value: ^Value) -> bool {
	if table.count == 0 do return false

	entry := find_entry(table.entries[:], table.capacity, key)
	if entry.key == nil do return false

	value^ = entry.value
	return true
}

adjust_capacity :: proc(table: ^Table, capacity: int) {
	entries := make([]Entry, capacity)

	table.count = 0
	for i in 0 ..< table.capacity {
		entry := &table.entries[i]
		if entry.key != nil {
			dest := find_entry(entries, capacity, entry.key)
			dest.key = entry.key
			dest.value = entry.value
			table.count += 1
		}
	}

	delete(table.entries)
	table.entries = entries
	table.capacity = capacity
}

grow_capacity :: proc(capacity: int) -> int {
	return capacity < 8 ? 8 : capacity * 2
}

table_set :: proc(table: ^Table, key: ^Obj_String, value: Value) -> bool {
	if table.count + 1 > int(f32(table.capacity) * TABLE_MAX_LOAD) {
		capacity := grow_capacity(table.capacity)
		adjust_capacity(table, capacity)
	}

	entry := find_entry(table.entries, table.capacity, key)
	is_new_key := entry.key == nil
	if is_new_key && entry.value == nil do table.count += 1

	entry.key = key
	entry.value = value
	return is_new_key
}

table_delete :: proc(table: ^Table, key: ^Obj_String) -> bool {
	if table.count == 0 do return false

	entry := find_entry(table.entries, table.capacity, key)
	if entry.key == nil do return false

	entry.key = nil
	entry.value = true
	return true
}

table_add_all :: proc(from: ^Table, to: ^Table) {
	for i in 0 ..< from.capacity {
		entry := &from.entries[i]
		if entry.key != nil {
			table_set(to, entry.key, entry.value)
		}
	}
}

table_find_string :: proc(table: ^Table, chars: string, hash: u32) -> ^Obj_String {
	assert(hash != 0)
	when ODIN_OS == .JS && LOX_TABLE_DEBUG {
		fmt.eprintf(
			"[table_find_string] count=%v cap=%v len(entries)=%v chars_len=%v\n",
			table.count,
			table.capacity,
			len(table.entries),
			len(chars),
		)
	}
	if table.count == 0 do return nil

	index := hash & u32(table.capacity - 1)
	for {
		entry := &table.entries[index]
		if entry.key == nil {
			if entry.value == nil do return nil
		} else if len(entry.key.chars) == len(chars) &&
		   entry.key.hash == hash &&
		   entry.key.chars[:len(chars)] == chars {
			return entry.key
		}
		index = (index + 1) & u32(table.capacity - 1)
	}
}

table_remove_white :: proc(table: ^Table) {
	if table == nil do return // TODO: this should be an assert
	for i in 0 ..< table.capacity {
		entry := &table.entries[i]
		if entry.key != nil && !entry.key.obj.is_marked {
			table_delete(table, entry.key)
		}
	}
}

mark_table :: proc(table: ^Table) {
	if table == nil do return // TODO: this should be an assert
	for i in 0 ..< table.capacity {
		entry := &table.entries[i]
		mark_object(cast(^Obj)entry.key)
		mark_value(entry.value)
	}
}
