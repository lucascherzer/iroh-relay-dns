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

      getSystemKey = system:
        if system == "x86_64-linux" then "x86_64-linux"
        else if system == "aarch64-linux" then "aarch64-linux"
        else if system == "x86_64-darwin" then "x86_64-darwin"
        else if system == "aarch64-darwin" then "aarch64-darwin"
        else null;

      getTarget = system:
        if system == "x86_64-linux" then "x86_64-unknown-linux-musl"
        else if system == "aarch64-linux" then "aarch64-unknown-linux-musl"
        else if system == "x86_64-darwin" then "x86_64-apple-darwin"
        else if system == "aarch64-darwin" then "aarch64-apple-darwin"
        else null;

      mkPackage = { pkgs, pname, system }:
        let
          systemKey = getSystemKey system;
          target = getTarget system;
          hash = hashes.${pname}.${systemKey};
          url = "https://github.com/n0-computer/iroh/releases/download/v${version}/${pname}-v${version}-${target}.tar.gz";
        in
        pkgs.stdenv.mkDerivation {
          inherit pname version;

          src = pkgs.fetchurl {
            inherit url hash;
          };

          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ${pname} $out/bin/
            chmod +x $out/bin/${pname}
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Iroh ${pname} - distributed data synchronization";
            homepage = "https://iroh.computer";
            license = licenses.mit;
            platforms = supportedSystems;
            mainProgram = pname;
          };
        };

      mkPackages = system:
        let
          pkgs = nixpkgsFor system;
        in
        {
          iroh-dns-server = mkPackage { inherit pkgs system; pname = "iroh-dns-server"; };
          iroh-relay = mkPackage { inherit pkgs system; pname = "iroh-relay"; };
        };

    in
    {
      packages = forAllSystems (system:
        (mkPackages system) // {
          default = self.packages.${system}.iroh-relay;
        }
      );
    };
}
