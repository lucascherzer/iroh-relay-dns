"""
Smoke test helper for the iroh-dns-server NixOS module VM test.

Imported inline by smoke-test-iroh-dns-server.nix via builtins.readFile,
so all code lives at module level and main(machine) is the entry point.

Test config uses:
  HTTP  → port 8080
  DNS   → port 5353  (unprivileged, avoids conflicting with systemd-resolved)
"""


def main(machine):
    print("=" * 60)
    print("IROH-DNS-SERVER MODULE SMOKE TEST")
    print("=" * 60)

    # 1 – binary is present
    machine.succeed("test -x $(which iroh-dns-server)")
    print("OK  iroh-dns-server binary found in PATH")

    # 2 – systemd unit is active
    machine.wait_for_unit("iroh-dns-server.service")
    print("OK  iroh-dns-server.service is active")

    # 3 – process is running
    machine.succeed("pgrep -f iroh-dns-server")
    print("OK  iroh-dns-server process running")

    # 4 – HTTP port 8080 is listening
    machine.wait_until_succeeds("ss -tuln | grep -q ':8080'", timeout=30)
    print("OK  port 8080 (HTTP) is listening")

    # 5 – DNS port 5353 is listening
    machine.wait_until_succeeds("ss -tuln | grep -q ':5353'", timeout=30)
    print("OK  port 5353 (DNS) is listening")

    # 6 – HTTP endpoint responds (pkarr PUT endpoint or root)
    machine.wait_until_succeeds(
        "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ "
        "| grep -qE '^(200|404|405)'",
        timeout=30,
    )
    print("OK  HTTP endpoint responds on port 8080")

    # 7 – DNS responds to queries (SOA for '.' zone)
    machine.wait_until_succeeds(
        "dig @127.0.0.1 -p 5353 . SOA +short +time=2 +tries=1",
        timeout=30,
    )
    print("OK  DNS server responds to SOA query on port 5353")

    # 8 – ExecStart contains --config flag (validates configFile wiring)
    machine.succeed(
        "systemctl show iroh-dns-server.service --property=ExecStart "
        "| grep -q -- '--config'"
    )
    print("OK  ExecStart contains --config flag")

    # 9 – service survives a restart
    machine.succeed("systemctl restart iroh-dns-server.service")
    machine.wait_for_unit("iroh-dns-server.service")
    machine.wait_until_succeeds("ss -tuln | grep -q ':8080'", timeout=30)
    machine.wait_until_succeeds("ss -tuln | grep -q ':5353'", timeout=30)
    print("OK  service restarted and ports are listening again")

    # 10 – logs are accessible
    machine.succeed("journalctl -u iroh-dns-server.service -n 5 --no-pager")
    print("OK  service logs accessible via journalctl")

    print("=" * 60)
    print("ALL iroh-dns-server smoke tests passed")
    print("=" * 60)
