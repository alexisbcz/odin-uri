package uri

import "core:strings"

/*
split breaks `s` into borrowed components following the regular expression of
RFC 3986 appendix B, then validates each one against the section 3 grammar.
*/
@(private)
split :: proc(s: string) -> (u: URI, err: Parse_Error) {
	rest := s
	scan: for i in 0 ..< len(s) {
		switch s[i] {
		case ':':
			if !valid_scheme(s[:i]) {
				return {}, .Invalid_Scheme
			}
			u.scheme = s[:i]
			rest = s[i + 1:]
			break scan
		case '/', '?', '#':
			break scan
		}
	}

	if hash := strings.index_byte(rest, '#'); hash >= 0 {
		u.fragment = rest[hash + 1:]
		u.has_fragment = true
		rest = rest[:hash]
		validate(u.fragment, is_query_char, .Invalid_Fragment) or_return
	}
	if question := strings.index_byte(rest, '?'); question >= 0 {
		u.raw_query = rest[question + 1:]
		u.has_query = true
		rest = rest[:question]
		validate(u.raw_query, is_query_char, .Invalid_Query) or_return
	}
	if strings.has_prefix(rest, "//") {
		u.has_authority = true
		rest = rest[2:]
		end := strings.index_byte(rest, '/')
		if end < 0 {
			end = len(rest)
		}
		split_authority(&u, rest[:end]) or_return
		rest = rest[end:]
	}
	validate(rest, is_path_char, .Invalid_Path) or_return
	u.path = rest
	return u, .None
}

@(private)
split_authority :: proc(u: ^URI, authority: string) -> Parse_Error {
	hostport := authority
	if at := strings.last_index_byte(authority, '@'); at >= 0 {
		info := authority[:at]
		hostport = authority[at + 1:]
		validate(info, is_userinfo_char, .Invalid_Userinfo) or_return
		u.has_userinfo = true
		u.user = info
		if colon := strings.index_byte(info, ':'); colon >= 0 {
			u.user = info[:colon]
			u.password = info[colon + 1:]
			u.has_password = true
		}
	}

	port_text := ""
	if strings.has_prefix(hostport, "[") {
		close := strings.index_byte(hostport, ']')
		if close < 0 {
			return .Invalid_IP_Literal
		}
		u.host = hostport[1:close]
		u.host_kind = ip_literal_kind(u.host) or_return
		after := hostport[close + 1:]
		if after != "" {
			if after[0] != ':' {
				return .Invalid_Host
			}
			port_text = after[1:]
		}
	} else {
		u.host = hostport
		if colon := strings.last_index_byte(hostport, ':'); colon >= 0 {
			u.host = hostport[:colon]
			port_text = hostport[colon + 1:]
		}
		validate(u.host, is_reg_name_char, .Invalid_Host) or_return
		if is_ipv4(u.host) {
			u.host_kind = .IPv4
		}
	}

	// RFC 3986 allows an empty port; it means the same as no port.
	if port_text == "" {
		return .None
	}
	for i in 0 ..< len(port_text) {
		if !is_digit(port_text[i]) {
			return .Invalid_Port
		}
	}
	value := 0
	for i in 0 ..< len(port_text) {
		value = value * 10 + int(port_text[i] - '0')
		if value > 65535 {
			return .Port_Out_Of_Range
		}
	}
	u.port = u16(value)
	return .None
}

// validate checks that every byte of `s` is allowed or part of a valid percent-escape.
@(private)
validate :: proc(s: string, allowed: proc(c: byte) -> bool, fail: Parse_Error) -> Parse_Error {
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == '%' {
			if i + 2 >= len(s) || !is_hex(s[i + 1]) || !is_hex(s[i + 2]) {
				return .Invalid_Escape
			}
			i += 2
			continue
		}
		if !allowed(c) {
			return fail
		}
	}
	return .None
}

// valid_scheme matches `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`.
@(private)
valid_scheme :: proc(s: string) -> bool {
	if s == "" || !is_alpha(s[0]) {
		return false
	}
	for i in 1 ..< len(s) {
		c := s[i]
		if !is_alpha(c) && !is_digit(c) && c != '+' && c != '-' && c != '.' {
			return false
		}
	}
	return true
}

// ip_literal_kind validates the text between "[" and "]" (RFC 3986 section 3.2.2, RFC 6874).
@(private)
ip_literal_kind :: proc(s: string) -> (kind: Host_Kind, err: Parse_Error) {
	if s != "" && (s[0] == 'v' || s[0] == 'V') {
		if !valid_ip_future(s) {
			return .Reg_Name, .Invalid_IP_Literal
		}
		return .IP_Future, .None
	}
	address := s
	if zone_at := strings.index(s, "%25"); zone_at >= 0 {
		zone := s[zone_at + 3:]
		if zone == "" {
			return .Reg_Name, .Invalid_IP_Literal
		}
		validate(zone, is_unreserved, .Invalid_IP_Literal) or_return
		address = s[:zone_at]
	}
	if !valid_ipv6(address) {
		return .Reg_Name, .Invalid_IP_Literal
	}
	return .IPv6, .None
}

