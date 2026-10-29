package uri_tests

import uri ".."
import "core:testing"

Escape_Case :: struct {
	input, want: string,
}

@(test)
test_escape_path_matches_go_path_escape :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	// Expected values come from Go's url.PathEscape.
	cases := []Escape_Case {
		{"", ""},
		{"abc", "abc"},
		{"-_.~AZaz09", "-_.~AZaz09"},
		{"a b", "a%20b"},
		{"a/b", "a%2Fb"},
		{"a;b,c?d", "a%3Bb%2Cc%3Fd"},
		{"$&+:=@", "$&+:=@"},
		{"!'()*", "%21%27%28%29%2A"},
		{"#%", "%23%25"},
		{"caf\xc3\xa9", "caf%C3%A9"},
		{"\x00\x7f\xff", "%00%7F%FF"},
	}
	for c in cases {
		got, err := uri.escape_path(c.input, alloc)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "escape_path(%q): got %q, want %q", c.input, got, c.want)
		delete(got, alloc)
	}
}

@(test)
test_escape_query_component_matches_go_query_escape :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	// Expected values come from Go's url.QueryEscape.
	cases := []Escape_Case {
		{"", ""},
		{"a b", "a+b"},
		{"a+b", "a%2Bb"},
		{"a&b=c", "a%26b%3Dc"},
		{"/?#[]@", "%2F%3F%23%5B%5D%40"},
		{"$,;:", "%24%2C%3B%3A"},
		{"!*'()", "%21%2A%27%28%29"},
		{"-_.~", "-_.~"},
		{"\xe2\x82\xac 5", "%E2%82%AC+5"},
	}
	for c in cases {
		got, err := uri.escape_query_component(c.input, alloc)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "escape_query_component(%q): got %q, want %q", c.input, got, c.want)
		delete(got, alloc)
	}
}

@(test)
test_unescape_keeps_plus :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	cases := []Escape_Case {
		{"", ""},
		{"plain", "plain"},
		{"a+b%20c", "a+b c"},
		{"%2F%2f", "//"},
		{"%C3%A9", "\xc3\xa9"},
		{"%00", "\x00"},
	}
	for c in cases {
		got, err := uri.unescape(c.input, alloc)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "unescape(%q): got %q, want %q", c.input, got, c.want)
		delete(got, alloc)
	}
}

@(test)
test_unescape_query_component_turns_plus_into_space :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	got, err := uri.unescape_query_component("a+b%20c%2B", alloc)
	defer delete(got, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, got, "a b c+")
}

@(test)
test_unescape_rejects_bad_escapes :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	for input in ([]string{"%", "%4", "%zz", "a%g1", "abc%", "%%41"}) {
		got, err := uri.unescape(input, alloc)
		testing.expectf(t, err == uri.Error(uri.Parse_Error.Invalid_Escape), "unescape(%q): got %v", input, err)
		testing.expect_value(t, got, "")
		qgot, qerr := uri.unescape_query_component(input, alloc)
		testing.expectf(t, qerr == uri.Error(uri.Parse_Error.Invalid_Escape), "unescape_query_component(%q): got %v", input, qerr)
		testing.expect_value(t, qgot, "")
	}
}

@(test)
test_escape_then_unescape_round_trips_every_byte :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	all: [256]byte
	for i in 0 ..< 256 {
		all[i] = byte(i)
	}
	input := string(all[:])

	p, _ := uri.escape_path(input, alloc)
	defer delete(p, alloc)
	pback, perr := uri.unescape(p, alloc)
	defer delete(pback, alloc)
	testing.expect_value(t, perr, nil)
	testing.expect(t, pback == input)

	q, _ := uri.escape_query_component(input, alloc)
	defer delete(q, alloc)
	qback, qerr := uri.unescape_query_component(q, alloc)
	defer delete(qback, alloc)
	testing.expect_value(t, qerr, nil)
	testing.expect(t, qback == input)
}

@(test)
test_escaped_segment_is_a_valid_path :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	segment, _ := uri.escape_path("reports/2026 Q3?.pdf", alloc)
	defer delete(segment, alloc)
	testing.expect_value(t, segment, "reports%2F2026%20Q3%3F.pdf")
	u := uri.URI {
		scheme = "https",
		host   = "files.example.com",
		path   = segment,
	}
	s, _ := uri.to_string(u, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, s, "https://files.example.com/reports%2F2026%20Q3%3F.pdf")
	back, err := uri.parse(s, alloc)
	defer uri.destroy(&back)
	testing.expect_value(t, err, nil)
}
