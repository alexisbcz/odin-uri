/*
Package uri parses, builds, resolves and normalizes URIs as defined by
RFC 3986, and reads and writes `application/x-www-form-urlencoded` queries
without losing the order of repeated keys.

Every component of a parsed URI keeps the exact text of the input, still
percent-encoded. Decode a component with unescape or, for query strings,
with parse_query.

Example:
	import "shared:uri"

	main :: proc() {
		u, err := uri.parse("https://user@example.com:8443/a/b?x=1#top")
		if err != nil {
			return
		}
		defer uri.destroy(&u)
		// u.scheme == "https", u.host == "example.com", u.port.? == 8443
	}
*/
package uri

import "base:runtime"
import "core:strings"

// Parse_Error lists the ways a string can fail to be a URI reference.
Parse_Error :: enum {
	None,
	// The scheme is empty or contains a character outside ALPHA, DIGIT, "+", "-" and ".".
	Invalid_Scheme,
	// The user information before "@" contains a character that is not allowed there.
	Invalid_Userinfo,
	// The host contains a character that is not allowed in a registered name.
	Invalid_Host,
	// The bracketed host is not a valid IPv6 address, zone or IPvFuture literal.
	Invalid_IP_Literal,
	// The port contains a character other than a decimal digit.
	Invalid_Port,
	// The port is made of digits but is larger than 65535.
	Port_Out_Of_Range,
	// The path contains a character that is not allowed in a path.
	Invalid_Path,
	// The query contains a character that is not allowed in a query.
	Invalid_Query,
	// The fragment contains a character that is not allowed in a fragment.
	Invalid_Fragment,
	// A "%" is not followed by two hexadecimal digits.
	Invalid_Escape,
}

// Resolve_Error lists the ways reference resolution can fail.
Resolve_Error :: enum {
	None,
	// The base URI of resolve has no scheme, so it is not an absolute URI.
	Base_Not_Absolute,
}

/*
Error is the compound error type returned by every fallible procedure in this
package. `nil` means success. Compare it against a specific variant such as
`uri.Parse_Error.Invalid_Port`, or use a type switch.
*/
Error :: union #shared_nil {
	Parse_Error,
	Resolve_Error,
	runtime.Allocator_Error,
}

// Host_Kind says which RFC 3986 grammar rule a host matched.
Host_Kind :: enum u8 {
	// A registered name such as "example.com", or an empty host.
	Reg_Name,
	// A dotted-decimal IPv4 address such as "192.0.2.1".
	IPv4,
	// A bracketed IPv6 address such as "[::1]", possibly with a "%25" zone.
	IPv6,
	// A bracketed IPvFuture literal such as "[v1.fe80::a]".
	IP_Future,
}

/*
URI is a parsed URI reference: either an absolute URI with a scheme or a
relative reference without one.

Every string field holds the component exactly as it appeared in the input,
still percent-encoded and without its delimiters. `host` excludes the square
brackets of an IP literal. The `has_*` flags tell an absent component apart
from a present but empty one, so that `http://h/?` and `http://h/` both round
trip through to_string.

A URI returned by parse, clone, resolve or normalize owns one buffer that
backs all of its strings; free it with destroy. Copies of the struct share
that buffer. A URI built by hand as a struct literal owns nothing and needs no
destroy. A value is safe to use from one thread at a time.
*/
URI :: struct {
	scheme:        string,
	user:          string,
	password:      string,
	host:          string,
	port:          Maybe(u16),
	path:          string,
	raw_query:     string,
	fragment:      string,
	host_kind:     Host_Kind,
	// The reference contains "//" followed by an authority, which may be empty.
	has_authority: bool,
	// The authority contains "@", so `user` is present even when empty.
	has_userinfo:  bool,
	// The user information contains ":", so `password` is present even when empty.
	has_password:  bool,
	// The reference contains "?", so `raw_query` is present even when empty.
	has_query:     bool,
	// The reference contains "#", so `fragment` is present even when empty.
	has_fragment:  bool,
	// The memory behind the string fields. Owned by the URI; don't touch it.
	_buf:          [dynamic]byte,
}

