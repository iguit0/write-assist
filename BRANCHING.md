# Branching & PR Workflow

WriteAssist uses a **single-trunk** model: `main` is always the latest working code and the only source of releases.

## The rules

1. **`main` is protected** — no direct pushes. All changes go through a PR.
2. **Feature branches** live only as long as their PR. Name them `feat/<short>`, `fix/<short>`, `chore/<short>`, or `docs/<short>`.
3. **Every PR must pass CI** (`swift build`, `swift test`, `swiftlint --strict`, DMG build) before merging.
4. **Squash-merge** PRs into `main`. Keeps history linear and revertable.
5. **Releases are tags, not branches.** Preview and stable are channels expressed as tag patterns (`v0.2.0-preview.1`, `v0.2.0`), never as branches.

## Day-to-day flow

```bash
# start work
git checkout main && git pull
git checkout -b feat/paragraph-collapse

# hack, commit locally
git commit -am "feat: collapse paragraphs with zero issues"

# publish and open PR
git push -u origin feat/paragraph-collapse
gh pr create --fill

# after approval + CI green: squash-merge via GitHub UI or:
gh pr merge --squash --delete-branch
```

## PR checklist

- [ ] Code compiles with zero errors and zero warnings (`swift build`)
- [ ] `swiftlint --strict` passes
- [ ] `swift test` passes
- [ ] `CHANGELOG.md`'s `## [Unreleased]` section has a new bullet describing the change (if user-visible)
- [ ] No dead code, commented-out blocks, or debug prints introduced
- [ ] PR description explains **why**, not just **what**

## When to bump `VERSION`

Only when about to cut a release. Bumping on every PR is noise — the release commit is the right place.

- Bug fix release → patch bump (`0.2.0` → `0.2.1`)
- New feature → minor bump (`0.2.0` → `0.3.0`)
- Breaking change → major bump (`0.2.0` → `1.0.0`)

```bash
echo "0.3.0" > VERSION
# also move CHANGELOG.md's Unreleased section into a new ## [0.3.0] - YYYY-MM-DD section
git add VERSION CHANGELOG.md
git commit -m "chore: prepare 0.3.0 release"
git push
```

Then tag and push per [RELEASING.md](RELEASING.md).

## Why no `develop` or `preview` branch?

For a one- or two-person project, a second long-lived branch doubles the merge surface without adding clarity. The preview/stable split is about **who can run a build**, not about **where the code lives** — that's a tag concern, not a branch concern.
