{
  description = "Nix flake for wg-easy (packaged as github.com/fnltochka/wg-easy-nix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    wg-easy-src = {
      url = "github:wg-easy/wg-easy";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    systems,
    wg-easy-src,
    ...
  }: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    packages = eachSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      nodejs = pkgs.nodejs_20;
      pnpm = pkgs.pnpm.override {inherit nodejs;};
    in rec {
      wg-easy = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "wg-easy";
        version = "15.2.1";

        src = wg-easy-src + "/src";

        pnpmDeps = pnpm.fetchDeps {
          inherit (finalAttrs) pname version;
          src = wg-easy-src + "/src";
          fetcherVersion = 2;
          hash = "sha256-jJ6H4gKnHywbqiiYd9fXqfnTvPJuPoX76A8i4Lhc26k=";
        };

        nativeBuildInputs = [
          nodejs
          pkgs.makeWrapper
          pnpm.configHook
        ];

        env.NUXT_TELEMETRY_DISABLED = "1";

        buildPhase = ''
          runHook preBuild

          pnpm build
          pnpm run cli:build

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/app"
          cp -r .output/. "$out/app/"

          # Prune dev dependencies for smaller output
          pnpm prune --prod --ignore-scripts
          cp -r node_modules "$out/app/node_modules"

          mkdir -p "$out/app/server/database"
          cp -r server/database/migrations "$out/app/server/database/migrations"

          mkdir -p "$out/bin"

          makeWrapper ${nodejs}/bin/node "$out/bin/wg-easy-server" \
            --chdir "$out/app" \
            --add-flags server/index.mjs

          makeWrapper ${nodejs}/bin/node "$out/bin/wg-easy-cli" \
            --chdir "$out/app" \
            --add-flags server/cli.mjs

          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "The easiest way to run WireGuard VPN + Web-based Admin UI";
          homepage = "https://github.com/wg-easy/wg-easy";
          license = licenses.agpl3Plus;
          maintainers = with maintainers; [
            FnlTochka
          ];
        };
      });

      default = wg-easy;
    });

    nixosModules.wg-easy = {
      config,
      lib,
      pkgs,
      ...
    }:
      import ./nixosModules/wg-easy.nix {
        inherit self config lib pkgs;
      };

    nixosModules.default = self.nixosModules.wg-easy;
  };
}
