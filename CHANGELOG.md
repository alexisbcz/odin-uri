# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-10-29

### Fixed

- `query_del` and `query_set` no longer read freed memory when the key is a string stored in the same `Query`, such as `q[0][0]`. Before, they left some matching pairs in place.
- `normalize` no longer leaks its result buffer when an allocation fails.

## [0.1.0] - 2026-10-29

### Added

- `parse` and `to_string` for RFC 3986 URI references, with user information, passwords, IPv4, IPv6 with zones, IPvFuture hosts and `Maybe(u16)` ports.
- Typed errors: `Parse_Error`, `Resolve_Error` and the `Error` union.
- `resolve` and `resolve_string`, the strict reference resolution of RFC 3986 section 5.2, and `remove_dot_segments`.
- `normalize`, the normal form of RFC 3986 section 6.2.
- `clone`, `destroy`, `is_absolute`, `default_port` and `port_or_default`.
- `escape_path`, `escape_query_component`, `unescape` and `unescape_query_component` with Go `net/url` semantics.
- The ordered `Query` type with `parse_query`, `query_get`, `query_get_all`, `query_has`, `query_add`, `query_set`, `query_del`, `query_encode` and `query_destroy`.

[Unreleased]: https://github.com/alexisbcz/odin-uri/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/alexisbcz/odin-uri/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/alexisbcz/odin-uri/releases/tag/v0.1.0
