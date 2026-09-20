# checked_exceptions

Checked exceptions for Dart, delivered as an [analyzer plugin][], so they run
in your IDE and in `dart analyze` / `flutter analyze` with no extra tooling.

Dart has no checked exceptions: nothing in the language records what a function
throws, and nothing makes a caller deal with it. This package adds that as a
static rule. A function declares its failures with `@Throws`, and every caller
must either catch them or declare them in turn, exactly as the callee did.

| Rule | What it catches |
| --- | --- |
| `unhandled_throws` | A call to a `@Throws`-annotated target whose exceptions are neither caught nor re-declared. |
| `empty_catch` | A `catch` clause that swallows the exception: empty body, no `rethrow`, exception never used. |

The two belong together: `unhandled_throws` pushes you to handle what a callee
declares, and `empty_catch` stops the cheapest way of pretending to. A `catch`
that names the exception and does nothing silences the first rule without
handling anything, so a package with only the first would reward exactly the
code it exists to prevent.

A curated table of SDK and Flutter members that are known to throw
(`int.parse`, `jsonDecode`, `File.readAsString`, `MethodChannel.invokeMethod`)
is treated as if those members carried `@Throws`, so the common sources of an
uncaught `FormatException` are covered without annotating the SDK.

Requires Dart 3.10 or later (analyzer plugins are not supported before that).

## Installation

The package ships both the annotation and the rules, so it is listed twice:
once as a dependency (you write `@Throws` in your code) and once as a plugin
(the analyzer runs the rules).

```yaml
# pubspec.yaml
dependencies:
  checked_exceptions: ^1.0.0
```

```yaml
# analysis_options.yaml
plugins:
  checked_exceptions: ^1.0.0
```

Both rules are registered as *warning* rules, so they are active as soon as the
plugin is enabled. Restart the Dart Analysis Server after changing the
`plugins` section.

## `unhandled_throws`

Declare what a function can throw:

```dart
@Throws({ConfigError})
Config loadConfig(String path) => ...;
```

Callers must then either catch it:

```dart
try {
  loadConfig(path);
} on ConfigError {
  // handled
}
```

or declare it themselves, which propagates the obligation to *their* callers:

```dart
@Throws({ConfigError})
Config reload() => loadConfig(path);
```

Details:

* Catch clauses are matched by subtyping, so `on Exception` covers a
  `ConfigError`, and a bare `catch (e)` covers everything.
* With several declared types, each one must be handled; the message names only
  the ones that are still unhandled.
* Only the protected region of a `try` counts. A call inside a `catch` or
  `finally` block of that same `try` is still reported.
* The annotation is the source of truth. The rule does not check whether the
  annotated body really throws.

### Quick fix: propagate with `@Throws`

The warning offers two ways out, and the IDE automates the second. On any
`unhandled_throws` warning, the quick fix **"Annotate '<function>' with
'@Throws'"** declares the escaping exceptions on the enclosing function:

```dart
int age(String raw) => int.parse(raw);   // warning: may throw FormatException

// After applying the fix:
import 'package:checked_exceptions/checked_exceptions.dart';

@Throws({FormatException})
int age(String raw) => int.parse(raw);
```

Details:

* Exactly the exceptions the warning named are declared, so applying the fix
  always clears that warning and never silences more than you were told about.
  If a `try` already catches one of several types, only the rest are declared.
* An existing `@Throws` is extended rather than duplicated, and a type it
  already names is not repeated.
* Imports are added as needed, both for the annotation and for an exception
  class that is not yet in scope.
* The annotation goes below any documentation comment and existing metadata,
  at the declaration's own indentation.
* The target is the nearest enclosing declaration, including a local function
  and a getter. Annotating a getter propagates to whoever *reads* it, just as
  annotating a method propagates to whoever calls it.
* No fix is offered when the call sits inside a closure: its exceptions do not
  escape through the enclosing declaration, so annotating it would be a lie.
  Catching inside the closure is the real fix there.

