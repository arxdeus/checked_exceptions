<!--
The title should read as a conventional commit, since it becomes one:

    fix(unhandled_throws): look through a cascade target

See CONTRIBUTING.md for the types in use.
-->

## What and why

<!-- What changes, and the reason the diff does not already show. -->

## Checks

- [ ] `dart format .`
- [ ] `dart analyze --fatal-infos` is clean
- [ ] `dart test` passes
- [ ] `dart run tool/verify_example.dart` passes
- [ ] `dart run tool/verify_sdk_table.dart` passes (required if the table changed)
- [ ] `CHANGELOG.md` updated under `## Unreleased`, if a consumer would notice

## Rule behaviour

- [ ] Unchanged
- [ ] Reports something new, and a test covers it
- [ ] Stops reporting something, and a test covers why that was wrong
- [ ] Breaking, the title carries `!`, and the body explains the migration
