# NixOS VM smoke test for the iroh-relay NixOS module.
#
# Runs iroh-relay in --dev mode (plain HTTP, port 3340) so no TLS
# certificates are required, making the test self-contained.
#
# Usage (called from flake.nix checks):
#   pkgs.callPackage ./tests/vm/smoke-test-iroh-relay.nix {
#     inherit (self.packages.${system}) iroh-relay;
#     nixosModule = self.nixosModules.iroh-relay;
#   }

{ pkgs, iroh-relay, nixosModule }:

pkgs.testers.runNixOSTest {
  name = "iroh-relay-smoke-test";

  nodes = {
    machine = { config, pkgs, lib, ... }: {
      imports = [ nixosModule ];

      services.iroh-relay = {
        enable  = true;
        package = iroh-relay;
        devMode = true;   # HTTP on port 3340, no TLS needed
      };

      networking.firewall.enable = false;

      environment.systemPackages = with pkgs; [
        curl
        iproute2
      ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    ${builtins.readFile ./helpers/smoke_test_iroh_relay.py}

    main(machine)
  '';
}
