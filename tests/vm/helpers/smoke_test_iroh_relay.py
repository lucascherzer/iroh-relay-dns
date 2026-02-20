"""
Smoke test helper for the iroh-relay NixOS module VM test.

Imported inline by smoke-test-iroh-relay.nix via builtins.readFile,
so all code lives at module level and main(machine) is the entry point.
"""


def main(machine):
    print("=" * 60)
    print("IROH-RELAY MODULE SMOKE TEST")
    print("=" * 60)

    # 1 – binary is present
    machine.succeed("test -x $(which iroh-relay)")
    print("OK  iroh-relay binary found in PATH")

    # 2 – systemd unit is active
    machine.wait_for_unit("iroh-relay.service")
    print("OK  iroh-relay.service is active")

    # 3 – process is running
    machine.succeed("pgrep -f iroh-relay")
    print("OK  iroh-relay process running")

    # 4 – port 3340 is listening (dev mode default)
    machine.wait_until_succeeds("ss -tuln | grep -q ':3340'", timeout=30)
    print("OK  port 3340 is listening")

    # 5 – HTTP /healthz endpoint responds (iroh-relay uses /healthz, not /health)
    machine.wait_until_succeeds(
        "curl -sf http://127.0.0.1:3340/healthz", timeout=30
    )
    print("OK  /healthz endpoint responds on port 3340")

    # 6 – ExecStart contains --dev flag (validates devMode option wiring)
    machine.succeed(
        "systemctl show iroh-relay.service --property=ExecStart "
        "| grep -q -- '--dev'"
    )
    print("OK  ExecStart contains --dev flag")

    # 7 – ExecStart contains --config-path (validates configFile wiring)
    machine.succeed(
        "systemctl show iroh-relay.service --property=ExecStart "
        "| grep -q -- '--config-path'"
    )
    print("OK  ExecStart contains --config-path flag")

    # 8 – service survives a restart
    machine.succeed("systemctl restart iroh-relay.service")
    machine.wait_for_unit("iroh-relay.service")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:3340/healthz", timeout=30)
    print("OK  service restarted and is healthy again")

    # 9 – logs are accessible
    machine.succeed("journalctl -u iroh-relay.service -n 5 --no-pager")
    print("OK  service logs accessible via journalctl")

    print("=" * 60)
    print("ALL iroh-relay smoke tests passed")
    print("=" * 60)
