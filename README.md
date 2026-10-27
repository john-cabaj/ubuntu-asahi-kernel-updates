# Ubuntu Asahi Kernel Updates

This project will provide tooling to create Ubuntu kernel trees carrying the
upstream Asahi Linux patch set. Its first component detects Fedora Asahi
releases, which are the gate for considering an Ubuntu update.

## Project Layout

The implementation is `bin/asahi-tag-check` (bash), with tests in `tests/`.
Mutable operational state is stored in `.state/`, which Git ignores.

## Fedora Asahi Tag Check

`asahi-tag-check` uses `git ls-remote --tags` against Fedora
Asahi's repository. It does not create or maintain a local clone. It recognizes
only release tags named `asahi-X.Y.Z-N`; it ignores mainline `v*` tags and
Fedora `kernel-*` build tags.

Run it from a persistent working directory:

```sh
bin/asahi-tag-check
```

For each Fedora release it also reports the matching `AsahiLinux/linux` tag
(`asahi-tag: ...`), found by comparing the commits the tags point to. That tag
is the one to build from, and it is reported only for tags Fedora has actually
published. If Asahi has no tag at Fedora's commit, the run exits `1` and the
stored tag is not advanced, so the release is retried next run.

The first successful run creates `.state/fedora-asahi-tag-check` and reports the
baseline. A later run returns exit status `10` and prints `updated: OLD -> NEW`
plus the `asahi-tag:` line when Fedora has published a newer Asahi release. It returns `0` while current
and `1` for Git transport, response, or state errors. On a detected update it advances
the stored tag, so notification automation should treat exit status `10` as a
successful alert rather than a failure.

Use `--state-file PATH` to keep state outside the working directory, or
`--reset` to deliberately replace the baseline without producing an alert.

```sh
tests/test_asahi_tag_check.sh
```
