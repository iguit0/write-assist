# Releasing WriteAssist

WriteAssist ships through two channels, both driven by git tags on `main`:

- **Preview** — internal/tester builds. Tag pattern: `vX.Y.Z-preview.N`.
- **Stable** — public production release. Tag pattern: `vX.Y.Z`.

Both produce an ad-hoc signed `.dmg` attached to a GitHub Release. Preview is marked "Pre-release" and doesn't appear as the repo's "Latest" badge; stable does.

> **Current status: BETA pipeline.** Builds are ad-hoc signed but not notarized by Apple, because we don't have an Apple Developer Program membership yet. Testers will see a one-time Gatekeeper warning on first launch — see [Installing a BETA build](#installing-a-beta-build) below.

## Cutting a preview release

1. Make sure `main` is green on CI and contains the changes you want.
2. Confirm `VERSION` matches the base version you're about to tag. If not, bump it:
   ```bash
   echo "0.2.0" > VERSION
   git add VERSION
   git commit -m "chore: bump VERSION to 0.2.0"
   git push
   ```
3. Pick the next preview number for this base version. If this is the first preview of `0.2.0`, use `1`; otherwise increment.
4. Tag and push:
   ```bash
   git tag -a v0.2.0-preview.1 -m "Preview 0.2.0-preview.1"
   git push origin v0.2.0-preview.1
   ```
5. Watch the Actions tab — the `Release` workflow runs in ~6–10 min.
6. When green, the release appears on the [Releases page](../../releases) marked **Pre-release**.
7. Share the direct DMG link with testers (plus the install instructions below):
   ```
   https://github.com/iguit0/WriteAssist/releases/download/v0.2.0-preview.1/WriteAssist-0.2.0-preview.1.dmg
   ```

## Cutting a stable release

1. Preview-test `vX.Y.Z-preview.N` thoroughly. If anything's wrong, fix, push, cut `vX.Y.Z-preview.(N+1)`. Don't promote a broken preview.
2. Once accepted, tag stable directly from the same commit:
   ```bash
   git tag -a v0.2.0 -m "Release 0.2.0"
   git push origin v0.2.0
   ```
3. The workflow runs and publishes as the new **Latest**.

## Installing a BETA build

Send testers this section verbatim.

**Because WriteAssist isn't notarized by Apple yet, macOS will block it on first launch. Here's how to allow it (one-time, per install).**

### Step 1 — Download and move to Applications
1. Download `WriteAssist-<version>.dmg` from the [Releases page](../../releases).
2. Double-click the DMG to mount it.
3. Drag **WriteAssist** into the **Applications** folder shortcut.
4. Eject the DMG.

### Step 2 — First launch: allow the app through Gatekeeper
1. Open `/Applications` in Finder, double-click **WriteAssist**.
2. macOS will show: *"WriteAssist cannot be opened because Apple cannot check it for malicious software."* Click **Done**.
3. Open **System Settings → Privacy & Security**.
4. Scroll to the **Security** section. You'll see a line that says *"WriteAssist was blocked from use because it is not from an identified developer."* Click **Open Anyway** next to it.
5. You may be prompted for your password; enter it.
6. macOS will re-prompt: *"macOS cannot verify the developer of WriteAssist. Are you sure you want to open it?"* Click **Open**.

That's it — from now on the app launches normally.

### Alternative: Terminal one-liner

If the System Settings flow fails (rare on some corporate-managed Macs), remove the quarantine attribute directly:

```bash
xattr -dr com.apple.quarantine /Applications/WriteAssist.app
```

Then launch normally.

### Step 3 — Grant Accessibility permission
WriteAssist uses macOS Accessibility APIs to read text from other apps. On first use:

1. The app will prompt you to open **System Settings → Privacy & Security → Accessibility**.
2. Toggle **WriteAssist** on.
3. Return to WriteAssist — it's ready.

## Versioning rules

- We follow [SemVer](https://semver.org/): `MAJOR.MINOR.PATCH`.
- `MAJOR` — breaking changes to public behavior or user-visible contracts.
- `MINOR` — new features, backwards-compatible.
- `PATCH` — bug fixes only.
- Preview tags carry a `-preview.N` suffix. `N` resets to `1` for each new base version.
- The git tag's base version MUST equal the contents of `VERSION` at that commit. CI fails the build if they disagree.
- `CFBundleVersion` is the GitHub Actions run number — monotonically increasing across the whole pipeline, satisfying any future Sparkle update feed.

## Troubleshooting

**Version mismatch error in CI** — the tag's base version doesn't match the `VERSION` file. Delete the bad tag (`git push origin :v0.2.0-preview.1`) and recreate it from the correct commit.

**Tester reports "app is damaged and can't be opened"** — quarantine attribute stuck with no override available. Have them run `xattr -dr com.apple.quarantine /Applications/WriteAssist.app`.

**Tester can't find "Open Anyway" in System Settings** — they need to have tried to launch the app at least once first. The button only appears in System Settings *after* Gatekeeper has blocked a launch attempt.

## Hotfix releases

1. Branch from the tag: `git checkout -b hotfix/0.2.1 v0.2.0`
2. Fix, commit, PR to `main`, merge.
3. From `main`, bump `VERSION` to `0.2.1`, tag `v0.2.1`, push.
