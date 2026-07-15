# _plugins — Dichotic Studios release hub

Public meta-repo (public for free Actions runners) that owns CI/CD for every Dichotic
Studios audio plugin: build, sign, notarize, package, and upload to R2, then publish the
in-app update manifest. Secrets and the pipeline live **once, here**. Each plugin is a git
submodule and one entry in `plugins.json`. No GitHub org.

It is safe to be public: Actions secrets are never exposed by a public repo, and the pipeline
**never produces a public build artifact** (no `upload-artifact`) — every build goes to R2,
served only through the gated CDN (`cdn.dichoticstudios.com`). On a real publish the hub also
cuts the GitHub release **on the plugin repo** and publishes the plugin's changelog + update
manifest to the site. For a paid (`gated`) plugin the release carries notes only — no public
binaries — so downloads stay CDN-gated.

**Two modes, one workflow** (see `release.yml`):
- **dry-run** — build + package on all three platforms, publish nothing. Fired by a push to a
  plugin repo's `main` (its `release-dispatch.yml`). The continuous "does it still build" signal.
- **publish** — build (signed + notarized on mac) → and only if **all three** platforms pass:
  promote to the live CDN keys, cut the GitHub release, publish changelog + manifest to the
  site. Fired by tagging the plugin repo (`git tag vX.Y.Z && git push`). Atomic: one failed
  platform publishes nothing.

Adding a new plugin is: `make add-plugin`, fill a few `plugins.json` fields, done.

## Why this exists

Every plugin repo used to re-implement the same ~700-line release workflow and re-enter the
same ~9 secrets. That per-plugin toil is what this kills. One generic, manifest-driven
pipeline builds any plugin; the plugin repos keep only their own cheap PR checks.

## Layout

```
_plugins/
  plugins.json                 # source of truth: one entry per plugin
  Makefile                     # make help / add-plugin / update / release / secrets / list
  scripts/                     # add-plugin, release, update-plugins, secrets-sync, changelog-entry, lib
  plugins/<name>/              # each plugin as a submodule (tracks its main branch)
  .github/
    workflows/release.yml      # the generic pipeline (dry-run on push, publish on tag)
    workflows/test.yml         # cheap PR check: validate manifest + shellcheck
    actions/checkout-plugin/   # composite: clone plugin at latest branch (private auth + LFS)
    actions/build-web/         # composite: bun build, with webplug-ui auth when needed
  .secrets.env.example         # documents every secret; real .secrets.env is gitignored
```

### `plugins.json` fields

| field | meaning |
|-------|---------|
| `repo` | `owner/repo` of the plugin |
| `branch` | branch the hub tracks and releases from (usually `main`) |
| `target` | CMake target name — artefacts land in `build/<target>_artefacts/Release/` |
| `productName` | bundle basename, may differ from target (e.g. `Guillotine Clip` vs target `Guillotine`) |
| `bundleId` | `com.dichoticstudios.<x>`, used for the pkg identifier |
| `gated` | `true` for paid plugins: the GitHub release gets notes only (no public binaries); downloads stay CDN-gated. Omit/`false` = public release with binaries attached |
| `r2Bucket` | shared Cloudflare R2 bucket (`dichotic-plugins`); builds upload under a `<plugin>/` key prefix |
| `cdnBaseUrl` | public CDN base for this plugin's files, e.g. `https://cdn.dichoticstudios.com/pewpew` |
| `windowsInstaller` | path to the Inno `.iss` inside the plugin (pewpew: `scripts/installer/windows/…`, guillotine: `installer/windows/…`) |
| `downloadBaseUrl` | the `url` written into the update manifest (where users download) |
| `manifestPath` | path in the site repo, e.g. `static/updates/pewpew.json` |
| `webBuild` | `null` for no web build, or `{ "dir": "web", "usesWebplugUi": true }` |

`webBuild.usesWebplugUi` gates the private-dependency auth: only plugins that pull the
private `webplug-ui` package need the git URL rewrite before `bun install`.

## One-time setup

