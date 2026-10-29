package uri_tests

import uri ".."
import "core:testing"

@(test)
test_parse_full_uri_components :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("https://alice:s3cret@example.com:8443/a/b%20c?x=1&x=2#top", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, u.scheme, "https")
	testing.expect_value(t, u.user, "alice")
	testing.expect_value(t, u.password, "s3cret")
	testing.expect_value(t, u.host, "example.com")
	testing.expect_value(t, u.port.?, 8443)
	testing.expect_value(t, u.path, "/a/b%20c")
	testing.expect_value(t, u.raw_query, "x=1&x=2")
	testing.expect_value(t, u.fragment, "top")
	testing.expect_value(t, u.host_kind, uri.Host_Kind.Reg_Name)
	testing.expect(t, u.has_authority && u.has_userinfo && u.has_password && u.has_query && u.has_fragment)
}

@(test)
test_parse_copies_input :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	input := make([]byte, len("http://h/p"), alloc)
	copy(input, "http://h/p")
	u, err := uri.parse(string(input), alloc)
	defer uri.destroy(&u)
	delete(input, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, u.host, "h")
	testing.expect_value(t, u.path, "/p")
}

@(test)
test_parse_without_port_has_nil_port :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("http://example.com/", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect(t, u.port == nil)
	port, ok := uri.port_or_default(u)
	testing.expect(t, ok)
	testing.expect_value(t, port, 80)
}

@(test)
test_parse_empty_port_means_no_port :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("http://example.com:/x", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, u.host, "example.com")
	testing.expect(t, u.port == nil)
}

@(test)
test_parse_port_bounds :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	low, low_err := uri.parse("http://h:0/", alloc)
	defer uri.destroy(&low)
	testing.expect_value(t, low_err, nil)
	testing.expect_value(t, low.port.?, 0)

	high, high_err := uri.parse("http://h:65535/", alloc)
	defer uri.destroy(&high)
	testing.expect_value(t, high_err, nil)
	testing.expect_value(t, high.port.?, 65535)

	padded, padded_err := uri.parse("http://h:00080/", alloc)
	defer uri.destroy(&padded)
	testing.expect_value(t, padded_err, nil)
	testing.expect_value(t, padded.port.?, 80)
}

@(test)
test_parse_rejects_invalid_ports :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://h:80a/", .Invalid_Port)
	expect_parse_error(t, "http://h:-1/", .Invalid_Port)
	expect_parse_error(t, "http://h: 80/", .Invalid_Port)
	expect_parse_error(t, "http://h:+80/", .Invalid_Port)
	expect_parse_error(t, "http://[::1]:x/", .Invalid_Port)
}

@(test)
test_parse_rejects_port_out_of_range :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://h:65536/", .Port_Out_Of_Range)
	expect_parse_error(t, "http://h:99999999999999999999/", .Port_Out_Of_Range)
	expect_parse_error(t, "http://[::1]:70000/", .Port_Out_Of_Range)
}

@(test)
test_parse_ipv6_hosts :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		input, host: string,
		port:        Maybe(u16),
	}
	cases := []Case {
		{"http://[::1]/", "::1", nil},
		{"http://[::1]:8080/", "::1", 8080},
		{"http://[2001:db8::7]/c=GB", "2001:db8::7", nil},
		{"http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]/", "2001:0db8:85a3:0000:0000:8a2e:0370:7334", nil},
		{"http://[::]/", "::", nil},
		{"http://[1::]/", "1::", nil},
		{"http://[::ffff:192.0.2.128]:443/", "::ffff:192.0.2.128", 443},
		{"http://[1:2:3:4:5:6:1.2.3.4]/", "1:2:3:4:5:6:1.2.3.4", nil},
		{"http://[FE80::A:B]/", "FE80::A:B", nil},
	}
	for c in cases {
		u, err := uri.parse(c.input, alloc)
		testing.expectf(t, err == nil, "parse(%q): %v", c.input, err)
		testing.expectf(t, u.host == c.host, "host of %q: got %q", c.input, u.host)
		testing.expectf(t, u.port == c.port, "port of %q: got %v", c.input, u.port)
		testing.expectf(t, u.host_kind == .IPv6, "host kind of %q: got %v", c.input, u.host_kind)
		uri.destroy(&u)
	}
}

