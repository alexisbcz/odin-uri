package uri

import "base:runtime"
import "core:strings"

/*
Query is an ordered list of decoded key and value pairs from an
`application/x-www-form-urlencoded` query string. Unlike a map, it keeps
repeated keys, empty keys and the original order.

Each element is `{key, value}`. The Query owns every key and value string and
allocates them with its own allocator. Create one with parse_query, or start
from a zero value and call query_add, which then uses `context.allocator`.
Free it with query_destroy. A value is safe to use from one thread at a time.
*/
Query :: [dynamic][2]string

/*
parse_query decodes a raw query string such as `a=1&b=x+y&a=2`. Pairs are
separated by "&"; the first "=" splits a key from its value. A pair without
"=" has an empty value. Empty pairs, such as the one between "&&", are
skipped, but a pair with an empty key, such as `=v`, is kept. Keys and values
are decoded with unescape_query_component, so "+" becomes a space. ";" has no
special meaning.

Inputs:
- raw: the query without its leading "?", for example the `raw_query` field of a URI.
- allocator: allocates the list and every key and value.

Returns:
- q: the pairs in input order, owned by the caller; free them with query_destroy.
- err: `.Invalid_Escape` for a malformed "%" escape, or an allocator error. On error nothing is allocated.
*/
parse_query :: proc(raw: string, allocator := context.allocator) -> (q: Query, err: Error) {
	q = make(Query, 0, strings.count(raw, "&") + 1, allocator) or_return
	rest := raw
	for rest != "" {
		pair := rest
		rest = ""
		if amp := strings.index_byte(pair, '&'); amp >= 0 {
			rest = pair[amp + 1:]
			pair = pair[:amp]
		}
		if pair == "" {
			continue
		}
		if pair_err := query_append_encoded(&q, pair, allocator); pair_err != nil {
			query_destroy(&q)
			return nil, pair_err
		}
	}
	return q, nil
}

// query_append_encoded decodes one `key=value` pair and appends it to `q`, freeing both halves on error.
@(private)
query_append_encoded :: proc(q: ^Query, pair: string, allocator: runtime.Allocator) -> Error {
	raw_key, raw_value := pair, ""
	if eq := strings.index_byte(pair, '='); eq >= 0 {
		raw_key, raw_value = pair[:eq], pair[eq + 1:]
	}
	key := unescape_query_component(raw_key, allocator) or_return
	value, value_err := unescape_query_component(raw_value, allocator)
	if value_err != nil {
		delete(key, allocator)
		return value_err
	}
	if _, append_err := append(q, [2]string{key, value}); append_err != nil {
		delete(key, allocator)
		delete(value, allocator)
		return append_err
	}
	return nil
}

// query_destroy frees every key and value of `q` and the list itself, then zeroes `q`.
query_destroy :: proc(q: ^Query) {
	for pair in q {
		delete(pair[0], q.allocator)
		delete(pair[1], q.allocator)
	}
	delete(q^)
	q^ = nil
}

/*
query_get returns the value of the first pair whose key equals `key`. The
returned string is owned by `q` and stays valid until `q` changes.
*/
query_get :: proc(q: Query, key: string) -> (value: string, ok: bool) {
	for pair in q {
		if pair[0] == key {
			return pair[1], true
		}
	}
	return "", false
}

/*
query_get_all returns the values of every pair whose key equals `key`, in
order.

Returns:
- values: a new slice owned by the caller; free it with `delete(values, allocator)`. The strings inside are owned by `q`.
- err: an allocator error.
*/
query_get_all :: proc(q: Query, key: string, allocator := context.allocator) -> (values: []string, err: Error) {
	n := 0
	for pair in q {
		if pair[0] == key {
			n += 1
		}
	}
	values = make([]string, n, allocator) or_return
	i := 0
	for pair in q {
		if pair[0] == key {
			values[i] = pair[1]
			i += 1
		}
	}
	return values, nil
}

// query_has reports whether any pair of `q` has the key `key`.
query_has :: proc(q: Query, key: string) -> bool {
	_, ok := query_get(q, key)
	return ok
}

/*
query_add appends the pair `{key, value}` to `q`, keeping any existing pairs
with the same key. It copies both strings with the allocator of `q`.

Returns:
- err: an allocator error; `q` is unchanged on error.
*/
query_add :: proc(q: ^Query, key, value: string) -> (err: Error) {
	allocator := query_allocator(q)
	k := strings.clone(key, allocator) or_return
	v, v_err := strings.clone(value, allocator)
	if v_err != nil {
		delete(k, allocator)
		return v_err
	}
	if _, append_err := append(q, [2]string{k, v}); append_err != nil {
		delete(k, allocator)
		delete(v, allocator)
		return append_err
	}
	return nil
}

/*
query_set makes `value` the only value of `key`. It replaces the value of the
first pair with that key, in place, and removes the later ones. When no pair
has the key, it appends one.

Returns:
- err: an allocator error; `q` is unchanged on error.
*/
query_set :: proc(q: ^Query, key, value: string) -> (err: Error) {
	first := -1
	for pair, i in q {
		if pair[0] == key {
			first = i
			break
		}
	}
	if first < 0 {
		return query_add(q, key, value)
	}
	v := strings.clone(value, q.allocator) or_return
	delete(q[first][1], q.allocator)
	q[first][1] = v
	for i := len(q) - 1; i > first; i -= 1 {
		if q[i][0] == key {
			delete(q[i][0], q.allocator)
			delete(q[i][1], q.allocator)
			ordered_remove(q, i)
		}
	}
	return nil
}

// query_del removes and frees every pair of `q` whose key equals `key`, keeping the order of the rest.
query_del :: proc(q: ^Query, key: string) {
	kept := 0
	for i in 0 ..< len(q) {
		pair := q[i]
		if pair[0] == key {
			delete(pair[0], q.allocator)
			delete(pair[1], q.allocator)
			continue
		}
		q[kept] = pair
		kept += 1
	}
	resize(q, kept)
}

/*
query_encode writes `q` as an `application/x-www-form-urlencoded` string in
the order of its pairs, for example `a=1&b=x+y`. Keys and values are escaped
with escape_query_component. Every pair gets an "=", even when its value is
empty. Unlike Go's `Values.Encode`, query_encode doesn't sort the keys.

Returns:
- encoded: the query without a leading "?", owned by the caller; free it with `delete(encoded, allocator)`.
- err: an allocator error.
*/
query_encode :: proc(q: Query, allocator := context.allocator) -> (encoded: string, err: Error) {
	estimate := 0
	for pair in q {
		estimate += len(pair[0]) + len(pair[1]) + 2
	}
	b := strings.builder_make_len_cap(0, estimate, allocator) or_return
	for pair, i in q {
		if i > 0 {
			strings.write_byte(&b, '&')
		}
		escape_into(&b, pair[0], .Query_Component)
		strings.write_byte(&b, '=')
		escape_into(&b, pair[1], .Query_Component)
	}
	return strings.to_string(b), nil
}

// query_allocator returns the allocator of `q`, adopting `context.allocator` for a zero Query.
@(private)
query_allocator :: proc(q: ^Query) -> runtime.Allocator {
	raw := (^runtime.Raw_Dynamic_Array)(q)
	if raw.allocator.procedure == nil {
		raw.allocator = context.allocator
	}
	return raw.allocator
}
