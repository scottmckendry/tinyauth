{
  description = "tinyauth development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Pinned commit of the conformance suite we test against
      conformanceSuiteRev = "826b64783b739e108dcd8a7623673c3b6b5c5284";
      conformanceSuiteUrl = "https://github.com/openid-certification/conformance-suite.git";

      # ---------------------------------------------------------------------------
      # Helper scripts
      # ---------------------------------------------------------------------------

      oidctest-up = pkgs.writeShellScriptBin "oidctest-up" ''
                  set -euo pipefail
                  REPO="$(git rev-parse --show-toplevel)"
                  cd "$REPO"

                  # 1. Clone the conformance suite if not present
                  if [ ! -d oidctest/.git ]; then
                    echo "Cloning conformance suite..."
                    git clone ${conformanceSuiteUrl} oidctest
                    git -C oidctest checkout ${conformanceSuiteRev}
                    git -C oidctest submodule update --init
                  else
                    CURRENT="$(git -C oidctest rev-parse HEAD)"
                    if [ "$CURRENT" != "${conformanceSuiteRev}" ]; then
                      echo "Updating conformance suite to pinned commit..."
                      git -C oidctest fetch origin
                      git -C oidctest checkout ${conformanceSuiteRev}
                      git -C oidctest submodule update --init
                    fi
                  fi

                  # 2. Copy our overlay files into the clone
                  #    (tracked in the tinyauth repo under oidctest-overlay/)
                  cp oidctest-overlay/docker-compose.override.yml oidctest/docker-compose.override.yml
                  mkdir -p oidctest/nginx
                  cp oidctest-overlay/nginx/Dockerfile-tinyauth oidctest/nginx/Dockerfile-tinyauth
                  cp oidctest-overlay/nginx/nginx-with-tinyauth.conf oidctest/nginx/nginx-with-tinyauth.conf

                  # 3. Build the conformance suite JAR if not present
                  if [ ! -f oidctest/target/fapi-test-suite.jar ]; then
                    echo "Building conformance suite JAR (this takes several minutes)..."
                    MAVEN_CACHE="''${MAVEN_CACHE:-$HOME/.m2}" \
                      docker compose -f oidctest/builder-compose.yml run --rm builder
                  fi

                  # 4. Build the nginx image and extract its self-signed cert so the
                  #    conformance suite JVM can trust it
                  if [ ! -f oidctest/nginx-selfsigned.crt ]; then
                    echo "Building nginx image and extracting TLS cert..."
                    docker compose \
                      -f oidctest/docker-compose.yml \
                      -f oidctest/docker-compose.override.yml \
                      build nginx
                    docker run --rm oidctest-nginx \
                      cat /etc/ssl/certs/nginx-selfsigned.crt \
                      > oidctest/nginx-selfsigned.crt
                  fi

                  # 5. Start the stack (--force-recreate avoids stale stopped containers)
                  docker compose \
                    -f oidctest/docker-compose.yml \
                    -f oidctest/docker-compose.override.yml \
                    up -d --force-recreate

                  echo ""
                  echo "Conformance suite is up: https://localhost.emobix.co.uk:8443"
                  echo ""
                  echo "To create a test plan:"
                  echo ""
                  echo "  1. Open https://localhost.emobix.co.uk:8443"
                  echo "  2. Click 'Create a new test plan'"
                  echo "  3. Set Plan Name:  oidcc-basic-certification-test-plan"
                  echo "  4. Set the variant dropdowns:"
                  echo "       server_metadata    -> discovery"
                  echo "       client_registration -> static_client"
                  echo "  5. Paste the following JSON into the 'JSON configuration' box:"
                  echo ""
                  cat <<'EOF'
        {
          "alias": "ta-test-suite",
          "server": {
            "discoveryUrl": "https://localhost.emobix.co.uk:3000/.well-known/openid-configuration",
            "login_hint": "admin"
          },
          "client": {
            "client_id": "certtest",
            "client_secret": "certtest-secret"
          },
          "client_secret_post": {
            "client_id": "certtest",
            "client_secret": "certtest-secret"
          },
          "client2": {
            "client_id": "certtest2",
            "client_secret": "certtest2-secret"
          }
        }
        EOF
                  echo ""
                  echo "  6. Click 'Create test plan' then run the tests."
                  echo "     When prompted to log in, use:  admin / admin"
                  echo ""
      '';

      oidctest-down = pkgs.writeShellScriptBin "oidctest-down" ''
        set -euo pipefail
        REPO="$(git rev-parse --show-toplevel)"
        cd "$REPO"
        docker compose \
          -f oidctest/docker-compose.yml \
          -f oidctest/docker-compose.override.yml \
          down
      '';

      tinyauth-up = pkgs.writeShellScriptBin "tinyauth-up" ''
        set -euo pipefail
        REPO="$(git rev-parse --show-toplevel)"
        cd "$REPO"

        if ! docker network inspect oidctest_default &>/dev/null; then
          echo "oidctest network not found — run oidctest-up first."
          exit 1
        fi

        docker compose -f docker-compose.dev.yml up -d --build
      '';

      tinyauth-down = pkgs.writeShellScriptBin "tinyauth-down" ''
        set -euo pipefail
        REPO="$(git rev-parse --show-toplevel)"
        cd "$REPO"
        docker compose -f docker-compose.dev.yml down
      '';

      dev-up = pkgs.writeShellScriptBin "dev-up" ''
        set -euo pipefail
        oidctest-up
        tinyauth-up
      '';

      dev-down = pkgs.writeShellScriptBin "dev-down" ''
        set -euo pipefail
        tinyauth-down || true
        oidctest-down || true
      '';

    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        name = "tinyauth";

        packages = with pkgs; [
          # Go toolchain
          go_1_26
          air # live-reload for the backend
          delve # debugger — binary is 'dlv', used by air.toml
          sqlc # SQL code generation
          gotools # goimports etc.

          # Frontend
          bun

          # Conformance testing
          oidctest-up
          oidctest-down
          tinyauth-up
          tinyauth-down
          dev-up
          dev-down
        ];

        shellHook = ''
                      # Write .env if it doesn't exist yet
                      REPO="$(git rev-parse --show-toplevel)"
                      ENV_FILE="$REPO/.env"

                      if [ ! -f "$ENV_FILE" ]; then
                        echo "Writing $ENV_FILE with default OIDC conformance test config..."
                        BCRYPT_HASH='$2y$10$DAFf0j.sRvldHWdNvr0UMu2taOFll.SMMe8s.thueK9D.LBZkjFVW'
                        # Double the $ signs so docker-compose doesn't treat them as variable interpolation
                        BCRYPT_HASH_ESCAPED=''${BCRYPT_HASH//\$/\$\$}
                        cat > "$ENV_FILE" <<EOF
          TINYAUTH_APPURL=https://localhost.emobix.co.uk:3000

          # Password: admin (bcrypt). Change this for anything non-local.
          TINYAUTH_AUTH_USERS=admin:$BCRYPT_HASH_ESCAPED

          TINYAUTH_OIDC_CLIENTS_CERTTEST_CLIENTID=certtest
          TINYAUTH_OIDC_CLIENTS_CERTTEST_CLIENTSECRET=certtest-secret
          TINYAUTH_OIDC_CLIENTS_CERTTEST_TRUSTEDREDIRECTURIS=https://localhost.emobix.co.uk:8443/test/a/ta-test-suite/callback

          TINYAUTH_OIDC_CLIENTS_CERTTEST2_CLIENTID=certtest2
          TINYAUTH_OIDC_CLIENTS_CERTTEST2_CLIENTSECRET=certtest2-secret
          TINYAUTH_OIDC_CLIENTS_CERTTEST2_TRUSTEDREDIRECTURIS=https://localhost.emobix.co.uk:8443/test/a/ta-test-suite/callback
          EOF
                        echo "Done. Edit $ENV_FILE to customise."
                      fi

                      echo ""
                      echo "tinyauth dev environment"
                      echo "------------------------"
                      echo "  dev-up          start both stacks (oidctest first, then tinyauth)"
                      echo "  dev-down        stop both stacks"
                      echo "  oidctest-up     start conformance suite (also prints test plan setup instructions)"
                      echo "  oidctest-down   stop conformance suite"
                      echo "  tinyauth-up     start tinyauth (requires oidctest-up first)"
                      echo "  tinyauth-down   stop tinyauth"
                      echo ""
                      echo "  Tinyauth:          https://localhost.emobix.co.uk:3000"
                      echo "  Conformance suite: https://localhost.emobix.co.uk:8443"
                      echo ""
        '';
      };
    };
}
