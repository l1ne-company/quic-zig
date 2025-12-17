{
  description = "quic-zig";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
          pkgs.liboqs
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
            mkdir -p quic-interop-runner-tests/test-data/{www,downloads,certs,logs}
            echo "   ✓ Created test-data directories"

            # 2. Generate certificates if needed
            if [ ! -f quic-interop-runner-tests/test-data/certs/cert.pem ]; then
              echo ""
              echo "2. Generating test certificates..."
              ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
                -keyout quic-interop-runner-tests/test-data/certs/priv.key \
                -out quic-interop-runner-tests/test-data/certs/cert.pem \
                -days 365 \
                -subj "/CN=server/O=QuicZig/C=US" \
                -addext "subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1" 2>/dev/null
              chmod 600 quic-interop-runner-tests/test-data/certs/priv.key
              chmod 644 quic-interop-runner-tests/test-data/certs/cert.pem
              echo "   ✓ Generated test certificates"
            else
              echo ""
              echo "2. Test certificates already exist"
            fi

            # 3. Create test files
            echo ""
            echo "3. Creating test files..."
            echo "Hello from QUIC server!" > quic-interop-runner-tests/test-data/www/index.html
            echo "This is a test file for QUIC transfer." > quic-interop-runner-tests/test-data/www/test.txt
            dd if=/dev/urandom of=quic-interop-runner-tests/test-data/www/large.bin bs=1M count=1 2>/dev/null
            echo "   ✓ Created test files"

            # 4. Initialize quic-interop-runner submodule
            echo ""
            echo "4. Setting up quic-interop-runner submodule..."
            git submodule update --init --recursive
            echo "   ✓ Initialized quic-interop-runner submodule"

            # 5. Setup Python environment with uv
            echo ""
            echo "5. Setting up Python environment with uv..."
            cd quic-interop-runner-tests

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
          '')
          (pkgs.writeScriptBin "test-interop" ''
            #!/usr/bin/env bash
            if [ ! -d quic-interop-runner-tests ]; then
              echo "Error: quic-interop-runner-tests not found"
              echo "Run: setup"
              exit 1
            fi

            if [ ! -d quic-interop-runner-tests/.venv ]; then
              echo "Error: Python venv not found"
              echo "Run: setup"
              exit 1
            fi

            echo "Building binaries with Zig..."
            zig build -Doptimize=ReleaseFast

            echo "Building Docker image..."
            docker build -t l1ne/quic-zig:latest .

            echo "Running interop tests..."
            cd quic-interop-runner-tests

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
            echo "  setup            - Re-run setup if needed"
            echo ""
          fi
        '';
      };
    };
}
