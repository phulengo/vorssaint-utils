# Contributing to Vorssaint

Vorssaint aims to stay small, native and readable. Contributions are accepted
under GPL-3.0-or-later unless stated otherwise.

## Getting started

You need macOS 14 or newer, Apple Silicon and the Xcode Command Line Tools.
The project builds with `build.sh`, without an Xcode project or external package
dependencies. `Package.swift` supports editor indexing; it does not assemble or
sign the app bundle.

```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test
```

To install and launch the separate Developer app, use `./build.sh --dev --install`.
It has its own preferences and permissions and does not replace the official app.
A plain `./build.sh` builds the optimized variant used by CI; its health check is
`./build/Vorssaint --selftest`.

### Packaging a copy for someone

`Tools/make-edition.sh NAME EDITION_FOLDER [SETTINGS.plist]` builds a renamed copy
to give someone, writing `dist/NAME.app` and a DMG. It builds from a copy of the
tree in which `Tools/rename-app.py` replaces the app's name in every language;
copyright and license notices keep the original name, as the GPL asks. The edition
folder holds the copy's icon art and, optionally, a silhouette for its menu bar and
windows; `Resources/Editions/Rocky` is one. The copy never checks for updates, since
an official update would replace it with a different app. Given a settings backup,
it starts from those settings on its first launch on each Mac. It is signed like a
local build, not notarized, so macOS asks to confirm it in Privacy & Security the
first time it opens.

To let a copy update itself, build it with `EDITION_UPDATES=owner/repository` and
`EDITION_REVISION=N`. Its version gains a fourth number, such as `3.4.4.1`, and it then
takes only releases of that repository that are newer and signed with the same
certificate. The copy pins that certificate in place of the official Developer ID,
so keep the signing identity: a copy signed with another one cannot update the
installed copies. To ship an update, build the next revision without the settings,
which only a first install needs, and publish its DMG as a release tagged with the
version:

```sh
EDITION_UPDATES=owner/repository EDITION_REVISION=2 Tools/make-edition.sh Rocky Resources/Editions/Rocky
gh release create v3.4.4.2 dist/Rocky-3.4.4.2.dmg --repo owner/repository --title "Rocky 3.4.4.2"
```

### Stable signing

Developer and install builds automatically try to create a stable local signing
identity when none is available. You can also run `./Tools/setup-signing.sh`.
Keep that identity across rebuilds: ad-hoc signatures change with the binary and
can invalidate macOS permission grants. Check the build output for signing
failures. For stale grants, see [troubleshooting](docs/TROUBLESHOOTING.md#resetting-permissions).

Official releases use Developer ID signing and notarization through the protected
release workflow. Local signing does not produce an official release.

## Scope and implementation

Before a substantial feature, search existing issues and PRs and discuss the
direction in an issue. Explain the user need, required permissions, dependencies
and ongoing maintenance. Prefer existing macOS capabilities and repository code
over a new subsystem. Keep each PR focused on one independently useful change.

- App lifecycle lives in `Sources/Vorssaint/App`, shared catalogs and preferences
  in `Core`, behavior in `Services`, views in `UI`, and diagnostics in `Support`.
  Keep reusable decisions outside views where they can be tested.
- Check other callers and the upgrade path when fixing shared behavior.
- New features belong in the feature catalog, with availability and permission
  checks on every entry point. Optional background work should stop when disabled.
- User preferences must participate in settings backup. Machine-specific state
  and private content need an explicit exclusion.
- Update every locale in `AppLanguage.allCases`, including feature-specific
  string catalogs. A new language also needs its locale registration, localized
  permission prompts where applicable, and coverage tests.
- New source files retain the project's SPDX license and copyright headers.

Sensor changes should include a dump from `./build/Vorssaint --sensors` and the
Mac model. Selection logic lives in `TemperatureSensorSelector` and `SystemMonitor`.

## Validation

Documentation-only changes need a diff and link check. For code changes, run the
relevant tests; `./build.sh --list-tests` lists suites and
`./build.sh --test-suite=NAME` selects one. Behavior tests should fail without the
fix and preserve legitimate use, rather than pinning private implementation text.

The test executable compiles a selected set of sources, so passing tests does not
prove the app builds. Build the app and run its selftest for runtime, UI or bundled
resource changes. CI also checks the optimized build, selftest, tests and packaging.
Builds should finish without warnings.

For behavior involving windows, permissions or hardware, describe what you actually
verified and on which Mac and macOS version. Include display, Spaces or language
details when relevant, and state what remains untested. Compilation and static
inspection alone do not demonstrate an interaction on a real Mac.

## Pull requests

Explain the behavior before and after, the scope and validation. Use
`type(scope): lowercase imperative phrase` for the title and reuse an existing
scope where possible. Open unfinished work as a draft and name what is missing.
The [template](.github/PULL_REQUEST_TEMPLATE.md) is a prompt, not a form.

Leave version bumps and `CHANGELOG.md` to the maintainer. Describe the user-visible
effect in the PR so it can become a release note with your credit.

When an issue exists, include one reference per line:

```text
Refs #123
Refs #456
```

Avoid `Closes` or `Fixes`: those close the issue at merge, before users receive
the fix. The fix-status workflow tracks the reference, notifies the reporter when
a stable release carries the fix, and can close the issue after two weeks without
a response. If the PR addresses only part of an issue, say exactly which part.

For agent-assisted work, see [contributing with an agent](docs/AI-CONTRIBUTIONS.md).
Bug reports and feature requests use the [issue forms](https://github.com/vorssaint/vorssaint-utils/issues/new/choose).
Report vulnerabilities through [private security reporting](SECURITY.md).

## Releases (maintainers)

Integrating into `main`, pushing a branch and opening a PR do not publish a release.
Publication requires an explicit release decision, including beta or stable.

Before sending a version tag, validate the final commit on `main`, confirm its
verified signature, and match `Resources/Info.plist` and the release notes to the
chosen version. Use a signed tag such as `vX.Y.Z-beta.N` or `vX.Y.Z`.
Sending the tag starts [the release workflow](.github/workflows/release.yml).

The protected `release-signing` environment holds the signing and notarization
credentials. The workflow builds, signs and notarizes the app and DMG, then
publishes an immutable release. Confirm publication succeeded; a pushed tag alone
is not a published version. Beta releases remain prereleases and do not replace
the latest stable release or its Homebrew cask. Do not move published tags or
replace published artifacts.
