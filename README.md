# uri

[![CI](https://github.com/alexisbcz/odin-uri/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-uri/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Parse, build, resolve and normalize URIs in Odin, following [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986), with an ordered query type that keeps repeated keys.

`core:net` has `split_url`, but it returns the query as an unordered `map[string]string`, so `?tag=a&tag=b` loses a value. It also doesn't parse user information, ports or IPv6 hosts, and it can't resolve a relative link against a base. This package fills those gaps.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-uri libs/uri
```

```odin
import "libs/uri"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-uri ~/odin-shared/uri
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:uri"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:uri"

main :: proc() {
	base, err := uri.parse("https://alice@example.com:8443/docs/guide/intro.html?tag=a&tag=b")
	if err != nil {
		fmt.eprintln("parse failed:", err)
		return
	}
	defer uri.destroy(&base)
	fmt.println(base.host, base.port.? or_else 0, base.path)

	q, qerr := uri.parse_query(base.raw_query)
	if qerr != nil {
		fmt.eprintln("bad query:", qerr)
		return
	}
	defer uri.query_destroy(&q)
	tags, _ := uri.query_get_all(q, "tag")
	defer delete(tags)
	fmt.println(tags)

	link, _ := uri.resolve_string("https://example.com/docs/guide/intro.html", "../api/./v2?page=2")
	defer delete(link)
	fmt.println(link)
}
```

This prints `example.com 8443 /docs/guide/intro.html`, then `["a", "b"]`, then `https://example.com/docs/api/v2?page=2`.

## What a URI holds

`parse` fills a `URI` struct. Every string field holds the component exactly as it appeared in the input, still percent-encoded:

| Field | Value for `https://bob:pw@[::1]:8080/a%20b?x=1#top` |
| --- | --- |
| `scheme` | `https` |
| `user`, `password` | `bob`, `pw` |
| `host` | `::1`, without the brackets |
| `host_kind` | `.IPv6`; the others are `.Reg_Name`, `.IPv4` and `.IP_Future` |
| `port` | `8080`, a `Maybe(u16)` that's `nil` when absent |
| `path` | `/a%20b` |
| `raw_query` | `x=1` |
| `fragment` | `top` |

The flags `has_authority`, `has_userinfo`, `has_password`, `has_query` and `has_fragment` tell an absent component apart from an empty one, so `http://h/?` and `http://h/` print back unchanged. Call `unescape` to decode a component.

The parser is strict. A space, a raw non-ASCII byte or a character such as `[` outside an IPv6 host is an error, and so is a `%` that isn't followed by two hexadecimal digits. Escape such text with `escape_path` or `escape_query_component` first.

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `parse(s, allocator)` | Parse a URI or relative reference | Yes | `destroy` |
| `to_string(u, allocator)` | Print a URI in RFC 3986 syntax | Yes | `delete` |
| `resolve(base, ref, allocator)` | Resolve a reference, RFC 3986 section 5.2 | Yes | `destroy` |
| `resolve_string(base, ref, allocator)` | Parse, resolve and print in one call | Yes | `delete` |
| `normalize(u, allocator)` | Normal form from RFC 3986 section 6.2 | Yes | `destroy` |
| `remove_dot_segments(path, allocator)` | Remove `.` and `..` segments | Yes | `delete` |
| `clone(u, allocator)` | Deep copy, for example of a hand-built URI | Yes | `destroy` |
| `is_absolute(u)` | Report whether `u` has a scheme | No | Not needed |
| `default_port(scheme)`, `port_or_default(u)` | Well-known ports of `http`, `https`, `ws`, `wss` and `ftp` | No | Not needed |
| `escape_path(s, allocator)` | Escape one path segment, like Go's `url.PathEscape` | Yes | `delete` |
| `escape_query_component(s, allocator)` | Escape a query key or value, like `url.QueryEscape` | Yes | `delete` |
| `unescape(s, allocator)` | Decode `%XX`, like `url.PathUnescape` | Yes | `delete` |
| `unescape_query_component(s, allocator)` | Decode `%XX` and `+`, like `url.QueryUnescape` | Yes | `delete` |
| `Query` | Ordered `[dynamic][2]string` of decoded pairs | Yes | `query_destroy` |
| `parse_query(raw, allocator)` | Decode `a=1&b=2` | Yes | `query_destroy` |
| `query_get(q, key)`, `query_has(q, key)` | First value of a key | No | Not needed |
| `query_get_all(q, key, allocator)` | Every value of a key, in order | The slice | `delete` |
| `query_add(&q, key, value)` | Append a pair | Yes | `query_destroy` |
| `query_set(&q, key, value)` | Make `value` the only value of `key` | Yes | `query_destroy` |
| `query_del(&q, key)` | Remove every pair with `key` | No | Not needed |
| `query_encode(q, allocator)` | Encode in order, with `+` for space | Yes | `delete` |
| `Error` | Union of `Parse_Error`, `Resolve_Error` and `runtime.Allocator_Error` | No | Not needed |

## Building a URI

Fill the struct with already-escaped components and print it. A hand-built `URI` owns nothing, so it needs no `destroy`:

```odin
segment, _ := uri.escape_path("reports/2026 Q3.pdf")
defer delete(segment)
u := uri.URI {
	scheme = "https",
	host   = "files.example.com",
	path   = segment,
}
s, _ := uri.to_string(u)
defer delete(s)
// s == "https://files.example.com/reports%2F2026%20Q3.pdf"
```

`to_string` adds a `/` between the host and a relative path, and puts brackets around a host that contains a colon.

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Every allocating procedure takes `allocator := context.allocator` and says who owns the result. A parsed `URI` keeps all its strings in one buffer, so `destroy` is a single free.
- Fallible procedures return `(T, Error)`. The library never panics on bad input, and fuzz tests check that on random bytes.
- `resolve` uses the strict algorithm, so `http:g` against an `http` base stays `http:g`, as RFC 3986 section 5.4.2 recommends.
- `query_encode` keeps insertion order. Go's `Values.Encode` sorts keys instead.
- The package keeps no global mutable state, so it's safe to use from several threads as long as each value stays on one thread.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

The tests include the complete reference resolution tables of RFC 3986 section 5.4, a round trip of 49 URIs, and leak checks through a tracking allocator on every test.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
