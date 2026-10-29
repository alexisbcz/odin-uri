// Example basic parses, resolves, normalizes and edits URIs. Run it with `odin run examples/basic`.
package main

import uri "../.."
import "core:fmt"
import "core:os"

main :: proc() {
	base, err := uri.parse("https://alice@Example.COM:443/docs/guide/intro.html?lang=en&lang=fr#top")
	if err != nil {
		fmt.eprintln("parse failed:", err)
		os.exit(1)
	}
	defer uri.destroy(&base)
	fmt.println("scheme:", base.scheme)
	fmt.println("user:  ", base.user)
	fmt.println("host:  ", base.host)
	fmt.println("port:  ", base.port.? or_else 0)
	fmt.println("path:  ", base.path)

	// Repeated keys keep their order.
	q, qerr := uri.parse_query(base.raw_query)
	if qerr != nil {
		fmt.eprintln("bad query:", qerr)
		os.exit(1)
	}
	defer uri.query_destroy(&q)
	langs, _ := uri.query_get_all(q, "lang")
	defer delete(langs)
	fmt.println("langs: ", langs)

	// Resolve a relative link the way a browser would.
	link, _ := uri.parse("../api/./v2?page=2")
	defer uri.destroy(&link)
	target, rerr := uri.resolve(base, link)
	if rerr != nil {
		fmt.eprintln("resolve failed:", rerr)
		os.exit(1)
	}
	defer uri.destroy(&target)
	resolved, _ := uri.to_string(target)
	defer delete(resolved)
	fmt.println("resolved:  ", resolved)

	// Normalize to compare equivalent URIs as plain strings.
	normal, _ := uri.normalize(target)
	defer uri.destroy(&normal)
	normalized, _ := uri.to_string(normal)
	defer delete(normalized)
	fmt.println("normalized:", normalized)

	// Build a query in order and escape it for the wire.
	out: uri.Query
	defer uri.query_destroy(&out)
	uri.query_add(&out, "q", "odin lang")
	uri.query_add(&out, "tag", "a&b")
	uri.query_add(&out, "tag", "c")
	uri.query_set(&out, "q", "odin + uri")
	encoded, _ := uri.query_encode(out)
	defer delete(encoded)
	fmt.println("query:     ", encoded)
}
