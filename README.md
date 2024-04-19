
# You are STUNning
A super simple multithreaded STUN server in [Zig](https://ziglang.org/).

Always responds to a Binding Request with a Binding Success Response with an XOR-MAPPED-ADDRESS, which is sufficient for hole-punching in WebRTC, for example. Does not check for magic cookie to differentiate old ([RFC 3489](https://datatracker.ietf.org/doc/html/rfc3489)) clients.

Listens by default on UDP `::` in dual-stack mode (IPv4 & IPv6) on default STUN port `3478` on all CPU cores.

STUN RFCs:
1. [RFC 3489](https://datatracker.ietf.org/doc/html/rfc3489): First RFC, no XOR-MAPPED-ADDRESS. Only MAPPED-ADDRESS where some NATs rewrite unknown payloads.
2. [RFC 5389](https://datatracker.ietf.org/doc/html/rfc5389): Defines XOR-MAPPED-ADDRESS.
3. [RFC 8489](https://datatracker.ietf.org/doc/html/rfc8489): Current, adds more protocols and stuff.

## Run
### Linux
- Build: `zig build-exe -fstrip -O ReleaseFast stun.zig`
- Run: `./stun`
- `./stun <host> <port> <threads>`
## Development
- Linux: `zig run stun.zig`
- Windows: `zig run --library C .\stun.zig`
	- Multithreading does not work on Windows.

## Zig Version
Tested with `0.12.0-dev.3667+77abd3a96`.
