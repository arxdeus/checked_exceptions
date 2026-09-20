import 'dart:io';
import 'dart:isolate';

/// The real `checked_exceptions` annotation source, for writing into test
/// fixtures.
///
/// Read from `lib/src/annotations.dart` rather than copied, because the rules
/// match the annotation by class name, by field name and by package. A
/// hand-written copy could drift from the real declaration, and the tests
/// would keep passing while the rules silently stopped firing for real users.
///
/// Resolved once per test isolate, and synchronously, so that it can be used
/// from `setUp`.
final String annotationsSource = _readAnnotations();

String _readAnnotations() {
  final uri = Isolate.resolvePackageUriSync(
    Uri.parse('package:checked_exceptions/src/annotations.dart'),
  );
  if (uri == null) {
    throw StateError(
      'Cannot resolve package:checked_exceptions/src/annotations.dart. '
      'Run `dart pub get` before running the tests.',
    );
  }
  return File.fromUri(uri).readAsStringSync();
}
