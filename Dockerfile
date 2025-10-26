# Dockerfile for QUIC Interop Runner
# Simple approach: just copy pre-built binaries from host

FROM martenseemann/quic-network-simulator-endpoint:latest

# Copy pre-built binaries (build them first with: zig build -Doptimize=ReleaseFast)
COPY zig-out/bin/quic_server /usr/local/bin/
COPY zig-out/bin/quic_client /usr/local/bin/
COPY zig-out/bin/quic_endpoint /usr/local/bin/

ENTRYPOINT [ "/usr/local/bin/quic_endpoint" ]