/*
parse splits `s` into the components of an RFC 3986 URI reference and checks
every character against the grammar. It accepts absolute URIs such as
`https://example.com/` and relative references such as `../a?b`.

Inputs:
- s: the text to parse. parse copies what it keeps, so `s` may be freed afterwards.
- allocator: allocates the single buffer behind the returned strings.

Returns:
- u: the parsed reference, owned by the caller; free it with destroy.
- err: a Parse_Error naming the first bad component, or an allocator error.
*/
parse :: proc(s: string, allocator := context.allocator) -> (u: URI, err: Error) {
	parts := split(s) or_return
	return clone(parts, allocator)
}

/*
destroy frees the buffer behind the string fields of `u` and zeroes it. It is
safe to call on a zero URI or on one built by hand.
*/
destroy :: proc(u: ^URI) {
	delete(u._buf)
	u^ = {}
}

/*
clone returns a deep copy of `u` whose strings live in one new buffer. Use it
to take ownership of a URI built by hand from borrowed strings.

Returns:
- out: the copy, owned by the caller; free it with destroy.
- err: an allocator error.
*/
clone :: proc(u: URI, allocator := context.allocator) -> (out: URI, err: Error) {
	total := len(u.scheme) + len(u.user) + len(u.password) + len(u.host) + len(u.path) + len(u.raw_query) + len(u.fragment)
	a := assembler_make(total, allocator) or_return
	out = u
	assembler_put(&a, .Scheme, u.scheme)
	assembler_put(&a, .User, u.user)
	assembler_put(&a, .Password, u.password)
	assembler_put(&a, .Host, u.host)
	assembler_put(&a, .Path, u.path)
	assembler_put(&a, .Query, u.raw_query)
	assembler_put(&a, .Fragment, u.fragment)
	assembler_finish(&a, &out)
	return out, nil
}

/*
to_string writes `u` back in RFC 3986 syntax. For a URI that came from parse,
the output equals the input, except that a port with leading zeros or an
empty port (`http://h:/`) is written in its canonical form.

When a hand-built URI would otherwise change meaning, to_string adds the
minimum needed: a "/" between the authority and a relative path, "/." in front
of a path that starts with "//" when there is no authority, and "./" in front
of a relative path whose first segment contains ":".

Returns:
- s: the text, owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error.
*/
to_string :: proc(u: URI, allocator := context.allocator) -> (s: string, err: Error) {
	estimate := len(u.scheme) + len(u.user) + len(u.password) + len(u.host) + len(u.path) + len(u.raw_query) + len(u.fragment) + 16
	b := strings.builder_make_len_cap(0, estimate, allocator) or_return
	write_uri(&b, u)
	return strings.to_string(b), nil
}

// is_absolute reports whether `u` has a scheme, which makes it usable as a base for resolve.
is_absolute :: proc(u: URI) -> bool {
	return u.scheme != ""
}

/*
default_port returns the well-known port of `scheme`, compared without regard
to case: 80 for http and ws, 443 for https and wss, and 21 for ftp.
*/
default_port :: proc(scheme: string) -> (port: u16, ok: bool) {
	DEFAULTS :: [?]struct {
		scheme: string,
		port:   u16,
	}{{"http", 80}, {"https", 443}, {"ws", 80}, {"wss", 443}, {"ftp", 21}}
	for d in DEFAULTS {
		if strings.equal_fold(scheme, d.scheme) {
			return d.port, true
		}
	}
	return 0, false
}

// port_or_default returns the explicit port of `u`, or the default port of its scheme.
port_or_default :: proc(u: URI) -> (port: u16, ok: bool) {
	if p, has := u.port.?; has {
		return p, true
	}
	return default_port(u.scheme)
}

