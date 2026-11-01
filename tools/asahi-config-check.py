#!/usr/bin/env python3
"""Check Ubuntu's Asahi config annotations against Fedora Asahi's configs.

Fedora Asahi keeps its config as one file per option under redhat/configs/ (layered, see
FEDORA_ORDER). Its releases come in pairs per kernel version: kernel-X.Y.Z-0 (plain ARK) and
kernel-X.Y.Z-N.asahi (ARK plus the Asahi config commits). The Asahi layer is the set of options
whose files differ between the two. Ubuntu mirrors that layer by hand in
debian.asahi-arm/config/annotations, section "Asahi enablement config":

    CONFIG_X                                        policy<{'arm64': 'm'}>
    CONFIG_X                                        note<'{Asahi enablement config}'>

Run it after the Asahi stack is on top of the tree: the drivers (and so the Kconfig symbols)
arrive with the stack, and the symbols present in the tree decide what applies.

Usage: asahi-config-check.py --fedora DIR [--release TAG] [--repo DIR] [--ubuntu REF]
                             [--apply [--apply-updates]] [--commit] [--check] [--all]
  --fedora DIR     clone of fedora-asahi/kernel-asahi holding both kernel-* release tags and
                   their history (see the asahi-crank skill for a cheap blobless clone)
  --release TAG    Fedora Asahi release (default: newest kernel-*.asahi tag in DIR)
  --repo DIR       Ubuntu Asahi git repo (default .); --ubuntu REF is the commit/branch, with
                   the Asahi stack applied, whose annotations and Kconfig symbols are used
                   (default HEAD). Options whose symbol is absent are "notree", never applied
  --apply          write the missing ("add") entries into DIR's annotations file (no commit)
  --commit         with --apply: commit the written entries on top of the tree as
                   "UBUNTU: [Config] asahi-arm: Enable ..." (signed off with the git identity).
                   Config enablement commits go above the Asahi stack, before the marker
  --apply-updates  also overwrite differing policies. Off by default: a difference may be a
                   deliberate Ubuntu choice (e.g. DRM_NOVA), so that is the user's decision
  --check          exit 1 if anything needs action
  --all            also print options that already match

Statuses: ok (Ubuntu matches), add (Fedora y/m, Ubuntu has no arm64 policy), differs (Ubuntu
has another policy), review (Fedora n/number/string and Ubuntu has no policy: a Fedora distro
choice, not copied), notree (symbol not in the tree being ported), removed (no longer set in
the Fedora release).
"""
import argparse
import ast
import re
import subprocess
import sys

UBUNTU_ANN = "debian.asahi-arm/config/annotations"
MASTER_ANN = "debian.master/config/annotations"
ENABLE_NOTE = "'{Asahi enablement config}'"
NOTES_MARKER = "# ---- Annotations without notes ----"
NAME_WIDTH = 48          # annotations pad the option name to this column
# Fedora layering for the aarch64 (non-debug) kernel, lowest priority last: redhat/configs/
# priority.fedora gives the directory order, config_layout the arch order inside each.
FEDORA_ORDER = ["custom-overrides", "pending-fedora", "fedora", "common"]
FEDORA_SUB = ["generic/arm/aarch64", "generic/arm", "generic"]
FEDORA_PATHS = [f"redhat/configs/{o}/{s}" for o in FEDORA_ORDER for s in FEDORA_SUB]

SET = re.compile(r"^(CONFIG_\w+)=(.*)$")
POLICY = re.compile(r"^(CONFIG_\w+)\s+policy<(\{.*\})>\s*$")
NOTE = re.compile(r"^(CONFIG_\w+)\s+note<.*>\s*$")


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def newest_asahi_release(fed):
    """Newest kernel-X.Y.Z-N.asahi tag by numeric version."""
    tags = git(fed, "tag", "-l", "kernel-*.asahi").stdout.split()
    key = lambda t: tuple(int(x) for x in re.findall(r"\d+", t))
    return max(tags, key=key) if tags else None


def base_release(tag):
    """kernel-7.2.12-400.asahi -> kernel-7.2.12-0 (the plain ARK release of the same version)."""
    m = re.match(r"kernel-(\d+(?:\.\d+)+)-\d+\.asahi$", tag)
    return f"kernel-{m.group(1)}-0" if m else None


def asahi_layer(fed, base, release):
    """Option names whose Fedora config files differ between the ARK release and the Asahi one."""
    out = git(fed, "diff", "--name-only", base, release, "--", "redhat/configs").stdout.split()
    return sorted({p.rsplit("/", 1)[-1] for p in out if "/CONFIG_" in p})


def fedora_line(fed, ref, opt):
    """First line of the effective Fedora file for opt at ref (highest layer wins), or None."""
    for p in FEDORA_PATHS:
        r = git(fed, "show", f"{ref}:{p}/{opt}")
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip().splitlines()[0]
    return None


def fedora_policy(line):
    """Fedora config line -> annotation policy value: y/m/n, a number, or the raw string."""
    if line is None:
        return None
    m = SET.match(line)
    if m:
        return m.group(2)
    return "n" if line.startswith("# CONFIG_") else line


def kconfig_symbols(repo, ref):
    """CONFIG_ names of every Kconfig symbol defined in the tree at ref."""
    r = git(repo, "grep", "-hoE", r"^[ \t]*(menu)?config [A-Z0-9_]+", ref, "--", "*Kconfig*")
    return {"CONFIG_" + l.split()[-1] for l in r.stdout.splitlines()}


def arm64_policies(text):
    """annotations text -> {option: arm64 policy} (later lines win)."""
    out = {}
    for line in text.splitlines():
        m = POLICY.match(line)
        if m:
            try:
                out[m.group(1)] = ast.literal_eval(m.group(2)).get("arm64")
            except (ValueError, SyntaxError):
                pass
    return out


