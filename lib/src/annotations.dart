// The annotation consumed by the `checked_exceptions` analyzer plugin.
//
// The rules identify this annotation by its class name *and* by the fact that
// it is declared in the `checked_exceptions` package, so renaming the class or
// its field is a breaking change for `lib/src/util/annotations.dart`.

/// Declares the exception types that a function, method or constructor may
/// throw.
///
/// The `unhandled_throws` rule reports a call to an annotated target when a
/// declared type is neither caught at the call site nor re-declared by the
/// enclosing function.
///
/// ```dart
/// @Throws({FormatException})
/// int parse(String source) => int.parse(source);
/// ```
final class Throws {
  /// Creates a [Throws] annotation from a set of exception types.
  const Throws(this.exceptions);

  /// The declared exception types, written as type literals.
  ///
  /// Declared as `Set<Object>` rather than `Set<Type>` so that the annotation
  /// stays usable in constant contexts where the analyzer views a type literal
  /// as an `Object`. Entries that are not type literals are ignored by the
  /// rule.
  final Set<Object> exceptions;
}
