package uri

import "core:strings"

@(private)
Encoding :: enum u8 {
	Path_Segment,
	Query_Component,
}

@(private)
UPPER_HEX :: "0123456789ABCDEF"

/*
escape_path percent-encodes `s` so that it can be placed in a single path
segment. It matches Go's `url.PathEscape`: unreserved characters and
`$ & + : = @` stay as they are, and everything else, including "/", ";", ","
and "?", becomes `%XX` with uppercase hexadecimal digits.

Returns:
- escaped: a new string owned by the caller; free it with `delete(escaped, allocator)`.
- err: an allocator error.
*/
escape_path :: proc(s: string, allocator := context.allocator) -> (escaped: string, err: Error) {
	return escape(s, .Path_Segment, allocator)
}

/*
escape_query_component percent-encodes `s` so that it can be placed in a query
as a key or a value. It matches Go's `url.QueryEscape`: unreserved characters
stay as they are, a space becomes "+", and everything else becomes `%XX`.

Returns:
- escaped: a new string owned by the caller; free it with `delete(escaped, allocator)`.
- err: an allocator error.
*/
escape_query_component :: proc(s: string, allocator := context.allocator) -> (escaped: string, err: Error) {
	return escape(s, .Query_Component, allocator)
}

/*
unescape decodes every `%XX` escape in `s`. It matches Go's `url.PathUnescape`,
so "+" stays a plus sign. Use it for paths, user names, passwords and
fragments.

Returns:
- decoded: a new string owned by the caller, even when `s` has no escapes; free it with `delete(decoded, allocator)`.
- err: `.Invalid_Escape` when a "%" is not followed by two hexadecimal digits, or an allocator error.
*/
unescape :: proc(s: string, allocator := context.allocator) -> (decoded: string, err: Error) {
	return unescape_mode(s, .Path_Segment, allocator)
}

/*
unescape_query_component decodes a query key or value. It matches Go's
`url.QueryUnescape`: it decodes every `%XX` escape and turns "+" into a space.

Returns:
- decoded: a new string owned by the caller; free it with `delete(decoded, allocator)`.
- err: `.Invalid_Escape` when a "%" is not followed by two hexadecimal digits, or an allocator error.
*/
unescape_query_component :: proc(s: string, allocator := context.allocator) -> (decoded: string, err: Error) {
	return unescape_mode(s, .Query_Component, allocator)
}

// should_escape follows the shouldEscape function of Go's net/url package.
@(private)
should_escape :: proc(c: byte, mode: Encoding) -> bool {
	if is_alpha(c) || is_digit(c) {
		return false
	}
	switch c {
	case '-', '_', '.', '~':
		return false
	case '$', '&', '+', ',', '/', ':', ';', '=', '?', '@':
		switch mode {
		case .Path_Segment:
			return c == '/' || c == ';' || c == ',' || c == '?'
		case .Query_Component:
			return true
		}
	}
	return true
}

@(private)
escape :: proc(s: string, mode: Encoding, allocator := context.allocator) -> (escaped: string, err: Error) {
	extra := 0
	for i in 0 ..< len(s) {
		if should_escape(s[i], mode) && !(s[i] == ' ' && mode == .Query_Component) {
			extra += 2
		}
	}
	b := strings.builder_make_len_cap(0, len(s) + extra, allocator) or_return
	escape_into(&b, s, mode)
	return strings.to_string(b), nil
}

@(private)
escape_into :: proc(b: ^strings.Builder, s: string, mode: Encoding) {
	for i in 0 ..< len(s) {
		c := s[i]
		switch {
		case c == ' ' && mode == .Query_Component:
			strings.write_byte(b, '+')
		case should_escape(c, mode):
			hex := UPPER_HEX
			strings.write_byte(b, '%')
			strings.write_byte(b, hex[c >> 4])
			strings.write_byte(b, hex[c & 15])
		case:
			strings.write_byte(b, c)
		}
	}
}

@(private)
unescape_mode :: proc(s: string, mode: Encoding, allocator := context.allocator) -> (decoded: string, err: Error) {
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' {
			if i + 2 >= len(s) || !is_hex(s[i + 1]) || !is_hex(s[i + 2]) {
				return "", Parse_Error.Invalid_Escape
			}
			i += 2
		}
	}
	buf := make([dynamic]byte, 0, len(s), allocator) or_return
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		switch {
		case c == '%':
			append(&buf, hex_value(s[i + 1]) << 4 | hex_value(s[i + 2]))
			i += 2
		case c == '+' && mode == .Query_Component:
			append(&buf, ' ')
		case:
			append(&buf, c)
		}
	}
	return string(buf[:]), nil
}
