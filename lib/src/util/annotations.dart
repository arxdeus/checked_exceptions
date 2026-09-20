import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin_toolkit/analyzer_plugin_toolkit.dart';

/// Finds this package's annotation, matching on the declaring package so that
/// a same-named `Throws` from somewhere else cannot drive the rules.
///
/// Shared by both rules and by the quick fix, so that an element is inspected
/// once no matter how many of them ask about it: the finder memoizes per
/// element, and the memo table lives as long as the element does.
final _annotations = AnnotationFinder('checked_exceptions');

/// Returns the exception types declared by a `@Throws` annotation on
/// [element], or `null` when [element] is not annotated.
///
/// Entries of the annotated set that are not type literals are skipped, so a
/// malformed annotation degrades to a smaller set rather than to a crash.
List<DartType>? declaredThrows(Element? element) {
  final value = _annotations.valueOf(element, 'Throws');
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
}
