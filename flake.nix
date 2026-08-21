{
  description = "D&D combat encounter manager and monster database";
  inputs = {
    # LLM: Do NOT change this URL unless explicitly directed. This is the
    # correct format for nixpkgs stable (25.11 is correct, not nixos-25.11).
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    changelog-roller.url = "github:LoganBarnett/changelog-roller";
    # Shared infrastructure crate + Nix helpers (mkRustPackages, the
    # cross-compile package sets, mkCiShell, mkNixosService,
    # mkDarwinService, cargoHuskyHookSnippet).
    foundation.url = "github:LoganBarnett/rust-template";
    foundation.inputs.nixpkgs.follows = "nixpkgs";
    # Formats org-mode documents (treefmt delegates .org files to it).
    # Re-adopted after upstream switched its orgize input from ssh:// to
    # https://, which had previously blocked use in environments without
    # SSH credentials.
    org-fmt.url = "github:LoganBarnett/org-fmt";
    org-fmt.inputs.nixpkgs.follows = "nixpkgs";
    org-fmt.inputs.rust-overlay.follows = "rust-overlay";
    org-fmt.inputs.crane.follows = "crane";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
    changelog-roller,
    foundation,
    org-fmt,
  }: let
    forAllSystems =
      nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    perSystem = forAllSystems (system: let
      # Hoisted so the quarantined `pkgsUnfreeFor` instance below (used
      # only because this project links Apple frameworks) stays
      # overlay-consistent with this build `pkgs` — both see the same
      # overlay set.
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      craneLib =
        (crane.mkLib pkgs).overrideToolchain
        (p: p.rust-bin.stable.latest.default);
      rust = pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          "rust-src"
          "rust-analyzer"
          "rustfmt"
        ];
      };
      # Workspace crate map.  The 'lib' crate is intentionally absent —
      # it doesn't produce a binary.  The server entry has a
      # per-crate override at nix/packages/server.nix that hands the
      # compiled Elm frontend to the crate build for embedding;
      # mkRustPackages (and the cross-compile helpers below, which
      # thread the same override) pick it up automatically by the
      # convention `self + "/nix/packages/<key>.nix"`.
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
      };
      commonArgs = {
        # cleanCargoSource keeps only Cargo-relevant files (manifests,
        # lockfile, .rs).  The server crate additionally include_str!'s
        # the SRD creature bundle at compile time, so extend the filter
        # to keep that one data file; without it every crate build fails
        # inside the sandbox with "couldn't read …bundled-creatures.json".
        src = nixpkgs.lib.cleanSourceWith {
          src = self;
          filter = path: type:
            (craneLib.filterCargoSources path type)
            || nixpkgs.lib.hasSuffix "bundled-creatures.json" path;
          name = "source";
        };
        # Run only unit tests (--lib --bins); integration tests under
        # tests/ may require external services not available in the
        # Nix sandbox.
        cargoTestExtraArgs = "--lib --bins";
      };
      rustPackages = foundation.lib.mkRustPackages {
        inherit self pkgs craneLib crates commonArgs;
      };
      # On Linux each binary also gets a statically-linked `<name>-musl`
      # variant; on other systems mkMuslPackages returns an empty set.  It
      # threads the same commonArgs, so a project's native dependencies
      # reach the musl build as they do the native one.
      muslPackages = foundation.lib.mkMuslPackages {
        inherit self pkgs system crates crane commonArgs;
      };
      # On Linux each binary also gets a portable `<name>-gnu` variant: a
      # dynamic glibc build that runs off the Nix store (FHS interpreter,
      # glibc 2.17 floor) and links the host's shared libraries.  Pick
      # this over musl for a tool that must use a host library with a
      # runtime plugin/dlopen ecosystem.  Empty on other systems.
      gnuPortablePackages = foundation.lib.mkGnuPortablePackages {
        inherit self pkgs system crates crane commonArgs;
      };
      # The x86_64-linux build cross-compiles macOS `<key>-<arch>-darwin`
      # variants via zig so a release needs no macOS runner; empty on
      # other systems.  This project links Apple frameworks — the OIDC
      # stack pulls security-framework through reqwest's
      # rustls-tls-native-roots — so the darwin cross build needs the
      # Apple SDK's headers and link stubs.  `"apple-frameworks": true`
      # in rust-template.json turns that on (the same flag shape as
      # `windows-msvc` below); the SDK comes from a quarantined unfree
      # nixpkgs so this build `pkgs` graph stays licence-free, and
      # evaluating it accepts the darwin-gated Apple SDK licence here in
      # the project's own flake — the visible consent.  See
      # CONTRIBUTING.org.
      appleFrameworksEnabled =
        (builtins.fromJSON (builtins.readFile ./rust-template.json)).apple-frameworks
        or false;
      darwinCrossPackages = foundation.lib.mkDarwinCrossPackages {
        inherit self pkgs system crates crane commonArgs;
        appleSdk =
          if appleFrameworksEnabled
          then (foundation.lib.pkgsUnfreeFor {inherit nixpkgs system overlays;}).apple-sdk.src
          else null;
      };
      # Native Windows PE variants (`<key>-{x86_64,aarch64}-windows`),
      # cross-compiled via llvm-mingw for the gnullvm targets — no
      # Microsoft SDK, no Cygwin/MSYS2 runtime; a pure-Rust binary needs
      # only the OS Universal CRT (Windows 10+).  Unlike the darwin cross
      # build this is host-agnostic (llvm-mingw ships a per-host
      # toolchain), so it builds on Linux CI runners and on a
      # contributor's Mac alike.  Requires a toolchain ≥ Rust 1.91 for
      # the aarch64 gnullvm std — see CONTRIBUTING.org.
      windowsCrossPackages = foundation.lib.mkWindowsCrossPackages {
        inherit self pkgs system crates crane commonArgs;
      };
      # The opt-in MSVC-ABI Windows variant (`<key>-x86_64-windows-msvc`),
      # for a dependency that requires the MSVC ABI rather than the
      # default gnullvm path above.  Off unless `"windows-msvc": true` is
      # set in rust-template.json — that flag hands the helper the
      # xwin-splatted Microsoft SDK (foundation.lib.xwinSdk), and
      # evaluating it accepts Microsoft's SDK licence in this project's
      # own flake.  The SDK is a fixed-output fetch, so there is no
      # build-time download and no Docker.
      windowsMsvcEnabled =
        (builtins.fromJSON (builtins.readFile ./rust-template.json)).windows-msvc
        or false;
      windowsMsvcCrossPackages = foundation.lib.mkWindowsMsvcCrossPackages {
        inherit self pkgs system crates crane commonArgs;
        xwinSdk =
          if windowsMsvcEnabled
          then foundation.lib.xwinSdk {inherit pkgs;}
          else null;
      };
      packages =
        rustPackages.packages
        // muslPackages
        // gnuPortablePackages
        // darwinCrossPackages
        // windowsCrossPackages
        // windowsMsvcCrossPackages
        // {
          # Whole-workspace convenience build.  It compiles the server
          # crate too, whose rust_embed Frontend needs an asset dir at
          # macro-expansion time; hand it an empty stub since this
          # package is not the deployable server artifact (that is
          # `.#server`, which embeds the real compiled frontend via its
          # per-crate override).
          default = craneLib.buildPackage (commonArgs
            // {
              pname = "ezpz-dndz";
              RUST_TEMPLATE_FRONTEND_DIR = pkgs.emptyDirectory;
            });
        };
      # The arm64 subset of the darwin cross outputs — the only ones
      # re-signed (and so the only ones the signature guard below
      # verifies).  Empty except on x86_64-linux.
      aarch64DarwinPackages =
        nixpkgs.lib.filterAttrs
        (name: _: nixpkgs.lib.hasSuffix "-aarch64-darwin" name)
        darwinCrossPackages;
      # The x86_64 subset of the Windows cross outputs, smoke-tested
      # under wine.  Non-empty on every host (the Windows helper is
      # host-agnostic), so the wine check below is gated on
      # `system == "x86_64-linux"` rather than on emptiness: wine runs a
      # win64 PE reliably only there.
      windowsX86Packages =
        nixpkgs.lib.filterAttrs
        (name: _: nixpkgs.lib.hasSuffix "-x86_64-windows" name)
        windowsCrossPackages;
    in {
      inherit packages;
      inherit (rustPackages) apps;
      # The darwin ad-hoc signature guard runs on x86_64-linux, where the
      # zig-cross darwin binaries are produced.  mkDarwinCrossPackages
      # re-signs each arm64 binary after the release profile's
      # `strip = true` would otherwise invalidate zig's link-time
      # signature; an arm64 Mach-O with an invalid signature is SIGKILLed
      # by the kernel with no output, so this check proves the shipped
      # signature is intact.  Only the arm64 outputs are checked — x86_64
      # macOS does not enforce signatures, so those binaries ship
      # unsigned.  Empty (and so absent) on every other system.
      checks =
        rustPackages.checks
        // nixpkgs.lib.optionalAttrs (aarch64DarwinPackages != {}) {
          darwinSignatures = foundation.lib.mkDarwinSignatureCheck {
            inherit pkgs;
            darwinPackages = aarch64DarwinPackages;
          };
        }
        # Run the x86_64 Windows cross binaries under wine to prove they
        # execute, not merely link.  Gated to x86_64-linux: wine cannot
        # exec an aarch64 PE and is unreliable on Apple Silicon, so
        # aarch64 Windows is build-verified only.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          windowsSmoke = foundation.lib.mkWindowsSmokeCheck {
            inherit pkgs;
            windowsPackages = windowsX86Packages;
          };
        };
      devShells = {
        default = pkgs.mkShell {
          buildInputs = [
            rust
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
            # PDF tooling (pdftoppm + pdftotext) — used by Claude's
            # Read tool to render PDF pages for SRD / rulebook audits.
            pkgs.poppler-utils
            changelog-roller.packages.${system}.default
            # Formats org-mode documents (treefmt delegates .org files
            # to it).
            org-fmt.packages.${system}.default
            # One-shot Dependabot-backlog combiner, provided by the
            # foundation flake rather than copied in, so it stays
            # current with the template.  Run as
            # `just dependabot-combine`.
            foundation.packages.${system}.dependabot-combine
            # The daily dependency bumper the scheduled dependency-bump
            # workflow runs; also from the foundation flake.  Run
            # locally as `just dependency-bump` to bump and compose
            # changelog entries in the working tree for review.
            foundation.packages.${system}.dependency-bump
            # Blocks a Claude Code turn from ending on un-reviewed changes
            # until the template-compliance review passes.
            foundation.packages.${system}.review-stop
            # ABI baseline check; provided so `cargo semver-checks` can
            # run locally.  `doCheck = false` skips upstream's
            # target_feature_* snapshot tests, which assert against
            # snapshots recorded on x86_64 and therefore fail when
            # building on aarch64-darwin.  We only ship the binary, so
            # disabling the check phase does not affect what runs.
            (pkgs.cargo-semver-checks.overrideAttrs (_: {doCheck = false;}))
          ];
          shellHook = ''
            ${foundation.lib.cargoHuskyHookSnippet pkgs}
            echo "ezpz-dndz development environment"
            echo ""
            echo "Available Cargo packages (use 'cargo build -p <name>'):"
            cargo metadata --no-deps --format-version 1 2>/dev/null | \
              jq --raw-output '.packages[].name' | \
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

            # Nudge when the build cache is overdue for a sweep.
            # Cargo never garbage-collects superseded artifacts, so
            # target/ grows without bound (8.5 GB after three
            # months here, 97% of it stale duplicates).  This only
            # stats a marker file — measuring the tree would add
            # seconds to every direnv-triggered shell entry — and
            # never deletes anything on its own; `just sweep` is
            # always the explicit action.
            if [ -d target ]; then
              if [ ! -e target/.last-sweep ] \
                || [ -n "$(find target/.last-sweep -mtime +14 2>/dev/null)" ]; then
                echo ""
                echo "  ⚠ Build cache not swept in over 14 days — run 'just sweep'."
              fi
            fi
          '';
          # A runtime marker identifying this as the project's default
          # dev shell.  A compliance check reads it back with `nix eval`
          # to confirm this shell evaluates and carries the marker; the
          # `ci` shell carries the same marker with the value "ci".
          RUST_TEMPLATE_SHELL = "default";
        };
        # Minimal shell for CI jobs entered via `nix develop .#ci`: the
        # Rust toolchain plus the release CLIs (changelog-roller,
        # cargo-semver-checks) from foundation's mkCiShell baseline.  It
        # omits the interactive dev shell's extras (the Elm toolchain,
        # the treefmt formatter stack, just), so it is cheaper to
        # realize; the Elm frontend is a package-build input under
        # `nix build`, not something a devShell provides.
        ci = foundation.lib.mkCiShell {
          inherit pkgs system;
          toolchain = rust;
        };
      };
    });
  in {
    devShells = nixpkgs.lib.mapAttrs (_: p: p.devShells) perSystem;
    packages = nixpkgs.lib.mapAttrs (_: p: p.packages) perSystem;
    apps = nixpkgs.lib.mapAttrs (_: p: p.apps) perSystem;
    checks = nixpkgs.lib.mapAttrs (_: p: p.checks) perSystem;

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
