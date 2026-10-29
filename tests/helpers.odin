// Package uri_tests holds the unit tests for uri. Run them with `odin test tests`.
package uri_tests

import uri ".."
import "base:runtime"
import "core:mem"
import "core:testing"

// Leak_Check wraps a tracking allocator that a test passes to every call it makes.
Leak_Check :: struct {
	track: mem.Tracking_Allocator,
}

/*
tracked starts a leak check and returns its allocator. When the calling scope
ends, expect_no_leaks fails the test if anything allocated through the
returned allocator was not freed, or if anything was freed twice.
*/
@(deferred_in_out = expect_no_leaks)
tracked :: proc(t: ^testing.T, lc: ^Leak_Check) -> runtime.Allocator {
	mem.tracking_allocator_init(&lc.track, context.allocator)
	return mem.tracking_allocator(&lc.track)
}

expect_no_leaks :: proc(t: ^testing.T, lc: ^Leak_Check, _: runtime.Allocator) {
	for _, entry in lc.track.allocation_map {
		testing.expectf(t, false, "leaked %d bytes allocated at %v", entry.size, entry.location)
	}
	for entry in lc.track.bad_free_array {
		testing.expectf(t, false, "bad free of %p at %v", entry.memory, entry.location)
	}
	mem.tracking_allocator_destroy(&lc.track)
}

// expect_parse_error checks that parsing `input` fails with exactly `want`.
expect_parse_error :: proc(t: ^testing.T, input: string, want: uri.Parse_Error, loc := #caller_location) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse(input, alloc)
	defer uri.destroy(&u)
	testing.expectf(t, err == uri.Error(want), "parse(%q): got %v, want %v", input, err, want, loc = loc)
}

// expect_round_trip checks that parse followed by to_string reproduces `input`.
expect_round_trip :: proc(t: ^testing.T, input: string, alloc: runtime.Allocator, loc := #caller_location) {
	u, err := uri.parse(input, alloc)
	defer uri.destroy(&u)
	if !testing.expectf(t, err == nil, "parse(%q) failed: %v", input, err, loc = loc) {
		return
	}
	s, serr := uri.to_string(u, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, serr, nil, loc = loc)
	testing.expectf(t, s == input, "round trip: got %q, want %q", s, input, loc = loc)
}

// expect_resolve checks one row of a reference resolution table.
expect_resolve :: proc(t: ^testing.T, base, ref, want: string, alloc: runtime.Allocator, loc := #caller_location) {
	got, err := uri.resolve_string(base, ref, alloc)
	defer delete(got, alloc)
	testing.expectf(t, err == nil, "resolve(%q, %q) failed: %v", base, ref, err, loc = loc)
	testing.expectf(t, got == want, "resolve(%q, %q): got %q, want %q", base, ref, got, want, loc = loc)
}

// expect_normalized checks that normalize turns `input` into `want`.
expect_normalized :: proc(t: ^testing.T, input, want: string, alloc: runtime.Allocator, loc := #caller_location) {
	u, err := uri.parse(input, alloc)
	defer uri.destroy(&u)
	if !testing.expectf(t, err == nil, "parse(%q) failed: %v", input, err, loc = loc) {
		return
	}
	n, nerr := uri.normalize(u, alloc)
	defer uri.destroy(&n)
	testing.expect_value(t, nerr, nil, loc = loc)
	s, _ := uri.to_string(n, alloc)
	defer delete(s, alloc)
	testing.expectf(t, s == want, "normalize(%q): got %q, want %q", input, s, want, loc = loc)
}

/*
Scribble overwrites every block it frees with 0xAA before passing the free on
to `backing`. A procedure that reads memory after freeing it then sees garbage
instead of the old bytes, so use-after-free bugs show up as wrong results.
*/
Scribble :: struct {
	backing: runtime.Allocator,
}

scribble_allocator :: proc(s: ^Scribble) -> runtime.Allocator {
	return {scribble_proc, s}
}

@(private = "file")
scribble_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	s := (^Scribble)(data)
	if mode == .Free && old_memory != nil && old_size > 0 {
		mem.set(old_memory, 0xAA, old_size)
	}
	return s.backing.procedure(s.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

/*
Fail_After lets the first `left` allocations through to `backing` and fails
every later one with `.Out_Of_Memory`. Frees always go through.
*/
Fail_After :: struct {
	backing: runtime.Allocator,
	left:    int,
}

fail_after_allocator :: proc(f: ^Fail_After) -> runtime.Allocator {
	return {fail_after_proc, f}
}

@(private = "file")
fail_after_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	f := (^Fail_After)(data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if f.left <= 0 {
			return nil, .Out_Of_Memory
		}
		f.left -= 1
	}
	return f.backing.procedure(f.backing.data, mode, size, alignment, old_memory, old_size, loc)
}
