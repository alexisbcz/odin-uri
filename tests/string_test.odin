package uri_tests

import uri ".."
import "core:testing"

// CORPUS holds URIs that parse and print back unchanged.
CORPUS := [?]string {
	"",
	"https://example.com",
	"https://example.com/",
	"http://user:pass@example.com:8080/path/to?x=1&y=2#frag",
	"http://user@example.com/",
	"http://:pass@example.com/",
	"http://user:@example.com/",
	"http://@example.com/",
	"ftp://ftp.is.co.za/rfc/rfc1808.txt",
	"http://www.ietf.org/rfc/rfc2396.txt",
	"ldap://[2001:db8::7]/c=GB?objectClass?one",
	"mailto:John.Doe@example.com",
	"news:comp.infosystems.www.servers.unix",
	"tel:+1-816-555-1212",
	"telnet://192.0.2.16:80/",
	"urn:oasis:names:specification:docbook:dtd:xml:4.1.2",
	"file:///etc/hosts",
	"file://localhost/etc/fstab",
	"http://[::1]:8080/",
	"http://[fe80::1%25en0]/",
	"http://[v7.fe80::a+en1]/",
	"http://[::ffff:192.0.2.128]/",
	"//example.com/path",
	"//",
	"/absolute/path",
	"relative/path",
	"../up/one",
	"./a:b",
	"?query-only",
	"#fragment-only",
	"http://example.com/?",
	"http://example.com/#",
	"http://example.com?#",
	"http://example.com/a%20b/c%2Fd",
	"https://example.com/search?q=odin+lang&lang=en&lang=fr",
	"s3://bucket/key/with/slashes",
	"git+ssh://git@github.com/alexisbcz/odin-uri.git",
	"data:text/plain;charset=utf-8,hello%20world",
	"about:blank",
	"http://a/b/c/d;p?q",
	"http://example.com/~user/index.html",
	"magnet:?xt=urn:btih:abc&dn=name",
	"HTTP://EXAMPLE.COM/%7Efoo",
	"http://example.com:65535/a/./b/../c",
	"ws://localhost:9000/socket?token=a%2Bb",
	"redis://:hunter2@cache.internal:6379/0",
	"postgres://app:pw@db.example.com:5432/main?sslmode=require",
	"x:",
	"x://",
}

@(test)
test_round_trip_corpus :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	testing.expect(t, len(CORPUS) >= 30)
	for input in CORPUS {
		expect_round_trip(t, input, alloc)
	}
}

@(test)
test_to_string_canonical_port :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		input, want: string,
	}
	cases := []Case{{"http://h:/p", "http://h/p"}, {"http://h:0080/p", "http://h:80/p"}}
	for c in cases {
		u, err := uri.parse(c.input, alloc)
		testing.expect_value(t, err, nil)
		s, _ := uri.to_string(u, alloc)
		testing.expect_value(t, s, c.want)
		delete(s, alloc)
		uri.destroy(&u)
	}
}

@(test)
test_to_string_hand_built :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u := uri.URI {
		scheme    = "https",
		user      = "me",
		host      = "2001:db8::1",
		port      = 443,
		path      = "v1/items",
		raw_query = "limit=10",
		fragment  = "end",
	}
	s, err := uri.to_string(u, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, s, "https://me@[2001:db8::1]:443/v1/items?limit=10#end")
}

@(test)
test_to_string_protects_ambiguous_paths :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		u:    uri.URI,
		want: string,
	}
	cases := []Case {
		{{scheme = "x", path = "//not-a-host/p"}, "x:/.//not-a-host/p"},
		{{path = "a:b/c"}, "./a:b/c"},
		{{path = "a/b:c"}, "a/b:c"},
		{{scheme = "x", path = "a:b"}, "x:a:b"},
	}
	for c in cases {
		s, err := uri.to_string(c.u, alloc)
		testing.expect_value(t, err, nil)
		testing.expect_value(t, s, c.want)

		back, perr := uri.parse(s, alloc)
		testing.expectf(t, perr == nil, "reparse(%q): %v", s, perr)
		testing.expect_value(t, back.has_authority, false)
		uri.destroy(&back)
		delete(s, alloc)
	}
}

@(test)
test_clone_is_independent :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	original, err := uri.parse("http://u:p@h:1/p?q#f", alloc)
	testing.expect_value(t, err, nil)
	copy_, cerr := uri.clone(original, alloc)
	defer uri.destroy(&copy_)
	testing.expect_value(t, cerr, nil)
	uri.destroy(&original)

	s, _ := uri.to_string(copy_, alloc)
	defer delete(s, alloc)
	testing.expect_value(t, s, "http://u:p@h:1/p?q#f")
}

@(test)
test_destroy_zero_and_hand_built :: proc(t: ^testing.T) {
	zero: uri.URI
	uri.destroy(&zero)
	hand := uri.URI {
		scheme = "a",
		path   = "b",
	}
	uri.destroy(&hand)
	testing.expect_value(t, hand.scheme, "")
}

@(test)
test_default_port_table :: proc(t: ^testing.T) {
	Case :: struct {
		scheme: string,
		port:   u16,
		ok:     bool,
	}
	cases := []Case{{"http", 80, true}, {"HTTPS", 443, true}, {"ws", 80, true}, {"wss", 443, true}, {"ftp", 21, true}, {"gopher", 0, false}}
	for c in cases {
		port, ok := uri.default_port(c.scheme)
		testing.expectf(t, port == c.port && ok == c.ok, "default_port(%q) = %v, %v", c.scheme, port, ok)
	}
}
