# KING VPN Rust native core

This dependency-free crate generates bounded IPv4/IPv6 IP, CIDR and inclusive
range batches. It does not open sockets, probe endpoints, create VPN tunnels,
or alter routing policy.

Dart treats the library as optional and falls back to the existing BigInt
implementation whenever loading or response validation fails.

Host checks:
    cargo clippy --manifest-path native/king_native_core/Cargo.toml --all-targets --locked -- -D warnings
    cargo test --manifest-path native/king_native_core/Cargo.toml --locked

Android arm64 builds are performed by the main workflow with Android NDK and
cargo-ndk. No compiled native binary is committed.
