{
  description = "Iroh DNS and Relay servers from GitHub releases";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      version = "0.96.0";
      hashes = builtins.fromJSON (builtins.readFile ./hashes.json);

      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      nixpkgsFor = system: import nixpkgs { inherit system; };

      systemToTarget = {
        "x86_64-linux"   = "x86_64-unknown-linux-musl";
        "aarch64-linux"  = "aarch64-unknown-linux-musl";
        "x86_64-darwin"  = "x86_64-apple-darwin";
        "aarch64-darwin" = "aarch64-apple-darwin";
      };

      mkPackage = { pkgs, pname, system }:
        let
          target = systemToTarget.${system};
          hash   = hashes.${pname}.${system};
          url    = "https://github.com/n0-computer/iroh/releases/download/v${version}/${pname}-v${version}-${target}.tar.gz";
        in
        pkgs.stdenv.mkDerivation {
          inherit pname version;

          src = pkgs.fetchurl { inherit url hash; };

          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ${pname} $out/bin/
            chmod +x $out/bin/${pname}
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Iroh ${pname} — distributed data synchronisation";
            homepage    = "https://iroh.computer";
            license     = licenses.mit;
            platforms   = supportedSystems;
            mainProgram = pname;
          };
        };

      mkPackages = system:
        let pkgs = nixpkgsFor system; in {
          iroh-dns-server = mkPackage { inherit pkgs system; pname = "iroh-dns-server"; };
          iroh-relay      = mkPackage { inherit pkgs system; pname = "iroh-relay"; };
        };

    in
    {
      # ── Packages ────────────────────────────────────────────────────────────
      packages = forAllSystems (system:
        (mkPackages system) // {
          default = self.packages.${system}.iroh-relay;
        }
      );

      # ── NixOS modules ───────────────────────────────────────────────────────
      nixosModules = {
        iroh-relay      = import ./modules/iroh-relay.nix;
        iroh-dns-server = import ./modules/iroh-dns-server.nix;
        default         = import ./modules/iroh-relay.nix;
      };

      # ── Checks ──────────────────────────────────────────────────────────────
      # Build packages on Linux systems (Darwin is fine to skip in CI).
      checks = forAllSystems (system:
        let pkgs = nixpkgsFor system; in
        (mkPackages system) // nixpkgs.lib.optionalAttrs
          (nixpkgs.lib.hasSuffix "-linux" system)
          {
            # Evaluate the NixOS modules – a lightweight type-check that
            # doesn't require a full system build.
            # We access config.system.build.toplevel but supply the minimum
            # stubs required by NixOS to pass its assertions.
            module-iroh-relay = (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.iroh-relay
                {
                  services.iroh-relay.package = self.packages.${system}.iroh-relay;
                  # Minimum stubs to satisfy NixOS assertions.
                  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
                  boot.loader.grub.devices = [ "/dev/sda" ];
                  system.stateVersion = "24.11";
                }
              ];
            }).config.system.build.toplevel;

            module-iroh-dns-server = (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.iroh-dns-server
                {
                  services.iroh-dns-server = {
                    package    = self.packages.${system}.iroh-dns-server;
                    configFile = pkgs.writeText "iroh-dns-server.toml" "";
                  };
                  # Minimum stubs to satisfy NixOS assertions.
                  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
                  boot.loader.grub.devices = [ "/dev/sda" ];
                  system.stateVersion = "24.11";
                }
              ];
            }).config.system.build.toplevel;
          }
      );
    };
}
