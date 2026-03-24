{
  description = "quic-zig";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      zig = pkgs.stdenv.mkDerivation {
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
          mkdir -p $out/bin
          cp -r ./* $out/
          ln -s $out/zig $out/bin/zig
        '';
      };

      setup = pkgs.writeShellApplication {
        name = "setup";
        runtimeInputs = [ pkgs.openssl pkgs.uv pkgs.jq ];
        text = ''
          echo "==> Creating test directories..."
          mkdir -p quic-interop-runner-tests/test-data/{www,downloads,certs,logs}

          echo "==> Generating certificates..."
          if [ ! -f quic-interop-runner-tests/test-data/certs/cert.pem ]; then
            openssl req -x509 -newkey rsa:2048 -nodes \
              -keyout quic-interop-runner-tests/test-data/certs/priv.key \
              -out  quic-interop-runner-tests/test-data/certs/cert.pem \
              -days 365 \
              -subj "/CN=server/O=QuicZig/C=US" \
              -addext "subjectAltName=DNS:server,DNS:localhost,IP:127.0.0.1" 2>/dev/null
            chmod 600 quic-interop-runner-tests/test-data/certs/priv.key
            chmod 644 quic-interop-runner-tests/test-data/certs/cert.pem
          else
            echo "    certificates already exist, skipping"
          fi

          echo "==> Creating test files..."
          echo "Hello from QUIC server!" > quic-interop-runner-tests/test-data/www/index.html
          echo "This is a test file for QUIC transfer." > quic-interop-runner-tests/test-data/www/test.txt
          dd if=/dev/urandom of=quic-interop-runner-tests/test-data/www/large.bin bs=1M count=1 2>/dev/null

          echo "==> Initializing submodule..."
          git submodule update --init --recursive

          echo "==> Setting up Python environment..."
          cd quic-interop-runner-tests
          uv venv
          uv pip install -r requirements.txt

          echo "==> Registering quic-zig implementation..."
          if ! grep -q '"quic-zig"' implementations.json; then
            cp implementations.json implementations.json.bak
            jq '. + {"quic-zig": {"image": "l1ne/quic-zig:latest", "url": "https://github.com/l1ne-company/quic-zig", "role": "both"}}' \
              implementations.json > implementations.json.tmp
            mv implementations.json.tmp implementations.json
          fi
          cd ..

          touch .setup-complete
          echo "==> Done. Run: zig build && test-interop"
        '';
      };

      test-interop = pkgs.writeShellApplication {
        name = "test-interop";
        text = ''
          [ -f .setup-complete ] || { echo "Run: setup"; exit 1; }

          echo "==> Building..."
          zig build -Doptimize=ReleaseFast

          echo "==> Building Docker image..."
          docker build -t l1ne/quic-zig:latest .

          echo "==> Running interop tests..."
          cd quic-interop-runner-tests
          .venv/bin/python run.py -s quic-zig -c quic-zig "$@"
        '';
      };
    in {
      packages.${system}.default = zig;

      devShells.${system}.default = pkgs.mkShell {
        packages = [ zig pkgs.openssl pkgs.python3 pkgs.uv pkgs.jq setup test-interop ];

        shellHook = ''
          if [ ! -f .setup-complete ]; then
            echo "quic-zig dev shell — first time? Run: setup"
          else
            echo "quic-zig dev shell — zig build | test-interop | setup"
          fi
        '';
      };
    };
}