@(test)
test_parse_ipv6_zone_and_ip_future :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	zoned, zerr := uri.parse("http://[fe80::1%25en0]:80/", alloc)
	defer uri.destroy(&zoned)
	testing.expect_value(t, zerr, nil)
	testing.expect_value(t, zoned.host, "fe80::1%25en0")
	testing.expect_value(t, zoned.host_kind, uri.Host_Kind.IPv6)

	future, ferr := uri.parse("http://[v7.fe80::a+en1]/", alloc)
	defer uri.destroy(&future)
	testing.expect_value(t, ferr, nil)
	testing.expect_value(t, future.host, "v7.fe80::a+en1")
	testing.expect_value(t, future.host_kind, uri.Host_Kind.IP_Future)
}

@(test)
test_parse_rejects_bad_ip_literals :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://[::1/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[:::]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[1::2::3]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[1:2:3:4:5:6:7]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[1:2:3:4:5:6:7:8:9]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[12345::]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[::g]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[::1.2.3.256]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[1.2.3.4::]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[fe80::1%en0]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[fe80::1%25]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[v7]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[v.x]/", .Invalid_IP_Literal)
	expect_parse_error(t, "http://[::1]x/", .Invalid_Host)
}

@(test)
test_parse_ipv4_host_kind :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		input: string,
		kind:  uri.Host_Kind,
	}
	cases := []Case {
		{"http://192.0.2.16:80/", .IPv4},
		{"http://0.0.0.0/", .IPv4},
		{"http://255.255.255.255/", .IPv4},
		{"http://256.1.1.1/", .Reg_Name},
		{"http://01.2.3.4/", .Reg_Name},
		{"http://1.2.3/", .Reg_Name},
		{"http://1.2.3.4.5/", .Reg_Name},
	}
	for c in cases {
		u, err := uri.parse(c.input, alloc)
		testing.expectf(t, err == nil, "parse(%q): %v", c.input, err)
		testing.expectf(t, u.host_kind == c.kind, "host kind of %q: got %v, want %v", c.input, u.host_kind, c.kind)
		uri.destroy(&u)
	}
}

@(test)
test_parse_userinfo_variants :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	Case :: struct {
		input, user, password:      string,
		has_userinfo, has_password: bool,
	}
	cases := []Case {
		{"http://host/", "", "", false, false},
		{"http://@host/", "", "", true, false},
		{"http://bob@host/", "bob", "", true, false},
		{"http://bob:@host/", "bob", "", true, true},
		{"http://:pw@host/", "", "pw", true, true},
		{"http://bob:a:b@host/", "bob", "a:b", true, true},
		{"http://b%40b:p%3Aw@host/", "b%40b", "p%3Aw", true, true},
	}
	for c in cases {
		u, err := uri.parse(c.input, alloc)
		testing.expectf(t, err == nil, "parse(%q): %v", c.input, err)
		testing.expectf(t, u.user == c.user && u.password == c.password, "userinfo of %q: got %q %q", c.input, u.user, u.password)
		testing.expectf(t, u.has_userinfo == c.has_userinfo && u.has_password == c.has_password, "flags of %q", c.input)
		testing.expect_value(t, u.host, "host")
		uri.destroy(&u)
	}
}

@(test)
test_parse_rejects_bad_userinfo :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://a@b@host/", .Invalid_Userinfo)
	expect_parse_error(t, "http://a b@host/", .Invalid_Userinfo)
	expect_parse_error(t, "http://[x]@host/", .Invalid_Userinfo)
}

@(test)
test_parse_rejects_bad_hosts :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://exa mple.com/", .Invalid_Host)
	expect_parse_error(t, "http://a:b:c/", .Invalid_Host)
	expect_parse_error(t, "http://ex<ample/", .Invalid_Host)
	expect_parse_error(t, "http://h]/", .Invalid_Host)
}

@(test)
test_parse_rejects_bad_percent_escapes :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://h/a%", .Invalid_Escape)
	expect_parse_error(t, "http://h/a%2", .Invalid_Escape)
	expect_parse_error(t, "http://h/a%zz", .Invalid_Escape)
	expect_parse_error(t, "http://h/a%2g/b", .Invalid_Escape)
	expect_parse_error(t, "http://h/?q=%", .Invalid_Escape)
	expect_parse_error(t, "http://h/#%x1", .Invalid_Escape)
	expect_parse_error(t, "http://%zz@h/", .Invalid_Escape)
	expect_parse_error(t, "http://h%2/", .Invalid_Escape)
	expect_parse_error(t, "%", .Invalid_Escape)
}

