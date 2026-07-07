# _plugins — Dichotic Studios release hub

Public meta-repo (public for free Actions runners) that owns CI/CD for every Dichotic
Studios audio plugin: build, sign, notarize, package, and upload to R2, then publish the
in-app update manifest. Secrets and the pipeline live **once, here**. Each plugin is a git
submodule and one entry in `plugins.json`. No GitHub org.

It is safe to be public: Actions secrets are never exposed by a public repo, and the pipeline
**never produces a public build artifact** (no `upload-artifact`, no GitHub release on this
hub) — every build goes **straight to R2**, served only through the gated CDN
(`cdn.dichoticstudios.com`). The hub only **reads** the plugin repos (checkout + webplug-ui);
it never writes to them. Any GitHub release/tag on a plugin is one you cut by hand.

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
  scripts/                     # add-plugin, release, update-plugins, secrets-sync, lib
  plugins/<name>/              # each plugin as a submodule (tracks its main branch)
  .github/
    workflows/release.yml      # the generic pipeline (dispatch or <plugin>-v<version> tag)
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
     (github.com/settings/tokens?type=beta), **Contents: Read-only**. Under
     **Repository access you MUST explicitly select every plugin repo AND `webplug-ui`.**
     Fine-grained tokens default to public repos only; a missing repo shows up as a 404
     "Repository not found", which reads like an auth error but is a scope error.
   - **`SITE_DEPLOY_TOKEN` (1, optional)** — fine-grained PAT, Contents: Read **and Write**
     on `noahbaxter/dichoticstudios.com`. Only needed to publish the update manifest.

## Adding a new plugin

```bash
make add-plugin NAME=foo REPO=noahbaxter/foo
```

Then edit `plugins.json`: set `target` and `productName` from the plugin's `CMakeLists.txt`
(`juce_add_plugin(<target> … PRODUCT_NAME "<product>")`), confirm `windowsInstaller` and
`r2Bucket`, and set `webBuild` (`null`, or `{dir, usesWebplugUi}`). Add `foo` to the
`plugin:` choice list in `.github/workflows/release.yml`. Make sure `PLUGINS_CI_TOKEN`'s
Repository access includes the new repo. That's it.

## Cutting a release

```bash
make release PLUGIN=pewpew VERSION=0.2.0
# or, version from the plugin's VERSION file:
make release PLUGIN=pewpew
# or push a tag:
git tag pewpew-v0.2.0 && git push origin pewpew-v0.2.0
```

What happens (per selected plugin):

1. **setup** reads `plugins.json`; version falls back to the plugin's `VERSION` file.
2. Checks out the plugin's **latest `branch` tip** (`--remote`, no pointer bump needed) with
   private auth + LFS.
3. Builds **macOS** (universal, target 10.15), **Windows** (VS 2022 x64), **Linux** (Ninja).
   Runs `bun` web build first when `webBuild` is set.
4. **macOS**: sign (Developer ID Application) → notarize (`notarytool --wait`) → staple →
   signed `.pkg`. With no Apple secrets it builds an UNSIGNED pkg and warns.
5. **Windows**: Inno Setup `.exe` from the plugin's `.iss`. **Unsigned** today (SmartScreen
   warning) — see TODO below.
6. **Linux**: zips whatever formats built (VST3/LV2/CLAP/Standalone).
7. **R2**: each build job uploads its installer **straight to R2** under `<plugin>/`, with
   both a versioned key (`<Target>-<version>-macOS.pkg`) and a stable "latest" key
   (`<Target>-macOS.pkg`). No `upload-artifact`, so nothing is ever publicly downloadable
   from this hub — R2, served via the CDN, is the only store. The run fails if R2 secrets
   are unset (a build with nowhere to go is a failed release).
8. **finalize**: prints the R2/CDN keys and publishes the update manifest. It does **not**
   create a GitHub release; if you want one as a changelog, cut it by hand on the plugin repo.
9. **Update manifest** (if `publish_manifest` on and `downloadBaseUrl` set): commits
   `<manifestPath>` = `{ "version", "url" }` to `dichoticstudios.com`; Cloudflare Pages
   auto-deploys. This is what the in-app update notifier polls.

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

- **Build without publishing**: a dispatch with `publish_manifest` off builds + uploads to
  R2 without touching the site. To avoid overwriting the stable "latest" keys while testing,
  bump `VERSION` to a throwaway (the versioned keys are separate). Or iterate one OS on the
  plugin's own repo CI.
- **Re-run a failed job**: Actions UI → the run → "Re-run failed jobs".
- **One platform**: comment out the other `build-*` jobs' `needs` on `release`, or use the
  plugin's own repo CI to iterate a single OS.
- **Logs**: GitHub Actions → the run. R2 uploads print the S3 keys; the manifest step prints
  the committed path + version.
- **Pin a submodule locally**: `make update` pulls all submodules to latest and shows moved
  pointers (releases don't need this — they use `--remote`).

## Troubleshooting

- **bun can't fetch `webplug-ui` / 404 "Repository not found"**: the git `insteadOf` HTTPS
  rewrite is the fix (handled in `actions/build-web`). A 404 means `PLUGINS_CI_TOKEN`'s
  **Repository access does not include that repo** — it is a scope problem, not auth. Add
  the repo (and `webplug-ui`) to the token and re-run.
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

## Secrets → jobs

| secret | used by |
|--------|---------|
| `PLUGINS_CI_TOKEN` | setup (version read), checkout-plugin (private submodule), build-web (webplug-ui). **Read-only.** |
| `APPLE_CERTIFICATE_APPLICATION` / `_INSTALLER` / `_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | build-macos (sign + notarize) |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | build-macos / build-windows / build-linux (upload to R2), finalize (read back / summary) |
| `SITE_DEPLOY_TOKEN` | finalize (manifest commit to the site repo) |

## Migrating a plugin repo off self-release

Once the hub builds a plugin green, stop that repo from double-releasing: in its
`build.yml`, remove the `v*` tag trigger and the tag-gated `package-*` / `release-*` jobs;
keep the cheap Linux build + C++ unit test jobs so its own PRs still get validated. Leave
`VERSION`, `CMakeLists.txt`, and installer configs where they are — the hub reads them as-is.
Do it as one clean commit per plugin, only after that plugin's hub build is confirmed green.
