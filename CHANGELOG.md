# Changelog

## 1.0.0

- `export` directives no longer carry `show` clauses. A `show` that lists
  exactly what the file declares is noise, and one that drifts out of date is
  worse than noise, so the exported surface is now decided by what the `src/`
  files declare publicly.

  That is only safe with something checking it, because without a `show` a
  helper added to an exported `src/` file becomes public API the moment it is
  written. `test/public_api_test.dart` pins the exported names of every
  published library and fails naming the symbol when one leaks. The removal
  itself was verified the same way: the exported surface is byte-identical to
  what the `show` clauses produced, so the clauses were redundant rather than
  load-bearing.

- The shared analyzer-plugin infrastructure moved to a new package,
  `analyzer_plugin_toolkit`, in `packages/analyzer_plugin_toolkit`. The
  per-element memo table, the annotation lookup, the element normalization and
  the quick-fix test harness live there now, in one copy rather than two.

  Splitting checked exceptions out had left both plugins holding near-identical
  copies of the same code, including the annotation lookup, which is
  correctness-critical: it is what stops a same-named annotation from another
  package driving rules that know nothing about it. Two copies of that is one
  too many.

  The lookup is now `AnnotationFinder`, parameterized by the declaring package
  instead of hardcoding one, and it carries its own tests, including a mutation
  check that breaking the package comparison fails the suite. Nothing about the
  rules changed: over the same sources they report byte-identical diagnostics.

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
