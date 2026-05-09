{
  description = "D&D combat encounter manager and monster database";
  inputs = {
    # LLM: Do NOT change this URL unless explicitly directed. This is the
    # correct format for nixpkgs stable (25.11 is correct, not nixos-25.11).
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    changelog-roller.url = "github:LoganBarnett/changelog-roller";
    # Shared infrastructure crate + Nix helpers (mkRustProject,
    # mkNixosService, mkDarwinService).
    foundation.url = "github:LoganBarnett/rust-template";
    foundation.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
    changelog-roller,
    foundation,
  }: let
    project = foundation.lib.mkRustProject {
      inherit self nixpkgs rust-overlay crane;
      name = "ezpz-dndz";
      crates = {
        cli = {
          name = "ezpz-dndz-cli";
          binary = "ezpz-dndz-cli";
          description = "CLI for the ezpz-dndz monster database and encounter manager.";
        };
        server = {
          name = "ezpz-dndz-server";
          binary = "ezpz-dndz-server";
          description = "HTTP server for the ezpz-dndz combat encounter manager and monster database.";
        };
        # Note: the 'lib' crate is not included here as it doesn't
        # produce a binary.
      };
      extraDevPackages = system: pkgs: [
        pkgs.cargo-sweep
        pkgs.jq
        # Elm toolchain — frontend lives in frontend/ and is not part
        # of any Cargo build.
        pkgs.elmPackages.elm
        pkgs.elmPackages.elm-format
        pkgs.elmPackages.elm-test
        pkgs.elm2nix
        # Unified formatter and friends.
        pkgs.treefmt
        pkgs.alejandra
        pkgs.prettier
        pkgs.just
        # Diagram tooling for architecture / data-model visuals
        # (used by docs in ./docs/diagrams).
        pkgs.d2
        changelog-roller.packages.${system}.default
      ];
      shellHook = _pkgs: ''
        echo "ezpz-dndz development environment"
        echo ""
        echo "Available Cargo packages (use 'cargo build -p <name>'):"
        cargo metadata --no-deps --format-version 1 2>/dev/null | \
          jq -r '.packages[].name' | \
          sort | \
          sed 's/^/  • /' || echo "  Run 'cargo init' to get started"

        echo ""
        echo "Elm frontend (frontend/):"
        echo "  Build:   cd frontend && elm make src/Main.elm --output public/elm.js"
        echo "  Format:  treefmt"
        echo "  After changing elm.json dependency versions, regenerate Nix files:"
        echo "    cd frontend"
        echo "    elm2nix convert 2>/dev/null > elm-srcs.nix"
        echo "    elm2nix snapshot"
        echo "    git add elm-srcs.nix registry.dat && git commit"
      '';
    };
  in
    project
    // {
      # =========================================================
      # NIXOS MODULES
      # =========================================================
      nixosModules = {
        server = import ./nix/modules/nixos-server.nix {
          inherit self foundation;
        };
        default = self.nixosModules.server;
      };

      # =========================================================
      # DARWIN MODULES
      # =========================================================
      darwinModules = {
        server = import ./nix/modules/darwin-server.nix {
          inherit self foundation;
        };
        default = self.darwinModules.server;
      };
    };
}
