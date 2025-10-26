{
  description = "quic-zig";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      zigFromTarball = pkgs.stdenv.mkDerivation {
        pname = "zig";
        version = "0.15.1";

        src = pkgs.fetchurl {
          url = "https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz";
          sha256 = "sha256-xhxdpu3uoUylHs1eRSDG9Bie9SUDg9sz0BhIKTv6/gU=";
        };

        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;

        installPhase = ''
	 mkdir -p $out
	 cp -r ./* $out/
	 mkdir -p $out/bin
	 ln -s $out/zig $out/bin/zig
        '';
      };
    in {
      packages.${system}.default = zigFromTarball;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          zigFromTarball
          pkgs.docker
          pkgs.docker-compose
          pkgs.openssl
          pkgs.python3
          pkgs.uv
          pkgs.git
          pkgs.jq
          (pkgs.writeScriptBin "setup" ''
            #!/usr/bin/env bash
            set -e

            echo "=========================================="
            echo "  QUIC-Zig One-Time Setup"
            echo "=========================================="
            echo ""

            # 1. Create test data directories
            echo "1. Creating test directories..."
            mkdir -p test-data/{www,downloads,certs,logs}
            echo "   ✓ Created test-data directories"

            # 2. Generate certificates if needed
            if [ ! -f test-data/certs/cert.pem ]; then
              echo ""
              echo "2. Generating test certificates..."
              ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
                -keyout test-data/certs/priv.key \
                -out test-data/certs/cert.pem \
                -days 365 \
                -subj "/CN=server/O=QuicZig/C=US" \
                -addext "subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1" 2>/dev/null
              chmod 600 test-data/certs/priv.key
              chmod 644 test-data/certs/cert.pem
              echo "   ✓ Generated test certificates"
            else
              echo ""
              echo "2. Test certificates already exist"
            fi

            # 3. Create test files
            echo ""
            echo "3. Creating test files..."
            echo "Hello from QUIC server!" > test-data/www/index.html
            echo "This is a test file for QUIC transfer." > test-data/www/test.txt
            dd if=/dev/urandom of=test-data/www/large.bin bs=1M count=1 2>/dev/null
            echo "   ✓ Created test files"

            # 4. Initialize quic-interop-runner submodule
            echo ""
            echo "4. Setting up quic-interop-runner submodule..."
            git submodule update --init --recursive
            echo "   ✓ Initialized quic-interop-runner submodule"

            # 5. Setup Python environment with uv
            echo ""
            echo "5. Setting up Python environment with uv..."
            cd quic-interop-runner

            # Use uv to sync dependencies
            ${pkgs.uv}/bin/uv venv
            ${pkgs.uv}/bin/uv pip install -r requirements.txt
            echo "   ✓ Installed Python dependencies with uv"

            # 6. Add implementation to implementations.json
            echo ""
            echo "6. Configuring quic-zig implementation..."
            if ! grep -q '"quic-zig"' implementations.json; then
              cp implementations.json implementations.json.bak
              ${pkgs.jq}/bin/jq '. + {"quic-zig": {"image": "l1ne/quic-zig:latest", "url": "https://github.com/l1ne-company/quic-zig", "role": "both"}}' implementations.json > implementations.json.tmp
              mv implementations.json.tmp implementations.json
              echo "   ✓ Added quic-zig to implementations.json"
            else
              echo "   ✓ quic-zig already in implementations.json"
            fi

            cd ..

            # 7. Create setup marker
            touch .setup-complete

            echo ""
            echo "=========================================="
            echo "  Setup Complete!"
            echo "=========================================="
            echo ""
            echo "Next steps:"
            echo "  1. Build:     zig build"
            echo "  2. Test:      test-interop"
            echo ""
            echo "For Docker Hub:"
            echo "  docker-login    - Login to Docker Hub"
            echo "  docker-publish  - Publish image"
            echo ""
          '')
          (pkgs.writeScriptBin "docker-login" ''
            #!/usr/bin/env bash
            echo "Logging in to Docker Hub as l1ne..."
            docker login -u l1ne
          '')
          (pkgs.writeScriptBin "docker-publish" ''
            #!/usr/bin/env bash
            echo "Building binaries with Zig..."
            zig build -Doptimize=ReleaseFast

            echo "Building Docker image..."
            docker build -t l1ne/quic-zig:latest .

            echo "Pushing to Docker Hub (l1ne/quic-zig:latest)..."
            docker push l1ne/quic-zig:latest

            echo ""
            echo "✓ Image published successfully!"
            echo "  Repository: https://hub.docker.com/r/l1ne/quic-zig"
            echo ""
            echo "You can now run: test-interop"
          '')
          (pkgs.writeScriptBin "test-interop" ''
            #!/usr/bin/env bash
            if [ ! -d quic-interop-runner ]; then
              echo "Error: quic-interop-runner not found"
              echo "Run: setup"
              exit 1
            fi

            if [ ! -d quic-interop-runner/.venv ]; then
              echo "Error: Python venv not found"
              echo "Run: setup"
              exit 1
            fi

            echo "Building binaries with Zig..."
            zig build -Doptimize=ReleaseFast

            echo "Building Docker image..."
            docker build -t l1ne/quic-zig:latest .

            echo "Running interop tests..."
            cd quic-interop-runner

            # Use venv's python directly (installed by uv)
            .venv/bin/python run.py -s quic-zig -c quic-zig "$@"
          '')
        ];

        shellHook = ''
          echo "QUIC-Zig Development Environment"
          echo "================================"
          echo ""

          # Check if setup has been run
          if [ ! -f .setup-complete ]; then
            echo "⚠️  First time setup required!"
            echo ""
            echo "Run: setup"
            echo ""
          else
            echo "Quick Commands:"
            echo "  zig build        - Build all binaries"
            echo "  test-interop     - Run QUIC interop tests"
            echo "  zig build test   - Run unit tests"
            echo ""
            echo "Docker Hub:"
            echo "  docker-login     - Login to Docker Hub (l1ne)"
            echo "  docker-publish   - Build and publish"
            echo ""
            echo "Other:"
            echo "  setup            - Re-run setup if needed"
            echo ""
          fi
        '';
      };
    };
}
