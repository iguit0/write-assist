# Release Checklist

Step-by-step runbook for setting up and shipping WriteAssist releases. Work through this top-to-bottom for the first release; later releases skip straight to [Cutting a preview release](#5-cutting-a-preview-release).

Reference docs for the **concepts** behind this: [`RELEASING.md`](RELEASING.md), [`BRANCHING.md`](BRANCHING.md), [`docs/ci-cd.md`](docs/ci-cd.md). This file is pure action.

---

## 1. One-time setup

Done before your first release ever. Local steps are per-machine; GitHub steps are per-repo.

### On your Mac

- [ ] `xcode-select --install` (Xcode Command Line Tools)
- [ ] `brew install create-dmg`
- [ ] `brew install swiftlint` (if not already installed)
- [ ] `swift --version` reports 6.0 or later

### In the repo

- [ ] `assets/AppIcon.icns` exists (1024×1024 source → `iconutil -c icns AppIcon.iconset`)
- [ ] `CFBundleIdentifier` in `assets/Info.plist.template` is what you want (plan default: `com.writeassist.app`) — **changing this later orphans every existing install's AX permissions**, so get it right now
- [ ] Pipeline files committed to `main`: `VERSION`, `assets/`, `scripts/`, `.github/workflows/*.yml`, `.gitignore` additions, all docs

### On GitHub

- [ ] Settings → Branches → **Add branch protection rule** for `main`:
  - [ ] Require a pull request before merging
  - [ ] Require status checks to pass (select `CI / build`)
  - [ ] Do not allow force pushes

---

## 2. Local sanity check

Do this once after the pipeline files land. Proves the scripts work on your Mac before CI.

- [ ] `./scripts/build-app.sh 0.0.1-dev.1` exits 0
- [ ] `file build/WriteAssist.app/Contents/MacOS/WriteAssist` shows **both** `arm64` and `x86_64`
- [ ] `codesign -dv build/WriteAssist.app 2>&1 | grep Signature` shows `Signature=adhoc`
- [ ] `defaults read "$(pwd)/build/WriteAssist.app/Contents/Info.plist" CFBundleShortVersionString` prints `0.0.1-dev.1`
- [ ] `open build/WriteAssist.app` — pencil icon appears in the menu bar
- [ ] `./scripts/make-dmg.sh 0.0.1-dev.1` produces `build/WriteAssist-0.0.1-dev.1.dmg`
- [ ] Double-click the DMG → drag-to-Applications window appears
- [ ] Drag to `/Applications`, eject, open — Gatekeeper blocks on first launch (expected)
- [ ] **System Settings → Privacy & Security → Open Anyway** → app launches normally
- [ ] Uninstall with `rm -rf /Applications/WriteAssist.app` when done

---

## 3. CI dry run

Do this once on a throwaway PR to prove the CI workflow works end-to-end.

- [ ] Create any trivial branch (`git checkout -b test/ci-smoke`, touch a file, commit, push)
- [ ] Open a PR targeting `main`
- [ ] Actions tab → watch `CI` workflow — should turn green in ~6–10 min
- [ ] Download the workflow artifact, unzip, confirm the DMG is present
- [ ] Close the PR without merging, delete the branch

---

## 4. Before every release

Every time you cut a release — preview or stable — run this block first.

- [ ] `main` is green on CI
- [ ] `VERSION` file contains the exact base version you're about to tag (bump and commit if not)
- [ ] `CHANGELOG.md` has meaningful bullets under `## [Unreleased]`
- [ ] You're on `main`, it's up to date: `git checkout main && git pull`

---

## 5. Cutting a preview release

- [ ] Pick the next preview number for this base version (start at `1`, increment thereafter)
- [ ] Tag and push:
  ```bash
  git tag -a v0.1.0-preview.1 -m "Preview 0.1.0-preview.1"
  git push origin v0.1.0-preview.1
  ```
- [ ] Actions tab → watch `Release` workflow turn green (~6–10 min)
- [ ] On the [Releases page](../../releases):
  - [ ] Release title: `WriteAssist 0.1.0-preview.1`
  - [ ] **Pre-release** label is present (not "Latest")
  - [ ] `WriteAssist-0.1.0-preview.1.dmg` is attached
  - [ ] Release body contains the BETA warning + link to tester install instructions
- [ ] Download the DMG from the release page, install it, run through the tester bypass flow yourself — confirm the app launches
- [ ] Share the direct DMG URL with testers:
  ```
  https://github.com/<owner>/WriteAssist/releases/download/v0.1.0-preview.1/WriteAssist-0.1.0-preview.1.dmg
  ```
  Also point them at `RELEASING.md § Installing a BETA build` for the Gatekeeper bypass.

---

## 6. Cutting a stable release

Only do this after the exact commit has shipped as a preview and been validated.

- [ ] Tag and push from the same commit that was preview-tested:
  ```bash
  git tag -a v0.1.0 -m "Release 0.1.0"
  git push origin v0.1.0
  ```
- [ ] Actions tab → `Release` workflow green
- [ ] On the [Releases page](../../releases):
  - [ ] Release title: `WriteAssist 0.1.0`
  - [ ] **NOT** marked Pre-release — it's now the "Latest" release
  - [ ] DMG attached, downloads correctly

---

## 7. Known-failure drill (optional, do once)

Proves the error-handling path works so you trust it later.

- [ ] With `VERSION` = `0.1.0`, push a deliberately-mismatched tag:
  ```bash
  git tag v9.9.9-preview.1
  git push origin v9.9.9-preview.1
  ```
- [ ] Workflow should **fail** at the "Resolve version & channel from tag" step with a clear error message
- [ ] Clean up:
  ```bash
  git push origin :v9.9.9-preview.1
  git tag -d v9.9.9-preview.1
  ```

---

## When things go wrong

| Symptom | Where to look |
|---|---|
| Workflow fails at "Resolve version" | Tag's base version doesn't match `VERSION` file. Delete tag, fix, retag. |
| Tester reports "app is damaged" | Have them run `xattr -dr com.apple.quarantine /Applications/WriteAssist.app` |
| `create-dmg` times out in CI | Usually flaky AppleScript — re-run the workflow. If chronic, see `docs/ci-cd.md § When create-dmg flakes` |
| `codesign` fails locally with "resource fork, Finder information, or similar detritus not allowed" | Run `xattr -cr build/WriteAssist.app` before re-signing |
| `swift build --arch arm64 --arch x86_64` fails locally | Usually missing Xcode CLT or mismatched Xcode — `xcode-select --install` and retry |