Propagating is not always right. When the function *can* recover, catch the
exception instead; the fix is a shortcut for the case where the obligation
genuinely belongs to the caller.

### Built-in SDK and Flutter knowledge

Common SDK and Flutter members that throw are treated as if they carried a
`@Throws` annotation, so the usual sources of an uncaught `FormatException`,
`StateError` or `PlatformException` are covered without annotating anything:

```dart
int age(String raw) => int.parse(raw);   // reported: FormatException
```

The covered members are:

| Source | Members | Exception |
| --- | --- | --- |
| `dart:core` | `int`/`double`/`num`/`BigInt`/`DateTime`/`Uri`/`UriData` `.parse`, `Uri.parseIPv4Address`/`.parseIPv6Address` | `FormatException` |
| `dart:convert` | `jsonDecode`, `base64Decode`, and the `decode`/`convert` members of the JSON, UTF-8, Base64, ASCII and Latin-1 codecs | `FormatException` |
| `dart:async` | `Future.timeout`, `Stream.timeout` | `TimeoutException` |
| `dart:io` | the I/O members of `File`, `Directory`, `Link`, `RandomAccessFile` and `FileSystemEntity` | `FileSystemException` |
| `dart:io` | `Socket.connect`, `ServerSocket.bind` and their raw variants | `SocketException` |
| `dart:io` | `SecureSocket.connect`/`.secure`/`.secureServer` and their raw variants | `SocketException`, `HandshakeException` |
| `dart:io` | `Process.start`/`.run`/`.runSync` | `ProcessException` |
| `dart:io` | the request methods of `HttpClient` | `SocketException`, `HttpException` |
| `dart:io` | `HttpClientRequest.close` | `SocketException`, `HttpException`, `RedirectException` |
| `dart:io` | `WebSocket.connect` | `SocketException`, `WebSocketException` |
| `package:flutter` | `MethodChannel.invokeMethod`/`.invokeListMethod`/`.invokeMapMethod` | `PlatformException`, `MissingPluginException` |
| `package:flutter` | `MethodCodec.decodeEnvelope` | `PlatformException`, `FormatException` |
| `package:flutter` | `MethodCodec.decodeMethodCall`, `MessageCodec.decodeMessage` | `FormatException` |
| `package:flutter` | `NetworkImage.loadImage`/`.loadBuffer` | `NetworkImageLoadException` |

Details:

* Membership is matched through inheritance, so a user class that
  `implements Iterable` inherits the `first` entry, and the most derived entry
  wins: `OptionalMethodChannel.invokeMethod` reports only `PlatformException`,
  because that override makes a missing implementation return `null`. Its
  `invokeListMethod` is *not* overridden, so it keeps `MethodChannel`'s wider
  entry and still reports `MissingPluginException`.
* The `tryParse` counterparts are absent on purpose: returning `null` instead
  of throwing is exactly how they differ.
* **Only `Exception`s are listed, never `Error`s.** An `Error` reports a bug in
  the calling code, and the `avoid_catching_errors` lint says not to catch one,
  so declaring it with `@Throws` would be advice to do exactly what that rule
  forbids. Rather than have two rules contradict each other, nothing that
  throws an `Error` is covered. That rules out `Iterable.first`/`.last`/
  `.single`/`.reduce`/`.firstWhere` and `Queue.removeFirst` (`StateError`),
  `list[0]` and `Iterable.elementAt` (`RangeError`), `jsonEncode`
  (`JsonUnsupportedObjectError`) and the `AssetBundle` loaders
  (`FlutterError`). Fix the call instead of catching.
* A tear-off is not a call. Naming a member without invoking it (`int.parse`,
  `xs.firstWhere`) produces a function value and runs nothing, so it is clean.
* Only members declared by the SDK or by `package:flutter` count. A
  same-named member of your own class (`Money.parse`, `Bag.first`) is ignored.

