{ config, lib, pkgs, ... }:

let
  cfg = config.services.iroh-dns-server;
  settingsFormat = pkgs.formats.toml { };
in

{
  # ────────────────────────────────────────────────────────────────────────────
  # Options
  # ────────────────────────────────────────────────────────────────────────────
  options.services.iroh-dns-server = {

    enable = lib.mkEnableOption "iroh-dns-server — pkarr relay and DNS server for iroh";

    package = lib.mkPackageOption pkgs "iroh-dns-server" { };

    # ── Config ───────────────────────────────────────────────────────────────
    # Users can supply a verbatim config file path …
    configFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an existing TOML configuration file for iroh-dns-server.
        When set, <option>settings</option> is ignored.

        At minimum the server needs a "[dns]" section with
        "origins", "rr_a" and
        "default_soa".  See the upstream example configs at
        <https://github.com/n0-computer/iroh/tree/main/iroh-dns-server>.
      '';
    };

    # … or let the module generate one from structured settings.
    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          pkarr_put_rate_limit = lib.mkOption {
            type    = lib.types.str;
            default = "smart";
            example = "disabled";
            description = ''
              Rate limit for pkarr PUT requests.
              Valid values: ""smart"", ""disabled"",
              or a number (requests per second).
            '';
          };

          http = lib.mkOption {
            type = lib.types.submodule {
              freeformType = settingsFormat.type;
              options = {
                port = lib.mkOption {
                  type    = lib.types.port;
                  default = 8080;
                  description = "HTTP port for the pkarr / DoH HTTP endpoint.";
                };
                bind_addr = lib.mkOption {
                  type    = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "0.0.0.0";
                  description = "Address to bind the HTTP server on.";
                };
              };
            };
            default     = { };
            description = "HTTP server configuration.";
          };

          https = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              freeformType = settingsFormat.type;
              options = {
                port = lib.mkOption {
                  type    = lib.types.port;
                  default = 443;
                  description = "HTTPS port.";
                };
                domains = lib.mkOption {
                  type    = lib.types.listOf lib.types.str;
                  default = [ ];
                  example = [ "irohdns.example.org" ];
                  description = "Domains for which TLS certificates are obtained.";
                };
                cert_mode = lib.mkOption {
                  type    = lib.types.enum [ "lets_encrypt" "self_signed" "manual" ];
                  default = "lets_encrypt";
                  description = "Certificate acquisition mode.";
                };
                letsencrypt_prod = lib.mkOption {
                  type    = lib.types.bool;
                  default = true;
                  description = "Use the Let's Encrypt production CA (vs. staging).";
                };
              };
            });
            default     = null;
            description = "HTTPS configuration. Leave null to run HTTP only.";
          };

          dns = lib.mkOption {
            type = lib.types.submodule {
              freeformType = settingsFormat.type;
              options = {
                port = lib.mkOption {
                  type    = lib.types.port;
                  default = 53;
                  description = "UDP/TCP port for DNS queries.";
                };
                bind_addr = lib.mkOption {
                  type    = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "0.0.0.0";
                  description = "Address to bind the DNS server on.";
                };
                origins = lib.mkOption {
                  type    = lib.types.listOf lib.types.str;
                  default = [ "." ];
                  example = [ "irohdns.example.org." "." ];
                  description = "DNS origins served by this server.";
                };
                default_ttl = lib.mkOption {
                  type    = lib.types.int;
                  default = 30;
                  description = "Default DNS TTL in seconds.";
                };
                default_soa = lib.mkOption {
                  type    = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "ns1.example.org hostmaster.example.org 0 10800 3600 604800 3600";
                  description = "Default SOA record for the zone.";
                };
                rr_a = lib.mkOption {
                  type    = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "203.0.10.10";
                  description = "IPv4 address for the A record of the zone apex.";
                };
                rr_ns = lib.mkOption {
                  type    = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "ns1.example.org.";
                  description = "NS record value for the zone apex.";
                };
              };
            };
            default     = { };
            description = "DNS server configuration.";
          };

          mainline = lib.mkOption {
            type = lib.types.submodule {
              freeformType = settingsFormat.type;
              options = {
                enabled = lib.mkOption {
                  type    = lib.types.bool;
                  default = false;
                  description = "Whether to bootstrap from the mainline DHT.";
                };
              };
            };
            default     = { };
            description = "Mainline DHT bootstrap configuration.";
          };
        };
      };
      default     = { };
      description = ''
        Structured iroh-dns-server configuration serialised to TOML.
        Ignored when <option>configFile</option> is set.
        See <https://github.com/n0-computer/iroh/blob/main/iroh-dns-server/config.prod.toml>
        for a production example.
      '';
    };

    # ── Firewall ─────────────────────────────────────────────────────────────
    openFirewall = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Open the firewall for the DNS port (53 UDP+TCP), HTTP port (8080) and,
        if HTTPS is configured, port 443.
        Adjust if you have customised the bind addresses.
      '';
    };

    # ── systemd tweaks ───────────────────────────────────────────────────────
    extraArgs = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments passed to iroh-dns-server.";
    };

    environmentFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing environment variables (one KEY=value per line).
        Useful for supplying secrets without putting them in the Nix store.
      '';
    };
  };

  # ────────────────────────────────────────────────────────────────────────────
  # Implementation
  # ────────────────────────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {

    # ── User / group ─────────────────────────────────────────────────────────
    users.users.iroh-dns-server = {
      isSystemUser = true;
      group        = "iroh-dns-server";
      description  = "iroh-dns-server service user";
      home         = "/var/lib/iroh-dns-server";
    };
    users.groups.iroh-dns-server = { };

    # ── Firewall ─────────────────────────────────────────────────────────────
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 53 cfg.settings.http.port ]
        ++ lib.optional (cfg.settings.https != null) cfg.settings.https.port;
      allowedUDPPorts = [ 53 ];
    };

    # ── systemd service ───────────────────────────────────────────────────────
    systemd.services.iroh-dns-server = {
      description = "iroh-dns-server — pkarr relay and DNS server";
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig =
        let
          # Build config file: prefer explicit path, fall back to generated TOML.
          resolvedConfigFile =
            if cfg.configFile != null
            then cfg.configFile
            else
              let
                # Remove null-valued leaf fields so they are omitted from TOML.
                cleanSubAttrs = attrs: lib.filterAttrs (_k: v: v != null) attrs;
                cleanSettings =
                  lib.mapAttrs
                    (_k: v: if builtins.isAttrs v then cleanSubAttrs v else v)
                    (lib.filterAttrs (_k: v: v != null) cfg.settings);
              in
              settingsFormat.generate "iroh-dns-server.toml" cleanSettings;
        in
        {
          Type             = "simple";
          User             = "iroh-dns-server";
          Group            = "iroh-dns-server";
          StateDirectory   = "iroh-dns-server";
          WorkingDirectory = "/var/lib/iroh-dns-server";
          Restart          = "on-failure";
          RestartSec       = "5s";

          ExecStart = lib.concatStringsSep " " (
            [ "${cfg.package}/bin/iroh-dns-server" "--config" (toString resolvedConfigFile) ]
            ++ map lib.escapeShellArg cfg.extraArgs
          );

          EnvironmentFile = lib.mkIf (cfg.environmentFile != null)
            (toString cfg.environmentFile);

          # Hardening
          NoNewPrivileges      = true;
          PrivateTmp           = true;
          ProtectSystem        = "strict";
          ProtectHome          = true;
          ReadWritePaths       = [ "/var/lib/iroh-dns-server" ];
          # DNS on port 53 requires CAP_NET_BIND_SERVICE.
          CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
          AmbientCapabilities  = "CAP_NET_BIND_SERVICE";
        };
    };
  };
}
