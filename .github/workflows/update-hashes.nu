#!/usr/bin/env nu
# update-hashes.nu
#
# Checks for a new iroh release on GitHub. If a newer version is found,
# downloads every release tarball, computes its nix SRI sha256 hash and
# writes the results to hashes.json and patches flake.nix.
#
# Usage:
#   nu .github/workflows/update-hashes.nu
#   nu .github/workflows/update-hashes.nu --force   # re-hash even if version unchanged

def main [
    --force (-f)  # re-download and re-hash even if the version hasn't changed
    --dry-run     # print what would change without writing files
] {
    # ── Configuration ────────────────────────────────────────────────────────
    let repo         = "n0-computer/iroh"
    let pnames       = ["iroh-relay" "iroh-dns-server"]
    let systems: record<
        x86_64-linux:   string,
        aarch64-linux:  string,
        x86_64-darwin:  string,
        aarch64-darwin: string
    > = {
        "x86_64-linux":   "x86_64-unknown-linux-musl"
        "aarch64-linux":  "aarch64-unknown-linux-musl"
        "x86_64-darwin":  "x86_64-apple-darwin"
        "aarch64-darwin": "aarch64-apple-darwin"
    }

    # ── Read current state ───────────────────────────────────────────────────
    let hashes_path = "hashes.json"
    let flake_path  = "flake.nix"

    let current = open $hashes_path
    let current_version = $current.version

    # ── Fetch latest release ─────────────────────────────────────────────────
    print $"Fetching latest release from github.com/($repo) …"
    let release = (
        http get $"https://api.github.com/repos/($repo)/releases/latest"
            --headers { "User-Agent": "iroh-relay-dns-updater" }
    )
    let tag     = $release.tag_name                    # e.g. "v0.97.0"
    let version = ($tag | str replace --regex '^v' '') # e.g. "0.97.0"

    print $"Latest release : ($tag)"
    print $"Current version: ($current_version)"

    if ($version == $current_version) and (not $force) {
        print "Already up to date – nothing to do."
        return
    }

    # ── Hash each tarball ────────────────────────────────────────────────────
    print $"\nComputing hashes for v($version) …"

    # Build a nested record  pname -> system -> sri_hash
    mut new_hashes: record = {}

    for pname in $pnames {
        mut pname_hashes: record = {}
        for sys in ($systems | columns) {
            let target  = ($systems | get $sys)
            let filename = $"($pname)-v($version)-($target).tar.gz"
            let url      = $"https://github.com/($repo)/releases/download/($tag)/($filename)"

            print $"  ($pname) / ($sys) – ($url)"

            # nix hash convert expects a hex hash via stdin; nix store prefetch-file
            # gives us a SRI hash directly.
            let result = (
                nix store prefetch-file
                    --hash-type sha256
                    --json
                    $url
                | from json
            )
            let sri = $result.hash

            print $"    -> ($sri)"
            $pname_hashes = ($pname_hashes | insert $sys $sri)
        }
        $new_hashes = ($new_hashes | insert $pname $pname_hashes)
    }

    # Add version key
    let output = ($new_hashes | insert version $version)

    # ── Diff summary ─────────────────────────────────────────────────────────
    print "\nHash diff:"
    for pname in $pnames {
        for sys in ($systems | columns) {
            let old_hash = (try { $current | get $pname | get $sys } catch { "(none)" })
            let new_hash = ($output | get $pname | get $sys)
            if $old_hash != $new_hash {
                print $"  ($pname)/($sys)"
                print $"    old: ($old_hash)"
                print $"    new: ($new_hash)"
            }
        }
    }

    if $dry_run {
        print "\n--dry-run: not writing any files."
        return
    }

    # ── Write hashes.json ────────────────────────────────────────────────────
    $output | to json --indent 2 | save --force $hashes_path
    print $"\nWrote ($hashes_path)"

    # ── Patch version in flake.nix ────────────────────────────────────────────
    let flake_content = open --raw $flake_path
    let patched = (
        $flake_content
        | str replace
            $"version = \"($current_version)\";"
            $"version = \"($version)\";"
    )
    $patched | save --force $flake_path
    print $"Patched ($flake_path): ($current_version) → ($version)"

    print "\nDone."
}
