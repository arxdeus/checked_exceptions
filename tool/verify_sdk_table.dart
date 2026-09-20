// Verifies the `unhandled_throws` SDK table against the *real* SDKs.
//
// The table is a hand-written list of SDK members. An entry naming a class or
// member that does not exist, or one the rule can never reach, would silently
// do nothing: no test fails, the lint simply never fires. This tool resolves
// every entry against the installed Dart and Flutter SDKs through the real
// analyzer element model and checks three things per entry:
//
//   1. the declaring class exists, and really declares the member;
//   2. `sdkThrows` returns a non-empty result for that member's element, so
//      the rule can actually reach it through its own lookup;
//   3. every exception it names resolves to a real type;
//   4. no entry names an `Error`, which `avoid_catching_errors` forbids
//      catching and which `@Throws` would be advice to catch.
//
// Run with `dart run tool/verify_sdk_table.dart`.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:checked_exceptions/src/util/sdk_throws.dart';

/// A scratch library that imports everything the table mentions.
///
/// Resolving a real file is what gives us the genuine SDK element model,
/// including `package:flutter`, rather than a reduced test approximation.
const _probeSource = '''
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

void main() {}
''';

/// The Flutter package the probe is written into.
///
/// The table names `package:flutter` members, so verifying it needs a package
/// that really depends on Flutter: this package's own `example_flutter`. It is
/// reached relative to *this file* rather than to the current directory, so
/// the tool works whatever directory it is run from.
String _probeDirectory() {
  // tool/verify_sdk_table.dart -> tool -> the package root.
  final packageRoot = Directory(Platform.script.toFilePath()).parent.parent;
  return '${packageRoot.path}/example_flutter/lib';
}

Future<void> main() async {
  final probe = File('${_probeDirectory()}/_verify_probe.dart')
    ..writeAsStringSync(_probeSource);

  try {
    final collection = AnalysisContextCollection(
      includedPaths: [probe.path],
    );
    final session = collection.contextFor(probe.path).currentSession;
    final resolved = await session.getResolvedUnit(probe.path);
    if (resolved is! ResolvedUnitResult) {
      stderr.writeln('FAIL: could not resolve the probe library.');
      exit(1);
    }

    final failures = _verify(resolved);
    if (failures.isEmpty) {
      final count = sdkTableEntries.length;
      print('OK: all $count SDK table entries resolve and are reachable.');
      return;
    }
    for (final failure in failures) {
      print('FAIL  $failure');
    }
    print('');
    print('${failures.length} of ${sdkTableEntries.length} entries failed.');
    exit(1);
  } finally {
    if (probe.existsSync()) {
      probe.deleteSync();
    }
  }
}

/// Returns a description of every table entry that does not check out.
List<String> _verify(ResolvedUnitResult resolved) {
  final typeProvider = resolved.typeProvider;
  final scope = resolved.libraryElement.firstFragment.importedLibraries;
  final failures = <String>[];

  for (final entry in sdkTableEntries) {
    final label = entry.owner == null
        ? '${entry.kind} ${entry.member}'
        : '${entry.kind} ${entry.owner}.${entry.member}';

    final element = _lookUp(entry, scope);
    if (element == null) {
      failures.add('$label -- no such class or member in the installed SDKs');
      continue;
    }

    final thrown = sdkThrows(element, typeProvider);
    if (thrown == null || thrown.isEmpty) {
      failures.add('$label -- exists, but the rule never matches it');
      continue;
    }
    if (thrown.length != entry.exceptions.length) {
      failures.add(
        '$label -- names ${entry.exceptions.length} exceptions but only '
        '${thrown.length} resolve',
      );
    }
    for (final type in thrown) {
      if (_isError(type, typeProvider)) {
        failures.add(
          '$label -- declares ${type.getDisplayString()}, which is an Error; '
          'avoid_catching_errors forbids catching it, so @Throws must not '
          'ask callers to',
        );
      }
    }
  }
  return failures;
}

/// Whether [type] is a subtype of `Error`.
///
/// The check goes through the real `dart:core` `Error`, so a class that only
/// happens to be *named* something like an error is unaffected.
bool _isError(DartType type, TypeProvider typeProvider) {
  final error = typeProvider.objectElement.library.getClass('Error');
  if (error == null || type is! InterfaceType) {
    return false;
  }
  return type.element == error ||
      type.allSupertypes.any((s) => s.element == error);
}

/// Resolves the element a table entry describes, or `null` when there is none.
Element? _lookUp(SdkTableEntry entry, List<LibraryElement> scope) {
  if (entry.kind == 'toplevel') {
    for (final library in scope) {
      final found = library.exportNamespace.get2(entry.member);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  final owner = _findClass(entry.owner!, scope);
  if (owner == null) {
    return null;
  }
  // A getter and a method are distinct elements, so try both; `orElse` is not
  // relevant here, only whether the SDK declares the name at all.
  return owner.getMethod(entry.member) ??
      owner.getGetter(entry.member) ??
      _inherited(owner, entry.member);
}

/// Returns the class named [name], including private ones reached through the
/// supertypes of the classes in scope.
InterfaceElement? _findClass(String name, List<LibraryElement> scope) {
  for (final library in scope) {
    final found = library.exportNamespace.get2(name);
    if (found is InterfaceElement) {
      return found;
    }
  }
  // A private base such as `_UnicodeSubsetDecoder` is not exported, so look for
  // it among the supertypes of everything that is.
  for (final library in scope) {
    for (final element in library.exportNamespace.definedNames2.values) {
      if (element is! InterfaceElement) {
        continue;
      }
      for (final supertype in element.allSupertypes) {
        if (supertype.element.name == name) {
          return supertype.element;
        }
      }
    }
  }
  return null;
}

/// Returns [name] as declared by a supertype of [owner].
Element? _inherited(InterfaceElement owner, String name) {
  for (final supertype in owner.allSupertypes) {
    final element = supertype.element;
    final found = element.getMethod(name) ?? element.getGetter(name);
    if (found != null) {
      return found;
    }
  }
  return null;
}
