import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:checked_exceptions/src/util/cache.dart';

/// The name of the package that declares the annotation recognised by this
/// plugin.
const _annotationPackage = 'checked_exceptions';

/// Memoizes the `@Throws` lookup, keyed on the annotated element.
///
/// Answering this means evaluating a constant, which is the most expensive
/// thing the rules do, and the same element is asked about once per mention:
/// a call to an annotated function from a hundred places asks the same
/// question a hundred times. The answer depends only on the element.
final _throwsCache = ElementCache<Element, List<DartType>?>('throws');

/// Returns the exception types declared by a `@Throws` annotation on
/// [element], or `null` when [element] is not annotated.
///
/// Entries of the annotated set that are not type literals are skipped, so a
/// malformed annotation degrades to a smaller set rather than to a crash.
List<DartType>? declaredThrows(Element? element) {
  if (element == null) {
    return null;
  }
  return _throwsCache.of(element, () {
    final value = _annotationValue(element, 'Throws');
    if (value == null) {
      return null;
    }
    final exceptions = value.getField('exceptions')?.toSetValue();
    if (exceptions == null) {
      return null;
    }
    return [
      for (final exception in exceptions) ?exception.toTypeValue(),
    ];
  });
}

/// Returns the constant value of the annotation named [className] on
/// [element], or `null` when there is no such annotation.
///
/// The constant is only evaluated for an annotation that already *looks* like
/// the one being asked for. Evaluating a constant is expensive, and the
/// overwhelming majority of annotations in real code are somebody else's
/// (`@override`, `@immutable`, a code generator's); [_mayBe] rejects those
/// with a name comparison against the annotation's unevaluated element.
DartObject? _annotationValue(Element element, String className) {
  for (final annotation in element.metadata.annotations) {
    if (!_mayBe(annotation, className)) {
      continue;
    }
    final value = annotation.computeConstantValue();
    if (value != null && _isCheckedExceptionsAnnotation(value, className)) {
      return value;
    }
  }
  return null;
}

/// Whether [annotation] could be the `checked_exceptions` annotation named
/// [className], judged without evaluating it.
///
/// `@Throws({...})` resolves to the constructor of the annotation class, and
/// a `const` variable holding one resolves to a getter. The constructor case
/// is decided here in full, which is what covers ordinary code. The getter
/// case cannot be decided without knowing the variable's value, so it falls
/// through to evaluation rather than being rejected.
bool _mayBe(ElementAnnotation annotation, String className) {
  final element = annotation.element;
  if (element is ConstructorElement) {
    final enclosing = element.enclosingElement;
    return enclosing.name == className &&
        _isAnnotationLibrary(enclosing.library);
  }
  return true;
}

/// Whether [value] is an instance of the `checked_exceptions` class named
/// [className].
///
/// Matching on the package (rather than on the exact library URI) keeps the
/// rules working no matter which library of `checked_exceptions` re-exports
/// the annotation.
bool _isCheckedExceptionsAnnotation(DartObject value, String className) {
  final type = value.type;
  if (type is! InterfaceType) {
    return false;
  }
  final element = type.element;
  if (element.name != className) {
    return false;
  }
  return _isAnnotationLibrary(element.library);
}

/// Whether [library] belongs to the package that declares the annotation.
bool _isAnnotationLibrary(LibraryElement library) {
  final uri = library.uri;
  return uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == _annotationPackage;
}

/// Maps a resolved element onto the declaration the rules reason about.
///
/// Reading a field resolves to its synthetic getter, and members of a generic
/// class resolve to `*Member` wrappers; both are normalized away so that
/// elements can be compared by identity.
Element? normalizeElement(Element? element) {
  if (element == null) {
    return null;
  }
  if (element is PropertyAccessorElement) {
    return element.variable.baseElement;
  }
  return element.baseElement;
}
