### Added

* `require "statifier/basichttp"` loads the HTTP transport, the seam a Basic HTTP processor makes its requests through; `require "statifier"` alone loads none of it and no HTTP library.
* A transport is any callable that takes a `Statifier::BasicHTTP::Request` (`http_method`, `url`, `headers`, `body`) and answers a `Statifier::BasicHTTP::Response` (`status`, `headers`, `body`), whatever its status, or raises `Statifier::BasicHTTP::TransportError` when no response came back; both values are frozen, and building one copies what it is given.
* `Statifier::BasicHTTP::NetHTTPTransport` is the default transport, on the standard library's Net::HTTP: one attempt per call, each step bounded by `timeout:` seconds (five when absent), and `connect:` for a host's own Net::HTTP connection.