1. **Create the repo** (already done; public for free runners):
   ```bash
   gh repo create noahbaxter/_plugins --public --source . --remote origin --push
   ```

2. **Add plugins** (already done for pewpew + guillotine):
   ```bash
   make add-plugin NAME=pewpew REPO=noahbaxter/pewpew
   make add-plugin NAME=guillotine REPO=noahbaxter/guillotine
   ```
   Then fill each new entry's `target` / `productName` / `webBuild` by reading the plugin's
   `CMakeLists.txt`, and add the name to the `plugin:` choice list in `release.yml`.

3. **Set secrets.** Copy `.secrets.env.example` to `.secrets.env`, fill it in, then:
   ```bash
   make secrets
   ```
   Provenance for each:
   - **Apple signing (6)** — easiest is Noah's helper, which sets all six directly:
     `~/.claude/scripts/setup-apple-signing.sh noahbaxter/_plugins` (certs from
     `~/.claude/secrets/`, password in Bitwarden "Apple Signing", Team ID `KUP5WU7WPC`).
     If you use the helper, leave the `APPLE_*` values blank in `.secrets.env`.
   - **R2 (2)** — Cloudflare dashboard → R2 → Manage R2 API Tokens → token with Object
     Read & Write on the plugin buckets. One token spanning all buckets is fine.
   - **`PLUGINS_CI_TOKEN` (1)** — one fine-grained PAT
     (github.com/settings/tokens?type=beta), **Contents: read/write AND Actions: read/write**.
     Under **Repository access you MUST explicitly select every plugin repo AND `webplug-ui`
     AND `_plugins`.** Fine-grained tokens default to public repos only; a missing repo shows
     up as a 404 "Repository not found", which reads like an auth error but is a scope error.
     Set the **same PAT string** as `HUB_DISPATCH_TOKEN` on each plugin repo so its
     `release-dispatch.yml` can fire this hub: `gh secret set HUB_DISPATCH_TOKEN -R noahbaxter/<plugin>`.
   - **`SITE_DEPLOY_SSH_KEY` (1)** — private half of a **write** SSH deploy key on
     `noahbaxter/dichoticstudios.com`. Publishes the changelog + update manifest. Generate with
     `ssh-keygen -t ed25519`, add the public key as a write deploy key on that repo
     (`gh repo deploy-key add … --allow-write`), store the private key here.

## Adding a new plugin

```bash
make add-plugin NAME=foo REPO=noahbaxter/foo
```

`add-plugin` also scaffolds `plugins/foo/.github/workflows/release-dispatch.yml`. Then:
1. Edit `plugins.json`: set `target` and `productName` from the plugin's `CMakeLists.txt`
   (`juce_add_plugin(<target> … PRODUCT_NAME "<product>")`), set `gated`, confirm
   `windowsInstaller`, and set `webBuild` (`null`, or `{dir, usesWebplugUi}`).
2. Add `foo` to the `plugin:` choice list in `.github/workflows/release.yml`.
3. Make sure the plugin repo has a `CHANGELOG.md` (the site changelog is generated from it).
4. Commit + push the scaffolded `release-dispatch.yml` to the plugin repo, and set its
   `HUB_DISPATCH_TOKEN` secret (same PAT as `PLUGINS_CI_TOKEN`).
5. Make sure `PLUGINS_CI_TOKEN`'s Repository access includes the new repo. That's it.

## Cutting a release

The normal path is from the **plugin repo**: keep pushing to `main` (each push runs a hub
dry-run so `main` stays known-green), then tag a commit you've watched pass:

```bash
# in the plugin repo:
git tag v0.2.0 && git push origin v0.2.0    # release-dispatch.yml fires the hub in publish mode
```

Or drive the hub directly:

```bash
make release PLUGIN=pewpew VERSION=0.2.0    # version blank -> the plugin's VERSION file
gh workflow run release.yml -f plugin=pewpew -f dry_run=true    # build-only test run
git tag pewpew-v0.2.0 && git push origin pewpew-v0.2.0          # hub-side tag fallback
```

What happens on a **publish** run (per selected plugin):

