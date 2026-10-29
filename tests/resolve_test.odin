package uri_tests

import uri ".."
import "core:testing"

// RFC_BASE is the base URI of the examples in RFC 3986 section 5.4.
RFC_BASE :: "http://a/b/c/d;p?q"

Resolve_Case :: struct {
	ref, want: string,
}

@(test)
test_resolve_rfc3986_normal_examples :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	// RFC 3986 section 5.4.1.
	cases := []Resolve_Case {
		{"g:h", "g:h"},
		{"g", "http://a/b/c/g"},
		{"./g", "http://a/b/c/g"},
		{"g/", "http://a/b/c/g/"},
		{"/g", "http://a/g"},
		{"//g", "http://g"},
		{"?y", "http://a/b/c/d;p?y"},
		{"g?y", "http://a/b/c/g?y"},
		{"#s", "http://a/b/c/d;p?q#s"},
		{"g#s", "http://a/b/c/g#s"},
		{"g?y#s", "http://a/b/c/g?y#s"},
		{";x", "http://a/b/c/;x"},
		{"g;x", "http://a/b/c/g;x"},
		{"g;x?y#s", "http://a/b/c/g;x?y#s"},
		{"", "http://a/b/c/d;p?q"},
		{".", "http://a/b/c/"},
		{"./", "http://a/b/c/"},
		{"..", "http://a/b/"},
		{"../", "http://a/b/"},
		{"../g", "http://a/b/g"},
		{"../..", "http://a/"},
		{"../../", "http://a/"},
		{"../../g", "http://a/g"},
	}
	for c in cases {
		expect_resolve(t, RFC_BASE, c.ref, c.want, alloc)
	}
}

@(test)
test_resolve_rfc3986_abnormal_examples :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	// RFC 3986 section 5.4.2, with the strict reading of "http:g".
	cases := []Resolve_Case {
		{"../../../g", "http://a/g"},
		{"../../../../g", "http://a/g"},
		{"/./g", "http://a/g"},
		{"/../g", "http://a/g"},
		{"g.", "http://a/b/c/g."},
		{".g", "http://a/b/c/.g"},
		{"g..", "http://a/b/c/g.."},
		{"..g", "http://a/b/c/..g"},
		{"./../g", "http://a/b/g"},
		{"./g/.", "http://a/b/c/g/"},
		{"g/./h", "http://a/b/c/g/h"},
		{"g/../h", "http://a/b/c/h"},
		{"g;x=1/./y", "http://a/b/c/g;x=1/y"},
		{"g;x=1/../y", "http://a/b/c/y"},
		{"g?y/./x", "http://a/b/c/g?y/./x"},
		{"g?y/../x", "http://a/b/c/g?y/../x"},
		{"g#s/./x", "http://a/b/c/g#s/./x"},
		{"g#s/../x", "http://a/b/c/g#s/../x"},
		{"http:g", "http:g"},
	}
	for c in cases {
		expect_resolve(t, RFC_BASE, c.ref, c.want, alloc)
	}
}

@(test)
test_resolve_base_with_empty_path :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_resolve(t, "http://a", "g", "http://a/g", alloc)
	expect_resolve(t, "http://a", "?q", "http://a?q", alloc)
	expect_resolve(t, "http://a?x", "", "http://a?x", alloc)
}

@(test)
test_resolve_drops_base_fragment :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_resolve(t, "http://a/b#frag", "", "http://a/b", alloc)
	expect_resolve(t, "http://a/b#frag", "c", "http://a/c", alloc)
	expect_resolve(t, "http://a/b?q#frag", "#", "http://a/b?q#", alloc)
}

@(test)
test_resolve_keeps_reference_authority :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_resolve(t, "https://u@a:1/b/c", "//v@x:2/./y/../z?k", "https://v@x:2/z?k", alloc)
	expect_resolve(t, "https://a/b", "//[::1]:8080", "https://[::1]:8080", alloc)
	expect_resolve(t, "https://u@a:1/b/c", "d", "https://u@a:1/b/d", alloc)
}

@(test)
test_resolve_against_base_without_authority :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_resolve(t, "urn:a:b/c", "d", "urn:a:b/d", alloc)
	expect_resolve(t, "mailto:x@example.com", "?subject=hi", "mailto:x@example.com?subject=hi", alloc)
	expect_resolve(t, "x:a/b", "../..//c", "x:/.//c", alloc)
}

@(test)
test_resolve_absolute_reference_removes_dots :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_resolve(t, RFC_BASE, "https://x/a/./b/../c", "https://x/a/c", alloc)
}

@(test)
test_resolve_requires_absolute_base :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	base, _ := uri.parse("/relative/base", alloc)
	defer uri.destroy(&base)
	ref, _ := uri.parse("g", alloc)
	defer uri.destroy(&ref)
	target, err := uri.resolve(base, ref, alloc)
	defer uri.destroy(&target)
	testing.expect_value(t, err, uri.Error(uri.Resolve_Error.Base_Not_Absolute))

	s, serr := uri.resolve_string("//host/x", "y", alloc)
	defer delete(s, alloc)
	testing.expect_value(t, serr, uri.Error(uri.Resolve_Error.Base_Not_Absolute))
}

@(test)
test_resolve_string_reports_parse_errors :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	s1, e1 := uri.resolve_string("http://h:99999/", "g", alloc)
	delete(s1, alloc)
	testing.expect_value(t, e1, uri.Error(uri.Parse_Error.Port_Out_Of_Range))
	s2, e2 := uri.resolve_string("http://h/", "%zz", alloc)
	delete(s2, alloc)
	testing.expect_value(t, e2, uri.Error(uri.Parse_Error.Invalid_Escape))
}

@(test)
test_remove_dot_segments_examples :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		input, want: string,
	}
	cases := []Case {
		{"/a/b/c/./../../g", "/a/g"},
		{"mid/content=5/../6", "mid/6"},
		{"", ""},
		{".", ""},
		{"..", ""},
		{"/", "/"},
		{"/..", "/"},
		{"/.", "/"},
		{"a/..", "/"},
		{"/a/b/..", "/a/"},
		{"../a/./b", "a/b"},
		{"/a//../b", "/a/b"},
		{"/a/.../b", "/a/.../b"},
	}
	for c in cases {
		got, err := uri.remove_dot_segments(c.input, alloc)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "remove_dot_segments(%q): got %q, want %q", c.input, got, c.want)
		delete(got, alloc)
	}
}