@(test)
test_parse_rejects_bad_schemes :: proc(t: ^testing.T) {
	expect_parse_error(t, ":no-scheme", .Invalid_Scheme)
	expect_parse_error(t, "1http://h/", .Invalid_Scheme)
	expect_parse_error(t, "ht_tp://h/", .Invalid_Scheme)
	expect_parse_error(t, "ht tp://h/", .Invalid_Scheme)
	expect_parse_error(t, "-a:b", .Invalid_Scheme)
}

@(test)
test_parse_accepts_scheme_characters :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("git+ssh.v2-x://git@github.com/a.git", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, u.scheme, "git+ssh.v2-x")
	testing.expect_value(t, u.user, "git")
}

@(test)
test_parse_rejects_bad_path_query_fragment :: proc(t: ^testing.T) {
	expect_parse_error(t, "http://h/a b", .Invalid_Path)
	expect_parse_error(t, "http://h/a\"b", .Invalid_Path)
	expect_parse_error(t, "http://h/a\x00", .Invalid_Path)
	expect_parse_error(t, "http://h/caf\xc3\xa9", .Invalid_Path)
	expect_parse_error(t, "http://h/?a b", .Invalid_Query)
	expect_parse_error(t, "http://h/?a[]=1", .Invalid_Query)
	expect_parse_error(t, "http://h/#a b", .Invalid_Fragment)
	expect_parse_error(t, "http://h/#a#b", .Invalid_Fragment)
}

@(test)
test_parse_relative_references :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)

	net, nerr := uri.parse("//cdn.example.com/lib.js", alloc)
	defer uri.destroy(&net)
	testing.expect_value(t, nerr, nil)
	testing.expect_value(t, net.scheme, "")
	testing.expect_value(t, net.host, "cdn.example.com")
	testing.expect(t, !uri.is_absolute(net))

	rel, rerr := uri.parse("../a/b?c#d", alloc)
	defer uri.destroy(&rel)
	testing.expect_value(t, rerr, nil)
	testing.expect(t, !rel.has_authority)
	testing.expect_value(t, rel.path, "../a/b")
	testing.expect_value(t, rel.raw_query, "c")
	testing.expect_value(t, rel.fragment, "d")

	colon, cerr := uri.parse("./a:b", alloc)
	defer uri.destroy(&colon)
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, colon.path, "./a:b")
}

@(test)
test_parse_empty_string :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect(t, !u.has_authority && !u.has_query && !u.has_fragment)
	testing.expect_value(t, u.path, "")
}

@(test)
test_parse_opaque_uris :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	mail, merr := uri.parse("mailto:John.Doe@example.com", alloc)
	defer uri.destroy(&mail)
	testing.expect_value(t, merr, nil)
	testing.expect_value(t, mail.scheme, "mailto")
	testing.expect(t, !mail.has_authority)
	testing.expect_value(t, mail.path, "John.Doe@example.com")

	urn, uerr := uri.parse("urn:oasis:names:specification:docbook:dtd:xml:4.1.2", alloc)
	defer uri.destroy(&urn)
	testing.expect_value(t, uerr, nil)
	testing.expect_value(t, urn.scheme, "urn")
	testing.expect_value(t, urn.path, "oasis:names:specification:docbook:dtd:xml:4.1.2")
}

@(test)
test_parse_empty_query_and_fragment_flags :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("http://h/p?#", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect(t, u.has_query && u.raw_query == "")
	testing.expect(t, u.has_fragment && u.fragment == "")

	v, verr := uri.parse("http://h/p", alloc)
	defer uri.destroy(&v)
	testing.expect_value(t, verr, nil)
	testing.expect(t, !v.has_query && !v.has_fragment)
}

@(test)
test_parse_file_uri_with_empty_host :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("file:///etc/hosts", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect(t, u.has_authority)
	testing.expect_value(t, u.host, "")
	testing.expect_value(t, u.path, "/etc/hosts")
}

@(test)
test_parse_query_may_contain_slash_and_question_mark :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	u, err := uri.parse("http://h/p?next=/a?b=c#x/y?z", alloc)
	defer uri.destroy(&u)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, u.path, "/p")
	testing.expect_value(t, u.raw_query, "next=/a?b=c")
	testing.expect_value(t, u.fragment, "x/y?z")
}
