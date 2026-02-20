{ config, lib, pkgs, ... }:

let
  cfg = config.services.iroh-relay;
  settingsFormat = pkgs.formats.toml { };
in

{
  # ────────────────────────────────────────────────────────────────────────────
  # Options
  # ────────────────────────────────────────────────────────────────────────────
  options.services.iroh-relay = {

    enable = lib.mkEnableOption "iroh-relay — a relay / QUIC-address-discovery server for iroh";

    package = lib.mkPackageOption pkgs "iroh-relay" { };

    # ── Config file ─────────────────────────────────────────────────────────
    # Users can either supply a verbatim config file path …
    configFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an existing TOML configuration file for iroh-relay.
        When set, <option>settings</option> is ignored.
      '';
    };

    # … or let the module generate one from structured settings.
    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          enable_relay = lib.mkOption {
            type    = lib.types.bool;
            default = true;
            description = "Whether to enable the relay proxy. Disable for a holepunch-only server.";
          };
          http_bind_addr = lib.mkOption {
            type    = lib.types.nullOr lib.types.str;
            default = null;
            example = "[::]:80";
            description = "Socket address to bind the HTTP server on (default [::]:80).";
          };
          enable_quic_addr_discovery = lib.mkOption {
            type    = lib.types.bool;
            default = false;
            description = "Whether to enable QUIC address discovery. Requires TLS to be configured.";
          };
          enable_metrics = lib.mkOption {
            type    = lib.types.bool;
            default = true;
            description = "Whether to expose a Prometheus metrics endpoint.";
          };
          metrics_bind_addr = lib.mkOption {
            type    = lib.types.nullOr lib.types.str;
            default = null;
            example = "[::]:9090";
            description = "Socket address for the metrics endpoint. Defaults to the HTTP address on port 9090.";
          };
        };
      };
      default     = { };
      description = ''
        Structured iroh-relay configuration written to a TOML file.
        See <https://github.com/n0-computer/iroh/blob/main/iroh-relay/src/main.rs>
        for the full list of options.
        Ignored when <option>configFile</option> is set.
      '';
    };

    # ── Dev mode ─────────────────────────────────────────────────────────────
    devMode = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Run in localhost development mode over plain HTTP on port 3340.
        This overrides TLS settings and is intended for local testing only.
      '';
    };

    # ── Firewall ─────────────────────────────────────────────────────────────
    openFirewall = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Open the firewall for the relay HTTP port (80), HTTPS port (443) and
        QUIC port (7842). Adjust if you have customised the bind addresses.
      '';
    };

    # ── systemd tweaks ───────────────────────────────────────────────────────
    extraArgs = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--dev" ];
      description = "Extra command-line arguments passed to iroh-relay.";
    };

    environmentFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing environment variables (one KEY=value per line).
        Useful for supplying secrets such as bearer tokens without putting them
        in the Nix store.
      '';
    };
  };

  # ────────────────────────────────────────────────────────────────────────────
  # Implementation
  # ────────────────────────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {

    # Remove null-valued fields from the settings attrset before serialising,
    # so optional keys are simply omitted rather than written as null.
    _module.args.iroh-relay-configFile =
      let
        cleanSettings = lib.filterAttrs (_k: v: v != null) cfg.settings;
        generated     = settingsFormat.generate "iroh-relay.toml" cleanSettings;
      in
      if cfg.configFile != null then cfg.configFile else generated;

    # ── User / group ─────────────────────────────────────────────────────────
    users.users.iroh-relay = {
      isSystemUser = true;
      group        = "iroh-relay";
      description  = "iroh-relay service user";
      home         = "/var/lib/iroh-relay";
    };
    users.groups.iroh-relay = { };

    # ── Firewall ─────────────────────────────────────────────────────────────
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 7842 ];
    };

    # ── systemd service ───────────────────────────────────────────────────────
    systemd.services.iroh-relay = {
      description = "iroh-relay server";
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Type             = "simple";
        User             = "iroh-relay";
        Group            = "iroh-relay";
        StateDirectory   = "iroh-relay";
        WorkingDirectory = "/var/lib/iroh-relay";
        Restart          = "on-failure";
        RestartSec       = "5s";

        ExecStart =
          let
            configFlag =
              if cfg.configFile != null
              then "--config-path ${cfg.configFile}"
              else "--config-path ${
                let
                  cleanSettings = lib.filterAttrs (_k: v: v != null) cfg.settings;
                in
                settingsFormat.generate "iroh-relay.toml" cleanSettings
              }";
            devFlag   = lib.optionalString cfg.devMode "--dev";
            extraArgs = lib.escapeShellArgs cfg.extraArgs;
          in
          "${cfg.package}/bin/iroh-relay ${configFlag} ${devFlag} ${extraArgs}";

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null)
          (toString cfg.environmentFile);

        # Hardening
        NoNewPrivileges      = true;
        PrivateTmp           = true;
        ProtectSystem        = "strict";
        ProtectHome          = true;
        ReadWritePaths       = [ "/var/lib/iroh-relay" ];
        CapabilityBoundingSet = lib.mkIf (!cfg.devMode) "CAP_NET_BIND_SERVICE";
        AmbientCapabilities  = lib.mkIf (!cfg.devMode) "CAP_NET_BIND_SERVICE";
      };
    };
  };
}
