# NixOS VM smoke test for the iroh-dns-server NixOS module.
#
# Uses a minimal TOML config that binds DNS on an unprivileged port (5353)
# and HTTP on port 8080, so no CAP_NET_BIND_SERVICE tricks are needed for
# the test itself (the module still grants the capability in production).
#
# Usage (called from flake.nix checks):
#   pkgs.callPackage ./tests/vm/smoke-test-iroh-dns-server.nix {
#     inherit (self.packages.${system}) iroh-dns-server;
#     nixosModule = self.nixosModules.iroh-dns-server;
#   }

{ pkgs, iroh-dns-server, nixosModule }:

pkgs.testers.runNixOSTest {
  name = "iroh-dns-server-smoke-test";

  nodes = {
    machine = { config, pkgs, lib, ... }: {
      imports = [ nixosModule ];

      services.iroh-dns-server = {
        enable  = true;
        package = iroh-dns-server;

        # Provide a minimal verbatim config pointing at unprivileged ports.
        configFile = pkgs.writeText "iroh-dns-server-test.toml" ''
          pkarr_put_rate_limit = "disabled"

          [http]
          port = 8080

          [dns]
          port      = 5353
          origins   = ["."]
          rr_a      = "127.0.0.1"
          default_soa = "ns1.example.org. hostmaster.example.org. 0 10800 3600 604800 3600"

          [mainline]
          enabled = false
        '';
      };

      networking.firewall.enable = false;

      environment.systemPackages = with pkgs; [
        curl
        iproute2
        dig
      ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    ${builtins.readFile ./helpers/smoke_test_iroh_dns_server.py}

    main(machine)
  '';
}
