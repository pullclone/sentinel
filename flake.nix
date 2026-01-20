{
  description = "Sentinel vNext - policy validation + status reporting (Rust)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      nixosModules.sentinel = import ./nix/module.nix;

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.rustPlatform.buildRustPackage {
            pname = "sentinelctl";
            version = "0.1.0";
            src = ./.;
            cargoLock = {
              lockFile = ./Cargo.lock;
            };
            cargoHash = "sha256-dYOdyZn0byioLz8GiT3aghjTUTBeQ3tdAk3UAlfe7d8=";

            meta = with pkgs.lib; {
              description = "Sentinel CLI (policy validation + status reporting)";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          };
        });

      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              rustc
              rustfmt
              clippy
              pkg-config
            ];
          };
        });

      checks = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in
        {
          fmt = pkgs.runCommand "fmt-check" { buildInputs = [ pkgs.rustfmt ]; } ''
            cd ${self}
            cargo fmt -- --check
            touch $out
          '';
        });
    };
}
