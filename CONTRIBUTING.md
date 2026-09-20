# Contributing

Thanks for taking an interest. The most useful thing you can do before writing
code is to open an issue with the Dart snippet you expected a diagnostic on, or
the one you did not.

## Scope

Two rules that only make sense together:

- `unhandled_throws` reports a call whose declared exceptions are neither caught
  at the call site nor re-declared on the enclosing function.
- `empty_catch` reports a `catch` clause that swallows what it caught.

The second exists because an empty `catch` is the cheapest way to silence the
first without handling anything. Shipping `unhandled_throws` alone would reward
exactly the code it exists to prevent.

What is deliberately out of scope: inferring what a function throws. Dart has no
checked exceptions, so there is no sound way to do it, and guessing would produce
false positives on code that was always fine. The rule knows only what `@Throws`
declares and what the curated SDK table records.

A false positive matters more here than in most lints, because `unhandled_throws`
fails a build. A rule that cries wolf gets switched off, and then reports nothing
at all.

## Getting set up

```sh
git clone https://github.com/arxdeus/checked_exceptions
cd checked_exceptions && dart pub get
```

The example is its own package and resolves separately:

```sh
cd example && dart pub get
```

`example_flutter/` resolves on its own too, with `flutter pub get`. It is
separate because `flutter_test` pins a `test_api` that caps `analyzer` below the
`^14` an analyzer plugin needs, so a Flutter package and this one cannot share a
single version solution.

## Checks

Everything CI runs, you can run:

```sh
dart format .
dart analyze --fatal-infos            # must be clean
dart test                             # the rule matrix
dart run tool/verify_example.dart     # the plugin loads, and fires where documented
dart run tool/verify_sdk_table.dart   # all 141 SDK entries resolve
dart pub publish --dry-run            # the archive still validates
```

Two of those are less obvious than they look.

**`verify_example.dart`.** `dart test` drives the rules through the analyzer's
testing harness, which calls them directly. That is a fine way to test rule logic
and a useless way to find out whether the *plugin* works: the harness never
registers it, never loads it the way the analysis server does, and never reads an
`analysis_options.yaml`. So a plugin that registers under the wrong name, or
fails to start at all, leaves every test passing while doing nothing whatsoever
for a real user.

This package shipped exactly that fault. The example enabled the plugin with a
version constraint, the analysis server looked for it on pub.dev where it was not
published, and setup failed silently. Every `// reported:` comment in the example
was a claim nothing checked.

The tool reads those comments as the specification: each `// reported: <rule>`
claims one diagnostic of that rule, and the per-rule totals must match exactly.
Adding a case to the example extends the check for free.

This is also why the example's `analysis_options.yaml` names the plugin by
`path:` rather than by version. A `pubspec_overrides.yaml` will not redirect it,
because the analysis server resolves a plugin independently of the package around
it.

**`verify_sdk_table.dart`.** The table of SDK and Flutter members known to throw
is hand-written. An entry naming a member that does not exist, or one the rule's
own lookup cannot reach, fails silently: no test breaks, the lint simply never
fires for it. The tool resolves all 141 entries against the real SDKs through the
analyzer's element model, which is why it needs Flutter installed. Run it after
any change to the table or any analyzer upgrade.

## Commit messages

Commits follow [Conventional Commits][cc]:

```
<type>(<optional scope>): <summary in the imperative mood>
```

The scope is usually the rule: `fix(unhandled_throws):`, `feat(empty_catch):`.

| Type | For |
| --- | --- |
| `feat` | A rule reports something it did not before. |
| `fix` | A false positive, or something that should have been reported. |
| `perf` | Same diagnostics, less work. Rules run on every node of every file. |
| `refactor` | Internal shape, no behaviour change. |
| `docs` | README, CHANGELOG, comments. |
| `test` | Tests and the tools that check invariants. |
| `build` | `pubspec.yaml`, dependency constraints, the archive. |
| `ci` | Workflows. |
| `chore` | Anything left over. |

Append `!` after the type for a breaking change, and explain the migration in the
body. Renaming the annotation or a rule is breaking: both appear in consumers'
source, the rule names in every `// ignore:` comment.

Keep the summary under about 72 characters, lowercase, no trailing period.

## Pull requests

- One concern per pull request.
- Every behaviour change needs a test, in both directions: the case that should
  now be reported, and the nearby case that must stay quiet.
- Adding to the SDK table means running `verify_sdk_table.dart`, and naming a
  member that really throws in practice rather than in principle.
- If the change is worth a reader's attention, add it to the example, which
  documents and tests it in one place.
- Update `CHANGELOG.md` under an `## Unreleased` heading for anything a consumer
  would notice.

## Releasing

1. `CHANGELOG.md`: turn `## Unreleased` into the version.
2. `pubspec.yaml`: bump `version`, following [semver][]. A new diagnostic, or a
   new SDK table entry, is a minor bump: both can fail a build that passed
   before.
3. `dart pub publish --dry-run` must be clean.
4. Merge, then tag: `git tag v<version> && git push origin v<version>`.

The tag triggers the `publish` workflow, which publishes through GitHub's OIDC
token. There is no stored pub credential to leak.

## License

By contributing you agree that your contribution is MIT licensed, as the rest of
the package is.

[cc]: https://www.conventionalcommits.org/en/v1.0.0/
[semver]: https://semver.org