@(private)
has_authority_part :: proc(u: URI) -> bool {
	return u.has_authority || u.host != "" || u.port != nil || has_userinfo_part(u)
}

@(private)
has_userinfo_part :: proc(u: URI) -> bool {
	return u.has_userinfo || u.user != "" || has_password_part(u)
}

@(private)
has_password_part :: proc(u: URI) -> bool {
	return u.has_password || u.password != ""
}

@(private)
write_uri :: proc(b: ^strings.Builder, u: URI) {
	if u.scheme != "" {
		strings.write_string(b, u.scheme)
		strings.write_byte(b, ':')
	}
	if has_authority_part(u) {
		strings.write_string(b, "//")
		if has_userinfo_part(u) {
			strings.write_string(b, u.user)
			if has_password_part(u) {
				strings.write_byte(b, ':')
				strings.write_string(b, u.password)
			}
			strings.write_byte(b, '@')
		}
		bracket := u.host_kind == .IPv6 || u.host_kind == .IP_Future || strings.index_byte(u.host, ':') >= 0
		if bracket {
			strings.write_byte(b, '[')
		}
		strings.write_string(b, u.host)
		if bracket {
			strings.write_byte(b, ']')
		}
		if p, ok := u.port.?; ok {
			strings.write_byte(b, ':')
			strings.write_uint(b, uint(p))
		}
		if u.path != "" && u.path[0] != '/' {
			strings.write_byte(b, '/')
		}
	} else if strings.has_prefix(u.path, "//") {
		strings.write_string(b, "/.")
	} else if u.scheme == "" {
		first := u.path
		if i := strings.index_byte(first, '/'); i >= 0 {
			first = first[:i]
		}
		if strings.index_byte(first, ':') >= 0 {
			strings.write_string(b, "./")
		}
	}
	strings.write_string(b, u.path)
	if u.has_query || u.raw_query != "" {
		strings.write_byte(b, '?')
		strings.write_string(b, u.raw_query)
	}
	if u.has_fragment || u.fragment != "" {
		strings.write_byte(b, '#')
		strings.write_string(b, u.fragment)
	}
}

// Component names the string fields of a URI, in buffer order.
@(private)
Component :: enum u8 {
	Scheme,
	User,
	Password,
	Host,
	Path,
	Query,
	Fragment,
}

/*
Assembler writes the string components of a new URI into one buffer. The
capacity given to assembler_make must be an upper bound of the total length,
so the buffer never moves while components are written.
*/
@(private)
Assembler :: struct {
	buf:   [dynamic]byte,
	spans: [Component][2]int,
}

@(private)
assembler_make :: proc(capacity: int, allocator: runtime.Allocator) -> (a: Assembler, err: runtime.Allocator_Error) {
	a.buf = make([dynamic]byte, 0, capacity, allocator) or_return
	return
}

@(private)
assembler_begin :: proc(a: ^Assembler, c: Component) {
	a.spans[c][0] = len(a.buf)
}

@(private)
assembler_end :: proc(a: ^Assembler, c: Component) {
	a.spans[c][1] = len(a.buf)
}

@(private)
assembler_put :: proc(a: ^Assembler, c: Component, s: string) {
	assembler_begin(a, c)
	append(&a.buf, s)
	assembler_end(a, c)
}

@(private)
assembler_finish :: proc(a: ^Assembler, u: ^URI) {
	get :: proc(a: ^Assembler, c: Component) -> string {
		return string(a.buf[a.spans[c][0]:a.spans[c][1]])
	}
	u.scheme = get(a, .Scheme)
	u.user = get(a, .User)
	u.password = get(a, .Password)
	u.host = get(a, .Host)
	u.path = get(a, .Path)
	u.raw_query = get(a, .Query)
	u.fragment = get(a, .Fragment)
	u._buf = a.buf
}
