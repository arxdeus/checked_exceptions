## 1.0.0

- Extracted from `arxdeus_lints`, where these rules shipped alongside the
  lifetime and secret rules. Checked exceptions are a self-contained idea with
  their own annotation, so they are now their own plugin: a project that wants
  `@Throws` no longer has to take `missing_dispose` and `stateful_in_build`
  with it, and either package can be enabled without the other.

  What moved, unchanged in behaviour:

  - The `@Throws` annotation, now `package:checked_exceptions`.
  - `unhandled_throws`, which reports a call whose declared exceptions are
    neither caught at the call site nor re-declared by the enclosing function.
  - `empty_catch`, which reports a `catch` clause that swallows what it
    catches. It belongs with `unhandled_throws` rather than with the lifetime
    rules: an empty `catch` is the cheapest way to silence `unhandled_throws`
    without handling anything, so shipping the first rule without the second
    would reward exactly the code it exists to prevent.
  - The quick fix that propagates an unhandled exception by annotating the
    enclosing function.
  - The curated table of SDK and Flutter members known to throw, and
    `tool/verify_sdk_table.dart`, which checks that all 141 entries name a
    member that really exists and that the rule's lookup can reach.

  Migration: replace the `arxdeus_lints` import used for `@Throws` with
  `package:checked_exceptions/checked_exceptions.dart`, add
  `checked_exceptions` to `dependencies` and to the `plugins` section, and
  change any `// ignore: arxdeus_lints/unhandled_throws` (or `empty_catch`)
  comment to the `checked_exceptions/` prefix. Nothing else about the rules
  changed: the diagnostics they report are identical.
