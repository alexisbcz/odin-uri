package uri

import "core:strings"

/*
resolve turns the reference `ref` into a target URI using `base`, following
the strict algorithm of RFC 3986 section 5.2: a reference with a scheme is
used as is, apart from removing its dot segments, even when its scheme equals
the base scheme.

Inputs:
- base: an absolute URI, which must have a scheme. Its fragment is ignored.
- ref: the reference to resolve, absolute or relative.
- allocator: allocates the result and scratch space, which is freed before returning.

Returns:
- target: the resolved URI, owned by the caller; free it with destroy.
- err: `.Base_Not_Absolute` when `base` has no scheme, or an allocator error.
*/
resolve :: proc(base, ref: URI, allocator := context.allocator) -> (target: URI, err: Error) {
	if base.scheme == "" {
		return {}, .Base_Not_Absolute
	}

	path := make([dynamic]byte, 0, len(base.path) + len(ref.path) + 1, allocator) or_return
	defer delete(path)

	t: URI
	if ref.scheme != "" {
		t = ref
		remove_dots_into(&path, ref.path)
	} else {
		if has_authority_part(ref) {
			copy_authority(&t, ref)
			remove_dots_into(&path, ref.path)
			copy_query(&t, ref)
		} else {
			copy_authority(&t, base)
			if ref.path == "" {
				append(&path, base.path)
				if ref.has_query || ref.raw_query != "" {
					copy_query(&t, ref)
				} else {
					copy_query(&t, base)
				}
			} else {
				if ref.path[0] == '/' {
					remove_dots_into(&path, ref.path)
				} else {
					merged := merge_paths(base, ref.path, allocator) or_return
					defer delete(merged, allocator)
					remove_dots_into(&path, merged)
				}
				copy_query(&t, ref)
			}
		}
		t.scheme = base.scheme
	}
	t.fragment = ref.fragment
	t.has_fragment = ref.has_fragment || ref.fragment != ""
	t.path = string(path[:])
	return clone(t, allocator)
}

/*
resolve_string parses `base` and `ref`, resolves `ref` against `base` and
returns the target as text. It is a shortcut for parse, resolve and to_string.

Returns:
- target: the resolved URI as text, owned by the caller; free it with `delete(target, allocator)`.
- err: a Parse_Error from either input, `.Base_Not_Absolute`, or an allocator error.
*/
resolve_string :: proc(base, ref: string, allocator := context.allocator) -> (target: string, err: Error) {
	b := parse(base, allocator) or_return
	defer destroy(&b)
	r := parse(ref, allocator) or_return
	defer destroy(&r)
	t := resolve(b, r, allocator) or_return
	defer destroy(&t)
	return to_string(t, allocator)
}

/*
remove_dot_segments removes the "." and ".." segments of `path` as described
in RFC 3986 section 5.2.4. A ".." that would climb above the root is dropped.

Returns:
- out: the cleaned path, owned by the caller; free it with `delete(out, allocator)`.
- err: an allocator error.
*/
remove_dot_segments :: proc(path: string, allocator := context.allocator) -> (out: string, err: Error) {
	buf := make([dynamic]byte, 0, len(path), allocator) or_return
	remove_dots_into(&buf, path)
	return string(buf[:]), nil
}

/*
normalize returns the syntax-based and scheme-based normal form of `u`
described in RFC 3986 section 6.2, so that equivalent URIs compare equal as
strings. It:

- lowercases the scheme and the host,
- uppercases the hexadecimal digits of every percent-escape,
- decodes percent-escapes of unreserved characters, such as `%7E` to `~`,
- removes dot segments from the path of an absolute URI or an absolute path,
- turns an empty path into "/" when there is an authority, and
- drops a port that equals the default port of the scheme.

Returns:
- out: the normalized URI, owned by the caller; free it with destroy.
- err: an allocator error.
*/
normalize :: proc(u: URI, allocator := context.allocator) -> (out: URI, err: Error) {
	total := len(u.scheme) + len(u.user) + len(u.password) + len(u.host) + len(u.path) + len(u.raw_query) + len(u.fragment) + 1
	a := assembler_make(total, allocator) or_return
	scratch := make([dynamic]byte, 0, len(u.path), allocator) or_return
	defer delete(scratch)

	out = u
	assembler_begin(&a, .Scheme)
	for i in 0 ..< len(u.scheme) {
		append(&a.buf, to_lower(u.scheme[i]))
	}
	assembler_end(&a, .Scheme)
	assembler_normalize(&a, .User, u.user, false)
	assembler_normalize(&a, .Password, u.password, false)
	assembler_normalize(&a, .Host, u.host, true)

	assembler_begin(&a, .Path)
	normalize_escapes(&scratch, u.path, false)
	if u.scheme != "" || strings.has_prefix(u.path, "/") {
		remove_dots_into(&a.buf, string(scratch[:]))
	} else {
		append(&a.buf, string(scratch[:]))
	}
	if has_authority_part(u) && len(a.buf) == a.spans[.Path][0] {
		append(&a.buf, '/')
	}
	assembler_end(&a, .Path)

	assembler_normalize(&a, .Query, u.raw_query, false)
	assembler_normalize(&a, .Fragment, u.fragment, false)
	assembler_finish(&a, &out)

	if p, ok := u.port.?; ok {
		if d, known := default_port(u.scheme); known && d == p {
			out.port = nil
		}
	}
	return out, nil
}

