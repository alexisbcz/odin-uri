package uri_tests

import uri ".."
import "core:testing"

expect_pairs :: proc(t: ^testing.T, q: uri.Query, want: [][2]string, loc := #caller_location) {
	if !testing.expectf(t, len(q) == len(want), "got %d pairs %v, want %d", len(q), q, len(want), loc = loc) {
		return
	}
	for pair, i in q {
		testing.expectf(t, pair == want[i], "pair %d: got %q, want %q", i, pair, want[i], loc = loc)
	}
}

@(test)
test_parse_query_keeps_duplicates_in_order :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, err := uri.parse_query("b=2&a=1&b=3&a=4", alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, err, nil)
	expect_pairs(t, q, {{"b", "2"}, {"a", "1"}, {"b", "3"}, {"a", "4"}})
}

@(test)
test_parse_query_keeps_empty_keys_and_values :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, err := uri.parse_query("=v&k=&flag&=&&x=1=2&", alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, err, nil)
	expect_pairs(t, q, {{"", "v"}, {"k", ""}, {"flag", ""}, {"", ""}, {"x", "1=2"}})
}

@(test)
test_parse_query_decodes_form_encoding :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, err := uri.parse_query("q=odin+lang&path=%2Fa%2Fb&plus=%2B&semi=a;b&caf%C3%A9=%E2%82%AC", alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, err, nil)
	expect_pairs(t, q, {{"q", "odin lang"}, {"path", "/a/b"}, {"plus", "+"}, {"semi", "a;b"}, {"caf\xc3\xa9", "\xe2\x82\xac"}})
}

@(test)
test_parse_query_empty_string :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, err := uri.parse_query("", alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(q), 0)
}

@(test)
test_parse_query_rejects_bad_escapes_without_leaking :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	for raw in ([]string{"a=1&b=%zz", "a=1&%4=b", "ok=1&x=%", "%"}) {
		q, err := uri.parse_query(raw, alloc)
		testing.expectf(t, err == uri.Error(uri.Parse_Error.Invalid_Escape), "parse_query(%q): got %v", raw, err)
		testing.expect_value(t, len(q), 0)
		uri.query_destroy(&q)
	}
}

@(test)
test_query_get_returns_first_value :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, _ := uri.parse_query("a=1&a=2&b=", alloc)
	defer uri.query_destroy(&q)
	v, ok := uri.query_get(q, "a")
	testing.expect(t, ok)
	testing.expect_value(t, v, "1")
	empty, has_b := uri.query_get(q, "b")
	testing.expect(t, has_b)
	testing.expect_value(t, empty, "")
	_, has_c := uri.query_get(q, "c")
	testing.expect(t, !has_c)
	testing.expect(t, uri.query_has(q, "b"))
	testing.expect(t, !uri.query_has(q, "A"))
}

@(test)
test_query_get_all_returns_values_in_order :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, _ := uri.parse_query("tag=x&id=1&tag=y&tag=", alloc)
	defer uri.query_destroy(&q)
	tags, err := uri.query_get_all(q, "tag", alloc)
	defer delete(tags, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(tags), 3)
	if len(tags) == 3 {
		testing.expect_value(t, tags[0], "x")
		testing.expect_value(t, tags[1], "y")
		testing.expect_value(t, tags[2], "")
	}
	none, _ := uri.query_get_all(q, "missing", alloc)
	defer delete(none, alloc)
	testing.expect_value(t, len(none), 0)
}

@(test)
test_query_add_copies_strings :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q := make(uri.Query, alloc)
	defer uri.query_destroy(&q)
	key := make([]byte, 1, alloc)
	key[0] = 'k'
	testing.expect_value(t, uri.query_add(&q, string(key), "1"), nil)
	testing.expect_value(t, uri.query_add(&q, string(key), "2"), nil)
	delete(key, alloc)
	expect_pairs(t, q, {{"k", "1"}, {"k", "2"}})
}

@(test)
test_query_add_on_zero_query_uses_context_allocator :: proc(t: ^testing.T) {
	lc: Leak_Check
	context.allocator = tracked(t, &lc)
	q: uri.Query
	defer uri.query_destroy(&q)
	testing.expect_value(t, uri.query_add(&q, "a", "1"), nil)
	testing.expect_value(t, uri.query_set(&q, "b", "2"), nil)
	expect_pairs(t, q, {{"a", "1"}, {"b", "2"}})
}

@(test)
test_query_set_replaces_first_and_removes_rest :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, _ := uri.parse_query("a=1&b=2&a=3&c=4&a=5", alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, uri.query_set(&q, "a", "new"), nil)
	expect_pairs(t, q, {{"a", "new"}, {"b", "2"}, {"c", "4"}})
	testing.expect_value(t, uri.query_set(&q, "d", "appended"), nil)
	expect_pairs(t, q, {{"a", "new"}, {"b", "2"}, {"c", "4"}, {"d", "appended"}})
}

@(test)
test_query_del_removes_every_match :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q, _ := uri.parse_query("a=1&b=2&a=3&c=4&a=5", alloc)
	defer uri.query_destroy(&q)
	uri.query_del(&q, "a")
	expect_pairs(t, q, {{"b", "2"}, {"c", "4"}})
	uri.query_del(&q, "missing")
	expect_pairs(t, q, {{"b", "2"}, {"c", "4"}})
}

@(test)
test_query_encode_keeps_order_and_escapes :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q := make(uri.Query, alloc)
	defer uri.query_destroy(&q)
	uri.query_add(&q, "z", "last first")
	uri.query_add(&q, "a&b", "1+1=2")
	uri.query_add(&q, "", "")
	uri.query_add(&q, "z", "again")
	s, err := uri.query_encode(q, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, s, "z=last+first&a%26b=1%2B1%3D2&=&z=again")
}

@(test)
test_query_encode_empty :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	q: uri.Query
	s, err := uri.query_encode(q, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, s, "")
}

@(test)
test_query_parse_encode_round_trip :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	raw :: "q=odin+lang&lang=en&lang=fr&empty=&=anon&path=%2Fa%3Fb"
	q, err := uri.parse_query(raw, alloc)
	defer uri.query_destroy(&q)
	testing.expect_value(t, err, nil)
	s, _ := uri.query_encode(q, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, s, raw)

	u, perr := uri.parse("https://example.com/search?" + raw, alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, perr, nil)
	testing.expect_value(t, u.raw_query, s)
}
