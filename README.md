# _plugins

Release hub for Dichotic Studios plugins. This repo is for robots.

One pipeline builds, signs, notarizes, packages and ships every plugin. Secrets live
here and nowhere else. Each plugin is a submodule plus one entry in `plugins.json`.

Public on purpose, and safe: secrets are Actions secrets, not files. Plugin source stays
private (submodules store URLs and commit pointers, not code). No build is ever a public
artifact; everything goes to R2 and is served through the CDN.

## Releasing

Tag the plugin repo:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Pushing to a plugin's `main` runs a dry-run instead: builds all three platforms, ships
nothing. That keeps `main` known-green so tagging is safe.

A publish run builds macOS (signed, notarized), Windows and Linux, stages each to R2, and
only if all three pass: promotes to the live CDN keys, cuts the GitHub release on the
plugin repo, and pushes the changelog + update manifest to dichoticstudios.com. One failed
platform ships nothing.

Drive it directly if you need to:

```bash
make release PLUGIN=pewpew VERSION=0.2.0
gh workflow run release.yml -f plugin=pewpew -f dry_run=true
gh run watch --exit-status $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Adding a plugin

```bash
make add-plugin NAME=foo REPO=noahbaxter/foo
```

Then set `target` and `productName` from the plugin's `CMakeLists.txt`, add `foo` to the
`plugin:` list in `release.yml`, give the plugin repo a `CHANGELOG.md`, push the scaffolded
`release-dispatch.yml`, set its `HUB_DISPATCH_TOKEN`, and add the repo to
`PLUGINS_CI_TOKEN`'s access list.

### `plugins.json`

| field | meaning |
|-------|---------|
| `repo` | `owner/repo` of the plugin |
| `branch` | branch the hub tracks and releases from |
| `target` | CMake target. Names the `build/<target>_artefacts/Release/` dir |
| `productName` | bundle basename, may differ from target (`Guillotine Clip` vs `Guillotine`) |
| `bundleId` | `com.dichoticstudios.<x>`, the pkg identifier |
| `gated` | `true` for paid: release gets notes only, no binaries attached |
| `r2Bucket` | R2 bucket, shared. Builds land under a `<plugin>/` prefix |
| `cdnBaseUrl` | public CDN base for this plugin |
| `windowsInstaller` | path to the Inno `.iss` inside the plugin |
| `downloadBaseUrl` | the `url` written into the update manifest |
| `manifestPath` | path in the site repo, e.g. `static/updates/pewpew.json` |
| `webBuild` | `null`, or `{ "dir": "web", "usesWebplugUi": true }` |

`usesWebplugUi` gates the private-dependency auth. Only plugins pulling `webplug-ui` need
the git URL rewrite before `bun install`.

## Projects that build themselves

Some projects (stemchotic) already build, sign and release their own artifacts and only
need the tail: promote to the CDN, push changelog + manifest to the site. Those live in
`external.json` and run through `publish-external.yml`, which takes an existing GitHub
release instead of building anything. A daily poll picks up new releases, so those repos
hold no secrets and trigger nothing.

Backfilling an old version through it would overwrite the `latest` CDN keys. Don't.

## Secrets

`make secrets` sets everything from a local `.secrets.env` (gitignored, copy the example).
Rotating a key: regenerate at the source, run it again.

| secret | used by |
|--------|---------|
| `PLUGINS_CI_TOKEN` | setup, checkout-plugin, build-web, publish (cut release, read CHANGELOG) |
| `APPLE_*` (6) | build-macos, sign + notarize. Skipped on dry-run |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | build (stage), publish (promote), cleanup (wipe) |
| `SITE_DEPLOY_SSH_KEY` | publish, commits changelog + manifest to the site repo |

Provenance:

- **Apple (6)**: `[redacted]` sets all six.
  Certs in `[redacted]`, password in [redacted], Team ID `KUP5WU7WPC`.
- **R2 (2)**: Cloudflare dashboard, R2, Manage R2 API Tokens. Object Read & Write. One token
  across all buckets is fine.
- **`PLUGINS_CI_TOKEN`**: fine-grained PAT, Contents read/write AND Actions read/write. You
  MUST explicitly list every plugin repo plus `webplug-ui` plus `_plugins` under Repository
  access. Set the same string as `HUB_DISPATCH_TOKEN` on each plugin repo.
- **`SITE_DEPLOY_SSH_KEY`**: private half of a write deploy key on `dichoticstudios.com`.

## Layout

```
plugins.json                 source of truth, one entry per plugin
external.json                projects that build themselves
Makefile                     help / add-plugin / update / release / secrets / list
scripts/                     add-plugin, release, update-plugins, secrets-sync, changelog-entry
plugins/<name>/              each plugin as a submodule
.github/workflows/           release.yml, publish-external.yml, test.yml
.github/actions/             checkout-plugin, build-web
```

## Gotchas

- **"Repository not found" but the API read worked.** A fine-grained PAT rejects the
  `https://x-access-token:<token>@` git URL; that form is GitHub App tokens only. Both
  composite actions use `gh auth setup-git` now. The token is fine, the auth format wasn't.
- **"Repository not found" and the API read also failed.** That one is scope. Add the repo
  to `PLUGINS_CI_TOKEN`'s Repository access.
- **Notarization hangs or fails.** `notarytool --wait` blocks until Apple answers. A
  rejection prints a submission id: `xcrun notarytool log <id> --keychain-profile
  notarytool-profile`. Usually an unsigned nested binary or missing hardened runtime.
- **Wrong artefact path.** `target` names the `_artefacts` dir, `productName` names the
  bundle inside it. Guillotine is where they differ.
- **CDN serves stale after a release.** `max-age=14400`, so downloads can be 4 hours behind.

## Known limitations

- Windows is unsigned, so SmartScreen warns. There's a marked TODO in `build-windows` where
  Authenticode signing goes.
- `gated` is a soft gate, not encryption. Binaries sit at stable, guessable CDN URLs; the
  gate is only that they're not attached to the public release. Before pewpew is actually
  paid, harden three things together: real download gating (signed or expiring URLs, noting
  the publish window briefly exposes `_staging/<run_id>/` too), split `PLUGINS_CI_TOKEN`
  into read and write halves so nothing write-capable sits in a `bun install` env, and
  Authenticode-sign Windows.
- Dry-run signs but skips notarization, so a notary rejection only surfaces on the real run.
  It still fails atomically, you just lose the build time.
- The `workflow_dispatch` plugin list in `release.yml` is hand-synced with `plugins.json`.
  Missing entries only affect the Actions UI picker.
- `choco install innosetup` is unpinned.
- pewpew's `beta.releases` block on the site is hand-maintained and can go stale.

## Migrating a plugin off self-release

Once the hub builds it green: add `release-dispatch.yml` and its `HUB_DISPATCH_TOKEN`,
remove the repo's own `v*` trigger and package/release jobs (keep its PR checks), and make
sure it has a `CHANGELOG.md`. Leave `VERSION`, `CMakeLists.txt` and installer configs alone,
the hub reads them as-is. One clean commit per plugin.
