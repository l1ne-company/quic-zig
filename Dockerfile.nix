# For CI only
# Build stage using Nix to get Zig
FROM nixos/nix:latest AS nix-builder

# Enable flakes
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Copy flake files
COPY flake.nix flake.lock /build/
WORKDIR /build

# Build Zig from flake and copy it
RUN nix build .#default && \
    mkdir -p /zig-dist && \
    cp -rL result/* /zig-dist/

# Copy source code and build
COPY build.zig build.zig.zon /build/
COPY src /build/src

RUN /zig-dist/zig build -Doptimize=ReleaseFast

# Final stage - use the network simulator endpoint base
FROM martenseemann/quic-network-simulator-endpoint:latest

# Copy built binaries
COPY --from=nix-builder /build/zig-out/bin/quic_server /usr/local/bin/
COPY --from=nix-builder /build/zig-out/bin/quic_client /usr/local/bin/
COPY --from=nix-builder /build/zig-out/bin/quic_endpoint /usr/local/bin/

ENTRYPOINT [ "/usr/local/bin/quic_endpoint" ]
