import 'package:analyzer_plugin_toolkit_testing/analyzer_plugin_toolkit_testing.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:checked_exceptions/src/plugin.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'src/annotations_source.dart';
import 'src/mock_sdk_extensions.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddThrowsSdkFixTest);
  });
}

/// Fixes for the SDK table, where the annotation and often the exception class
/// both have to be imported.
@reflectiveTest
class AddThrowsSdkFixTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage(
      'checked_exceptions',
    ).addFile('lib/checked_exceptions.dart', annotationsSource);
    addMockFlutter();
    rule = UnhandledThrowsRule();
    registerPluginFixes(CheckedExceptionsPlugin());
    super.setUp();
    augmentMockSdk();
  }

  Future<void> test_addsAnnotationAndItsImport() async {
    // Neither `@Throws` nor its library is in scope, so the fix must add the
    // import as well as the annotation.
    await assertFixProduces(
      r'''
int f(String s) => int.parse(s);
''',
      r'''
import 'package:checked_exceptions/checked_exceptions.dart';

@Throws({FormatException})
int f(String s) => int.parse(s);
''',
    );
  }

  Future<void> test_noFixForErrorThrowingMember() async {
    // `Iterable.first` throws a `StateError`, which is not tabled, so there is
    // no warning here and therefore nothing to fix.
    await assertNoLintAndNoFix(r'''
int f(List<int> xs) => xs.first;
''');
  }

  Future<void> test_importsExceptionFromAnotherLibrary() async {
    // `FileSystemException` lives in `dart:io`, which is already imported
    // here, so only the annotation's library is added.
    await assertFixProduces(
      r'''
import 'dart:io';

Future<String> f(File file) => file.readAsString();
''',
      r'''
import 'dart:io';

import 'package:checked_exceptions/checked_exceptions.dart';

@Throws({FileSystemException})
Future<String> f(File file) => file.readAsString();
''',
    );
  }

  Future<void> test_addsBothFlutterExceptions() async {
    await assertFixProduces(
      r'''
import 'package:flutter/services.dart';

Future<Object?> f(MethodChannel c) => c.invokeMethod<Object>('go');
''',
      r'''
import 'package:checked_exceptions/checked_exceptions.dart';
import 'package:flutter/services.dart';

@Throws({MissingPluginException, PlatformException})
Future<Object?> f(MethodChannel c) => c.invokeMethod<Object>('go');
''',
    );
  }
}