@(private)
copy_authority :: proc(dst: ^URI, src: URI) {
	dst.user = src.user
	dst.password = src.password
	dst.host = src.host
	dst.port = src.port
	dst.host_kind = src.host_kind
	dst.has_authority = has_authority_part(src)
	dst.has_userinfo = src.has_userinfo
	dst.has_password = src.has_password
}

@(private)
copy_query :: proc(dst: ^URI, src: URI) {
	dst.raw_query = src.raw_query
	dst.has_query = src.has_query || src.raw_query != ""
}

// merge_paths implements RFC 3986 section 5.2.3.
@(private)
merge_paths :: proc(base: URI, ref_path: string, allocator := context.allocator) -> (merged: string, err: Error) {
	if has_authority_part(base) && base.path == "" {
		return strings.concatenate({"/", ref_path}, allocator)
	}
	dir := ""
	if slash := strings.last_index_byte(base.path, '/'); slash >= 0 {
		dir = base.path[:slash + 1]
	}
	return strings.concatenate({dir, ref_path}, allocator)
}

/*
remove_dots_into appends the result of RFC 3986 section 5.2.4 for `input` to
`out`. It never touches bytes that were in `out` before the call, and it never
grows `out` by more than `len(input)`.
*/
@(private)
remove_dots_into :: proc(out: ^[dynamic]byte, input: string) {
	start := len(out)
	pop_segment :: proc(out: ^[dynamic]byte, start: int) {
		i := len(out) - 1
		for i >= start && out[i] != '/' {
			i -= 1
		}
		resize(out, max(i, start))
	}

	in_ := input
	for in_ != "" {
		switch {
		case strings.has_prefix(in_, "../"):
			in_ = in_[3:]
		case strings.has_prefix(in_, "./"):
			in_ = in_[2:]
		case strings.has_prefix(in_, "/./"):
			in_ = in_[2:]
		case in_ == "/.":
			in_ = "/"
		case strings.has_prefix(in_, "/../"):
			in_ = in_[3:]
			pop_segment(out, start)
		case in_ == "/..":
			in_ = "/"
			pop_segment(out, start)
		case in_ == "." || in_ == "..":
			in_ = ""
		case:
			from := 1 if in_[0] == '/' else 0
			end := len(in_)
			if slash := strings.index_byte(in_[from:], '/'); slash >= 0 {
				end = from + slash
			}
			append(out, in_[:end])
			in_ = in_[end:]
		}
	}
}

@(private)
assembler_normalize :: proc(a: ^Assembler, c: Component, s: string, lower: bool) {
	assembler_begin(a, c)
	normalize_escapes(&a.buf, s, lower)
	assembler_end(a, c)
}

/*
normalize_escapes appends `s` to `out`, decoding escapes of unreserved
characters and uppercasing the hexadecimal digits of the others. With `lower`
set, it also lowercases every literal letter.
*/
@(private)
normalize_escapes :: proc(out: ^[dynamic]byte, s: string, lower: bool) {
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == '%' && i + 2 < len(s) && is_hex(s[i + 1]) && is_hex(s[i + 2]) {
			decoded := hex_value(s[i + 1]) << 4 | hex_value(s[i + 2])
			if is_unreserved(decoded) {
				append(out, to_lower(decoded) if lower else decoded)
			} else {
				append(out, '%', to_upper(s[i + 1]), to_upper(s[i + 2]))
			}
			i += 2
			continue
		}
		append(out, to_lower(c) if lower else c)
	}
}

@(private)
to_lower :: proc(c: byte) -> byte {
	return c + 32 if c >= 'A' && c <= 'Z' else c
}

@(private)
to_upper :: proc(c: byte) -> byte {
	return c - 32 if c >= 'a' && c <= 'z' else c
}