def classify(options, fedora_vals, ubuntu, symbols):
    """-> [(option, fedora value, ubuntu policy, status)]."""
    rows = []
    for opt in options:
        fv, have = fedora_vals[opt], ubuntu.get(opt)
        if fv is None:
            status = "removed"
        elif opt not in symbols:
            status = "notree"
        elif have == fv:
            status = "ok"
        elif have is not None:
            status = "differs"
        else:
            status = "add" if fv in ("y", "m") else "review"
        rows.append((opt, fv, have, status))
    return rows


def split_sections(lines):
    """Index range [start, end) of the Asahi enablement section: after the include line, up to
    the 'Annotations without notes' marker (or end of file)."""
    start = next((i + 1 for i, l in enumerate(lines) if l.startswith("include ")), 0)
    end = next((i for i, l in enumerate(lines) if l.strip() == NOTES_MARKER), len(lines))
    return start, end


def apply_changes(path, rows, updates=False):
    """Write add (and, if updates, differs) rows into the annotations file. Returns options changed."""
    lines = open(path).read().split("\n")
    done = []
    for opt, new, _have, status in rows:
        if status != "add" and not (updates and status == "differs"):
            continue
        idx = next((i for i, l in enumerate(lines) if POLICY.match(l) and l.split()[0] == opt), None)
        if idx is not None:                       # already annotated: change its arm64 policy
            if "'arm64'" not in lines[idx]:
                continue
            lines[idx] = re.sub(r"'arm64': '[^']*'", f"'arm64': '{new}'", lines[idx])
            if not any(NOTE.match(l) and l.split()[0] == opt for l in lines):
                lines.insert(idx + 1, f"{opt:<{NAME_WIDTH}}note<{ENABLE_NOTE}>")
        else:                                     # new entry in the enablement section, sorted
            block = [f"{opt:<{NAME_WIDTH}}policy<{{'arm64': '{new}'}}>",
                     f"{opt:<{NAME_WIDTH}}note<{ENABLE_NOTE}>", ""]
            start, end = split_sections(lines)
            pos = end
            for i in range(start, end):
                m = POLICY.match(lines[i])
                if m and m.group(1) > opt:
                    pos = i
                    break
            lines[pos:pos] = block
        done.append(opt)
    open(path, "w").write("\n".join(lines))
    return done


def commit_entries(repo, release, rows, done):
    """Commit the annotations file with the standard enablement message."""
    vals = {r[0]: r[1] for r in rows}
    body = "\n".join(f"  {o} ({vals[o]})" for o in done)
    msg = (f"UBUNTU: [Config] asahi-arm: Enable Asahi options from Fedora {release}\n\n"
           f"Mirror the Asahi enablement configs that Fedora Asahi ({release}) sets and\n"
           f"Ubuntu did not yet annotate:\n{body}\n")
    git(repo, "add", UBUNTU_ANN)
    r = git(repo, "commit", "-q", "-s", "-m", msg)
    if r.returncode:
        sys.exit(f"commit failed: {r.stderr.strip()}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fedora", required=True)
    ap.add_argument("--release")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--ubuntu", default="HEAD")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--apply-updates", action="store_true")
    ap.add_argument("--commit", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()

    release = a.release or newest_asahi_release(a.fedora)
    if not release:
        sys.exit("no kernel-*.asahi tag in the Fedora clone (git fetch --tags)")
    base = base_release(release)
    if not base or git(a.fedora, "rev-parse", "-q", "--verify", f"{base}^{{commit}}").returncode:
        sys.exit(f"cannot find the ARK base release {base} for {release} in the Fedora clone")

    ann = git(a.repo, "show", f"{a.ubuntu}:{UBUNTU_ANN}").stdout
    if not ann:
        sys.exit(f"{UBUNTU_ANN} not found at {a.ubuntu}")
    ubuntu = arm64_policies(git(a.repo, "show", f"{a.ubuntu}:{MASTER_ANN}").stdout)
    ubuntu.update(arm64_policies(ann))
    symbols = kconfig_symbols(a.repo, a.ubuntu)

    options = asahi_layer(a.fedora, base, release)
    vals = {o: fedora_policy(fedora_line(a.fedora, release, o)) for o in options}
    rows = classify(options, vals, ubuntu, symbols)

    if rows and sum(1 for r in rows if r[3] == "notree") * 2 > len(rows):
        print("warning: most options are not in the tree; is the Asahi stack applied on top of it?")
    for opt, fv, have, status in rows:
        if a.all or status != "ok":
            print(f"{opt:<42} fedora {str(fv):<6} ubuntu {str(have or 'unset'):<6} => {status}")
    counts = {s: sum(1 for r in rows if r[3] == s) for s in ("ok", "add", "differs", "review", "notree", "removed")}
    print(f"{release} vs {base}: {len(rows)} Asahi options; " +
          ", ".join(f"{n} {s}" for s, n in counts.items() if n) + f" (ubuntu {a.ubuntu})")
    if a.apply:
        done = apply_changes(f"{a.repo}/{UBUNTU_ANN}", [(o, f, h, s) for o, f, h, s in rows], a.apply_updates)
        committed = a.commit and done
        if committed:
            commit_entries(a.repo, release, rows, done)
        print(f"applied to {UBUNTU_ANN}: {', '.join(done) or 'nothing'} "
              f"({'committed' if committed else 'uncommitted'})")
    if a.check and any(counts[s] for s in ("add", "differs", "review")):
        sys.exit(1)


if __name__ == "__main__":
    main()
