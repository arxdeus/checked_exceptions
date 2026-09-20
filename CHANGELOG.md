# Changelog

All notable changes to this package are recorded here. Versions follow
[semver](https://semver.org). A new diagnostic, or a new SDK table entry, is a
minor bump rather than a patch, because either can fail a build that passed
before.

## 1.0.0

First release.

Checked exceptions for Dart, as an analyzer plugin. Declare what a function
throws and the analyzer holds callers to it.

```dart
class ConfigError implements Exception {}

@Throws({ConfigError})
String loadConfig(String path) => /* ... */;

String read(String path) {
  return loadConfig(path); // unhandled_throws
}
```

Two rules, which only make sense together:

- **`unhandled_throws`** reports a call whose declared exceptions are neither
  caught at the call site nor re-declared on the enclosing function. Satisfy it
  by catching the exception, or by propagating it with `@Throws` and pushing the
  decision to your caller.

- **`empty_catch`** reports a `catch` clause that swallows what it caught: the
  body is empty, nothing is rethrown, and the exception is never used. A comment
  inside the braces clears it, which is the documented way to say the silence is
  deliberate.

  This ships alongside the first rule rather than separately because an empty
  `catch` is the cheapest way to silence `unhandled_throws` without handling
  anything. A release with one and not the other would reward exactly the code it
  exists to prevent.

A **quick fix** propagates an unhandled exception by annotating the enclosing
function, so the common resolution is one keystroke in the IDE.

A **curated table of 141 Dart and Flutter members** known to throw is treated as
if those members carried `@Throws`, so `int.parse`, `File.readAsString` and
`jsonDecode` are covered without annotating the SDK.
`tool/verify_sdk_table.dart` resolves every entry against the real SDKs, because
an entry naming a member that does not exist would fail silently: no test breaks,
the lint simply never fires for it.

`@Throws` is identified by its declaring package, so a same-named annotation from
somewhere else cannot drive these rules.

Diagnostics are suppressed the usual way, with the plugin name as a prefix:

```dart
// ignore: checked_exceptions/unhandled_throws
```

### If you used these rules inside arxdeus_lints

They shipped there once, alongside rules about object lifetimes and secrets.
Checked exceptions are a self-contained idea with their own annotation, so a
project that wants `@Throws` no longer has to take `missing_dispose` with it.

To migrate: add `checked_exceptions` to `dependencies` and to the `plugins`
section of `analysis_options.yaml`, import `@Throws` from
`package:checked_exceptions/checked_exceptions.dart`, and change any
`// ignore: arxdeus_lints/unhandled_throws` or `empty_catch` comment to the
`checked_exceptions/` prefix. The diagnostics themselves are identical.
