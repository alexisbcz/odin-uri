package uri_tests

import uri ".."
import "core:testing"

@(test)
test_normalize_lowercases_scheme_and_host :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "HTTP://User@Example.COM/Path", "http://User@example.com/Path", alloc)
	expect_normalized(t, "http://[FE80::A]/", "http://[fe80::a]/", alloc)
}

@(test)
test_normalize_decodes_unreserved_escapes :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "http://example.com/%7Efoo/%41%2d%5F%2E", "http://example.com/~foo/A-_.", alloc)
	expect_normalized(t, "http://%61%62c.com/?%7a=%31#%7E", "http://abc.com/?z=1#~", alloc)
	expect_normalized(t, "http://%41.com/", "http://a.com/", alloc)
}

@(test)
test_normalize_uppercases_other_escapes :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "http://h/a%2fb%c3%a9?x=%2b", "http://h/a%2Fb%C3%A9?x=%2B", alloc)
	expect_normalized(t, "http://h/%25", "http://h/%25", alloc)
}

@(test)
test_normalize_drops_default_ports :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "http://h:80/", "http://h/", alloc)
	expect_normalized(t, "HTTPS://h:443/", "https://h/", alloc)
	expect_normalized(t, "wss://h:443/", "wss://h/", alloc)
	expect_normalized(t, "ftp://h:21/", "ftp://h/", alloc)
	expect_normalized(t, "http://h:8080/", "http://h:8080/", alloc)
	expect_normalized(t, "https://h:80/", "https://h:80/", alloc)
	expect_normalized(t, "gopher://h:70/", "gopher://h:70/", alloc)
}

@(test)
test_normalize_paths :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "http://h", "http://h/", alloc)
	expect_normalized(t, "http://h?q", "http://h/?q", alloc)
	expect_normalized(t, "http://h/a/./b/../c", "http://h/a/c", alloc)
	expect_normalized(t, "http://h/a/%2E%2E/b", "http://h/b", alloc)
	expect_normalized(t, "../a/./b", "../a/./b", alloc)
	expect_normalized(t, "/a/../b", "/b", alloc)
}

@(test)
test_normalize_is_idempotent :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	for input in CORPUS {
		u, err := uri.parse(input, alloc)
		testing.expect_value(t, err, nil)
		once, _ := uri.normalize(u, alloc)
		twice, _ := uri.normalize(once, alloc)
		a, _ := uri.to_string(once, alloc)
		b, _ := uri.to_string(twice, alloc)
		testing.expectf(t, a == b, "normalize not idempotent for %q: %q then %q", input, a, b)
		delete(a, alloc)
		delete(b, alloc)
		uri.destroy(&twice)
		uri.destroy(&once)
		uri.destroy(&u)
	}
}

@(test)
test_normalize_makes_equivalent_uris_equal :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	expect_normalized(t, "HTTP://www.Example.com:80/%7euser/./docs/../index.html", "http://www.example.com/~user/index.html", alloc)
	expect_normalized(t, "http://www.example.com/~user/index.html", "http://www.example.com/~user/index.html", alloc)
}
