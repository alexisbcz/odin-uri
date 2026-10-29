package uri_tests

import uri ".."
import "base:runtime"
import "core:math/rand"
import "core:testing"

FUZZ_ITERATIONS :: 20_000

// URI_ALPHABET biases random input toward the delimiters and escapes of the grammar.
URI_ALPHABET :: "abcxyzABCF019:/?#[]@!$&'()*+,;=%-._~ v"

@(private = "file")
random_input :: proc(buf: []byte, uri_like: bool, gen: runtime.Random_Generator) -> string {
	n := rand.int_max(len(buf) + 1, gen)
	alphabet := URI_ALPHABET
	for i in 0 ..< n {
		if uri_like {
			buf[i] = alphabet[rand.int_max(len(alphabet), gen)]
		} else {
			buf[i] = byte(rand.int_max(256, gen))
		}
	}
	return string(buf[:n])
}

/*
check_one parses `input`. When parsing succeeds, the printed form must parse
again to the same text, normalize must succeed and reach a fixed point, and
resolving the input against a base must succeed.
*/
@(private = "file")
check_one :: proc(t: ^testing.T, input: string, alloc: runtime.Allocator) -> (parsed: bool) {
	u, err := uri.parse(input, alloc)
	defer uri.destroy(&u)
	if err != nil {
		_, is_parse := err.(uri.Parse_Error)
		testing.expectf(t, is_parse, "parse(%q) returned a non-parse error %v", input, err)
		return false
	}

	s, _ := uri.to_string(u, alloc)
	defer delete(s, alloc)
	again, again_err := uri.parse(s, alloc)
	defer uri.destroy(&again)
	testing.expectf(t, again_err == nil, "reparse of %q (from %q) failed: %v", s, input, again_err)
	s2, _ := uri.to_string(again, alloc)
	defer delete(s2, alloc)
	testing.expectf(t, s == s2, "to_string not stable for %q: %q then %q", input, s, s2)

	n, nerr := uri.normalize(u, alloc)
	defer uri.destroy(&n)
	testing.expect_value(t, nerr, nil)
	ns, _ := uri.to_string(n, alloc)
	defer delete(ns, alloc)
	nback, nback_err := uri.parse(ns, alloc)
	defer uri.destroy(&nback)
	testing.expectf(t, nback_err == nil, "normalized %q (from %q) does not parse: %v", ns, input, nback_err)

	base, _ := uri.parse("http://a/b/c/d;p?q", alloc)
	defer uri.destroy(&base)
	r, rerr := uri.resolve(base, u, alloc)
	defer uri.destroy(&r)
	testing.expectf(t, rerr == nil, "resolve(%q) failed: %v", input, rerr)
	rs, _ := uri.to_string(r, alloc)
	defer delete(rs, alloc)
	rback, rback_err := uri.parse(rs, alloc)
	defer uri.destroy(&rback)
	testing.expectf(t, rback_err == nil, "resolved %q (from %q) does not parse: %v", rs, input, rback_err)
	return true
}

@(test)
test_fuzz_parse_random_bytes_never_panics :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	state: rand.PCG_Random_State
	gen := rand.pcg_random_generator(&state)
	rand.reset(u64(0x0D1_7E57), gen)
	buf: [48]byte
	for _ in 0 ..< FUZZ_ITERATIONS {
		check_one(t, random_input(buf[:], false, gen), alloc)
	}
}

@(test)
test_fuzz_parse_uri_like_input :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	state: rand.PCG_Random_State
	gen := rand.pcg_random_generator(&state)
	rand.reset(u64(0xC0FFEE), gen)
	buf: [40]byte
	accepted := 0
	for _ in 0 ..< FUZZ_ITERATIONS {
		if check_one(t, random_input(buf[:], true, gen), alloc) {
			accepted += 1
		}
	}
	// The biased alphabet must reach the success paths often enough to matter.
	testing.expectf(t, accepted > FUZZ_ITERATIONS / 50, "only %d of %d inputs parsed", accepted, FUZZ_ITERATIONS)
}

@(test)
test_fuzz_query_and_unescape_never_panic :: proc(t: ^testing.T) {
	lc: Leak_Check
	alloc := tracked(t, &lc)
	state: rand.PCG_Random_State
	gen := rand.pcg_random_generator(&state)
	rand.reset(u64(42), gen)
	buf: [40]byte
	for i in 0 ..< FUZZ_ITERATIONS {
		input := random_input(buf[:], i % 2 == 0, gen)
		q, qerr := uri.parse_query(input, alloc)
		if qerr == nil {
			encoded, _ := uri.query_encode(q, alloc)
			back, berr := uri.parse_query(encoded, alloc)
			testing.expectf(t, berr == nil && len(back) == len(q), "query_encode of %q does not parse back", input)
			uri.query_destroy(&back)
			delete(encoded, alloc)
		} else {
			testing.expect_value(t, qerr, uri.Error(uri.Parse_Error.Invalid_Escape))
		}
		uri.query_destroy(&q)

		decoded, _ := uri.unescape(input, alloc)
		delete(decoded, alloc)
		escaped, _ := uri.escape_path(input, alloc)
		round, rerr := uri.unescape(escaped, alloc)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, round == input)
		delete(round, alloc)
		delete(escaped, alloc)
	}
}