1. **setup** reads `plugins.json`; version falls back to the plugin's `VERSION` file.
2. Each build job checks out the plugin's **latest `branch` tip** (`--remote`) with private
   auth + LFS, runs the `bun` web build when `webBuild` is set, and builds:
   - **macOS** (universal, 10.15) → sign (Developer ID) → notarize (`notarytool --wait`) →
     staple → signed `.pkg`. A **dry-run still signs** (so cert/keychain rot is caught every
     push) but **skips the notarization wait**.
   - **Windows** (VS 2022 x64) → Inno Setup `.exe`. **Unsigned** today — see TODO below.
   - **Linux** (Ninja) → zips whatever formats built (VST3/LV2/CLAP/Standalone).
3. Each build **stages** its installer to a private per-run prefix `<plugin>/_staging/<run_id>/`
   in R2 (dry-run stages nothing). No `upload-artifact`, ever — hub run artifacts are public.
4. **publish** runs only if **all three** builds passed (and it's not a dry-run):
   - promotes the staged builds to the live keys — a versioned key (`<Target>-macOS-<version>.pkg`)
     and a stable "latest" key (`<Target>-macOS.pkg`, which downloads as the versioned name);
   - cuts the GitHub release **on the plugin repo** (`vX.Y.Z`), with notes from the plugin's
     `CHANGELOG.md`; attaches the binaries unless the plugin is `gated`;
   - generates `static/changelogs/<plugin>.json` (from `CHANGELOG.md`) and
     `static/updates/<plugin>.json` = `{ "version", "url" }`, commits both to
     `dichoticstudios.com` via the SSH deploy key; Cloudflare Pages auto-deploys.
5. **cleanup** always wipes this run's `_staging/<run_id>/` prefix.

Because `publish` `needs` all three build jobs, a single failed platform means nothing is
promoted, released, or published — the release is atomic.

Watch a run:
```bash
gh run watch --exit-status $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## How the update loop closes

Each plugin polls a compiled-in URL (pewpew: `https://dichoticstudios.com/updates/pewpew.json`).
Step 9 rewrites exactly that file with the new `version`, so releasing = telling installed
plugins an update exists. `manifestPath` in `plugins.json` **must** match the plugin's
compiled URL.

## Manual ops / debugging

- **Build without publishing**: a dispatch with `dry_run=true` (or any push to the plugin
  repo's `main`) builds + packages all three platforms and touches nothing — no CDN keys, no
  release, no site. This is the way to verify a build before tagging.
- **Re-run a failed job**: Actions UI → the run → "Re-run failed jobs".
- **One platform**: comment out the other `build-*` jobs' `needs` on `publish`, or use the
  plugin's own repo CI to iterate a single OS.
- **Logs**: GitHub Actions → the run. R2 uploads print the S3 keys; the manifest step prints
  the committed path + version.
- **Pin a submodule locally**: `make update` pulls all submodules to latest and shows moved
  pointers (releases don't need this — they use `--remote`).

## Troubleshooting

- **`git` says "Repository not found" but the token clearly works** (e.g. the API read of
  `VERSION` succeeded): a fine-grained PAT **rejects the `https://x-access-token:<token>@`
  git URL** — that form is only for GitHub App tokens like the built-in `GITHUB_TOKEN`. Both
  composite actions now use `gh auth setup-git`, which picks the right credential. If you see
  this, the token itself is fine; the auth *format* was wrong.
- **404 "Repository not found" AND the API read also fails**: that one really is scope —
  `PLUGINS_CI_TOKEN`'s **Repository access does not include that repo**. Add the repo (and
  `webplug-ui`) under the token's Repository access + Contents: Read, and re-run.
- **Windows installer unsigned → SmartScreen**: known gap. There's a clearly-marked TODO
  step in `release.yml` (`build-windows`) where Authenticode signing goes. To add it: get an
  EV/OV code-signing cert, store it as a secret, and `signtool sign /fd sha256 /tr <ts> …`
  the `.vst3` before Inno packaging (and optionally the `.exe` after).
- **macOS notarization hangs/fails**: `notarytool --wait` blocks until Apple responds; a
  rejection prints a submission id — `xcrun notarytool log <id> --keychain-profile
  notarytool-profile` shows why (usually an unsigned nested binary or missing hardened
  runtime). The keychain is created fresh per run in `$RUNNER_TEMP`.
- **Wrong artefact path**: `target` (not `productName`) names the `_artefacts` dir; the
  bundle inside uses `productName`. Guillotine is the example where they differ.

## Known limitations

- **Windows is unsigned** (SmartScreen warning). There's a marked TODO step in
  `build-windows` where Authenticode signing goes.
- **`gated` is a soft gate**, not encryption. A gated plugin's binaries still sit at stable,
  guessable CDN URLs; the "gate" is just that they're not attached to the public GitHub
  release. Fine for the open pewpew beta (its CDN URLs are plaintext by design).

  **When pewpew becomes an actually-paid product, harden three things together** (all are
  fine to leave as-is while it's a free beta):
  1. Gate downloads for real — signed/expiring URLs or a Worker auth check, not stable CDN
     keys (and note the publish window briefly exposes `<plugin>/_staging/<run_id>/` too).
  2. Split the tokens so nothing write-capable is reachable from a supply-chain compromise:
     a minimal **dispatch** PAT (Actions:write on `_plugins` only) for `HUB_DISPATCH_TOKEN`,
     and split `PLUGINS_CI_TOKEN` into a **read** token (checkout + the `bun install` that
     pulls webplug-ui) and a **write** token used only by the publish job's release-cut, so
     the write token never sits in a `bun install` env.
  3. Authenticode-sign Windows (see below).
- **Dry-run signs but skips notarization**, so cert/keychain problems are caught on every
  push, but an Apple *notary-service* rejection only surfaces on the real publish run. That
  still fails atomically (nothing ships), you just lose the build time and re-tag.
- **The `workflow_dispatch` plugin choice list** in `release.yml` must be kept in sync with
  `plugins.json` by hand (`add-plugin` reminds you). A missing entry just means you can't pick
  it from the Actions UI; the dispatch/tag paths still work.
- **`choco install innosetup` is unpinned** — it tracks the latest Inno Setup. Pin a version
  if a future release ever breaks the `.iss` compile.
- **pewpew's beta block** (`beta.releases` in the site's `plugins.json`) is hand-maintained —
  a hub publish updates the changelog + manifest but not that block, so the beta card's
  version/date can go stale until you edit it.

## Secrets → jobs

| secret | used by |
|--------|---------|
| `PLUGINS_CI_TOKEN` | setup (version read), checkout-plugin (private submodule), build-web (webplug-ui), publish (cut the plugin-repo release + read `CHANGELOG.md`). **Contents read/write.** Same PAT is `HUB_DISPATCH_TOKEN` on each plugin repo. |
| `APPLE_CERTIFICATE_APPLICATION` / `_INSTALLER` / `_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | build-macos (sign + notarize; skipped on dry-run) |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | build-* (stage), publish (promote), cleanup (wipe staging) |
| `SITE_DEPLOY_SSH_KEY` | publish (changelog + manifest commit to the site repo, via write SSH deploy key) |

## Migrating a plugin repo off self-release

Once the hub builds a plugin green, stop that repo from self-releasing:

1. Add `release-dispatch.yml` (push `main` → hub dry-run, tag `v*` → hub publish) and set its
   `HUB_DISPATCH_TOKEN` secret. `make add-plugin` scaffolds this for new plugins.
2. Remove the repo's own release machinery — the `v*` tag trigger and the tag-gated
   `package-*` / `release-*` jobs (and any R2 upload steps). Keep the cheap build + unit-test
   jobs so its own PRs still get validated.
3. Make sure the repo has a `CHANGELOG.md` — the hub generates the site changelog from it.

Leave `VERSION`, `CMakeLists.txt`, and installer configs where they are — the hub reads them
as-is. Do it as one clean commit per plugin, only after that plugin's hub build is confirmed
green.
