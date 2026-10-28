# Continuous integration

Switch Launcher is a SwiftUI/AppKit app, so it can only be built on macOS. Linux runners
(like the homelab's Docker runner) can't build it.

## Gitea (homelab)

`.gitea/workflows/build.yml` runs on every push to `main`, on pull requests and on `v*` tags:

1. `swift test`
2. `./scripts/build-app.sh --dist`, which writes `dist/Switch-Launcher-<version>.zip` and a `.sha256`
3. uploads both as a workflow artifact
4. on a `v*` tag, creates a Gitea release with the zip attached

The job asks for a runner labelled `macos-arm64`. To turn a Mac into that runner:

```bash
GITEA_URL=https://gitea.parseit.net RUNNER_TOKEN=<token> ./scripts/setup-macos-runner.sh
```

The token comes from Gitea › Site Administration › Actions › Runners › *Create new runner*.
The script installs `act_runner` with Homebrew, registers it in host mode and keeps it running
with a LaunchAgent (`~/Library/LaunchAgents/net.parseit.gitea-runner.plist`).

## GitHub

`.github/workflows/build.yml` does the same on GitHub's `macos-15` runners, and attaches the zip to
a GitHub release for `v*` tags.

## Releasing

1. Update `VERSION` and `CHANGELOG.md`.
2. Commit, then tag: `git tag v1.0.0 && git push --tags`.