## `empty_catch`

A clause that catches and then does nothing turns a failure into silence:

```dart
try {
  loadConfig(path);
} on ConfigError {}   // reported: caught, and nothing happens
```

The rule reports a catch clause when *all* of this holds: the body contains no
statements (an empty body, or only `;`), nothing is rethrown, and the caught
exception is never used. Anything in the body clears it, including `rethrow`,
logging the exception, or throwing something else.

It is stricter than the built-in `empty_catches`, which is satisfied by
renaming the variable to `_`. Renaming handles nothing, so `catch (_) {}` is
still reported.

When the protected body calls a `@Throws`-annotated target, the message says
so: that combination is a declaration that was formally "handled" and actually
swallowed, which is exactly what silences `unhandled_throws` without doing any
work.

The escape hatch is a comment inside the braces, so that the decision to ignore
the failure is written down where it happens:

```dart
try {
  cache.evict(key);
} on CacheError {
  // Best effort: a stale cache entry is not worth failing the request.
}
```

## Turning rules off

Disable a rule for the whole package:

```yaml
plugins:
  checked_exceptions:
    diagnostics:
      empty_catch: false
```

Suppress one diagnostic with a comment, prefixed by the plugin name. The
comment applies to the line below it:

```dart
// ignore: checked_exceptions/unhandled_throws
final config = loadConfig(path);
```

`// ignore_for_file: checked_exceptions/unhandled_throws` works as well.

## Known limits

These are deliberate boundaries, not bugs:

* **`unhandled_throws` does not follow tear-offs or `.catchError`**, and does
  not analyze annotated setters.
* **The built-in SDK table is a curated list, not an analysis.** It names the
  members that throw in practice; an SDK member that is missing from it is
  simply not reported, and the rule never infers what an unannotated body
  throws. `dart run tool/verify_sdk_table.dart` checks that every entry names a
  member that really exists in the installed SDKs and that the rule's own
  lookup can reach, so an entry can be wrong but never silently dead.
* **The table lists only `Exception`s, never `Error`s.** An `Error` reports a
  bug in the calling code, and the fix is to correct the call rather than to
  catch it, which is what `avoid_catching_errors` says. `Iterable.first`
  (`StateError`) and `list[0]` (`RangeError`) are therefore absent.
* **A closure ends the covered region.** A `try` outside a closure does not
  cover a call inside it, because the closure may run later.
* **A future that is not awaited escapes an enclosing `try`**, and is reported,
  since the error surfaces after the `try` has finished.
* **`empty_catch` looks at the syntax of the clause only.** A body that runs
  but does nothing useful (`if (false) {}`, an empty statement wrapped in a
  block) is not reported, and a comment always clears the report.

## Examples

Two example packages are wired to this one by path, and are the end-to-end
check that the plugin loads and fires:

```sh
cd example          # pure Dart: unhandled_throws and empty_catch
dart pub get        # against a hand-annotated @Throws function
dart analyze
```

```sh
cd example_flutter  # the real Flutter SDK and the real dart:io, against
flutter pub get     # the built-in table: int.parse, File.readAsString,
dart analyze lib/sdk_throws_example.dart   # MethodChannel.invokeMethod
```

Both deliberately contain violations, so `dart analyze` exits non-zero there.
Use `dart analyze`, not `flutter analyze`: the Flutter wrapper runs its own
bundled analysis and drops diagnostics that come from a third-party analyzer
plugin. Analyze the *file* rather than the directory in `example_flutter`, for
the same reason.

## Development

```sh
dart analyze                          # must be clean
dart test                             # rule matrices plus plugin registration
dart run tool/verify_sdk_table.dart   # every table entry resolves
dart run tool/benchmark.dart <dir>    # what the rules cost on real code
```

## License

MIT. See [LICENSE](LICENSE).

[analyzer plugin]: https://pub.dev/packages/analysis_server_plugin