// valid_ip_future matches `"v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )`.
@(private)
valid_ip_future :: proc(s: string) -> bool {
	i := 1
	for i < len(s) && is_hex(s[i]) {
		i += 1
	}
	if i == 1 || i >= len(s) || s[i] != '.' {
		return false
	}
	i += 1
	if i >= len(s) {
		return false
	}
	for ; i < len(s); i += 1 {
		c := s[i]
		if !is_unreserved(c) && !is_sub_delim(c) && c != ':' {
			return false
		}
	}
	return true
}

// valid_ipv6 matches the IPv6address rule of RFC 3986 section 3.2.2.
@(private)
valid_ipv6 :: proc(s: string) -> bool {
	gap := strings.index(s, "::")
	if gap < 0 {
		n, ok := count_ipv6_groups(s, true)
		return ok && n == 8
	}
	if strings.index(s[gap + 1:], "::") >= 0 {
		return false
	}
	left, left_ok := count_ipv6_groups(s[:gap], false)
	right, right_ok := count_ipv6_groups(s[gap + 2:], true)
	return left_ok && right_ok && left + right <= 7
}

/*
count_ipv6_groups counts the 16-bit groups in a colon-separated run of h16
pieces. When `allow_ipv4` is set, the last piece may be an IPv4 address, which
counts as two groups.
*/
@(private)
count_ipv6_groups :: proc(s: string, allow_ipv4: bool) -> (n: int, ok: bool) {
	if s == "" {
		return 0, true
	}
	rest := s
	for {
		colon := strings.index_byte(rest, ':')
		piece := rest if colon < 0 else rest[:colon]
		if colon < 0 && allow_ipv4 && strings.index_byte(piece, '.') >= 0 {
			if !is_ipv4(piece) {
				return 0, false
			}
			return n + 2, true
		}
		if piece == "" || len(piece) > 4 {
			return 0, false
		}
		for i in 0 ..< len(piece) {
			if !is_hex(piece[i]) {
				return 0, false
			}
		}
		n += 1
		if colon < 0 {
			return n, true
		}
		rest = rest[colon + 1:]
	}
}

// is_ipv4 matches `dec-octet "." dec-octet "." dec-octet "." dec-octet`.
@(private)
is_ipv4 :: proc(s: string) -> bool {
	rest := s
	for octet in 0 ..< 4 {
		end := 0
		for end < len(rest) && end < 4 && is_digit(rest[end]) {
			end += 1
		}
		if end == 0 || end > 3 || (end > 1 && rest[0] == '0') {
			return false
		}
		value := 0
		for i in 0 ..< end {
			value = value * 10 + int(rest[i] - '0')
		}
		if value > 255 {
			return false
		}
		rest = rest[end:]
		if octet < 3 {
			if rest == "" || rest[0] != '.' {
				return false
			}
			rest = rest[1:]
		}
	}
	return rest == ""
}

@(private)
is_alpha :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

@(private)
is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
is_hex :: proc(c: byte) -> bool {
	return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

@(private)
hex_value :: proc(c: byte) -> byte {
	switch c {
	case '0' ..= '9':
		return c - '0'
	case 'a' ..= 'f':
		return c - 'a' + 10
	case 'A' ..= 'F':
		return c - 'A' + 10
	}
	return 0
}

// is_unreserved matches `ALPHA / DIGIT / "-" / "." / "_" / "~"`.
@(private)
is_unreserved :: proc(c: byte) -> bool {
	return is_alpha(c) || is_digit(c) || c == '-' || c == '.' || c == '_' || c == '~'
}

// is_sub_delim matches `"!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="`.
@(private)
is_sub_delim :: proc(c: byte) -> bool {
	switch c {
	case '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=':
		return true
	}
	return false
}

@(private)
is_reg_name_char :: proc(c: byte) -> bool {
	return is_unreserved(c) || is_sub_delim(c)
}

@(private)
is_userinfo_char :: proc(c: byte) -> bool {
	return is_unreserved(c) || is_sub_delim(c) || c == ':'
}

@(private)
is_path_char :: proc(c: byte) -> bool {
	return is_unreserved(c) || is_sub_delim(c) || c == ':' || c == '@' || c == '/'
}

@(private)
is_query_char :: proc(c: byte) -> bool {
	return is_path_char(c) || c == '?'
}
