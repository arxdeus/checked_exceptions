import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:checked_exceptions/src/plugin.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'src/annotations_source.dart';
import 'src/fix_harness.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddThrowsFixTest);
  });
}

/// The exception hierarchy and annotated targets shared by the fixtures.
const _preamble = '''
import 'package:checked_exceptions/checked_exceptions.dart';

class Boom implements Exception {}

class Other implements Exception {}

@Throws({Boom})
void risky() {}

@Throws({Boom, Other})
void riskyTwice() {}

class Resource {
  @Throws({Boom})
  Resource();

  @Throws({Boom})
  void method() {}
}
''';

@reflectiveTest
class AddThrowsFixTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage(
      'checked_exceptions',
    ).addFile('lib/checked_exceptions.dart', annotationsSource);
    rule = UnhandledThrowsRule();
    registerPluginFixes(CheckedExceptionsPlugin());
    super.setUp();
  }

  /// Asserts the fix turns [body] into [expected], both appended to the shared
  /// preamble.
  Future<void> assertFix(String body, String expected) =>
      assertFixProduces('$_preamble\n$body', '$_preamble\n$expected');

  // --- Adding a new annotation. ---

  Future<void> test_addsToFunction() async {
    await assertFix(
      r'''
void f() {
  risky();
}
''',
      r'''
@Throws({Boom})
void f() {
  risky();
}
''',
    );
  }

  Future<void> test_addsToExpressionBodiedFunction() async {
    await assertFix(
      r'''
void f() => risky();
''',
      r'''
@Throws({Boom})
void f() => risky();
''',
    );
  }

  Future<void> test_addsBothUnhandledTypes() async {
    await assertFix(
      r'''
void f() {
  riskyTwice();
}
''',
      r'''
@Throws({Boom, Other})
void f() {
  riskyTwice();
}
''',
    );
  }

  Future<void> test_addsToMethod_indented() async {
    await assertFix(
      r'''
class Caller {
  void f() {
    risky();
  }
}
''',
      r'''
class Caller {
  @Throws({Boom})
  void f() {
    risky();
  }
}
''',
    );
  }

  Future<void> test_addsToConstructor() async {
    await assertFix(
      r'''
class Caller {
  Caller() {
    risky();
  }
}
''',
      r'''
class Caller {
  @Throws({Boom})
  Caller() {
    risky();
  }
}
''',
    );
  }

  Future<void> test_addsForConstructorCall() async {
    await assertFix(
      r'''
void f() {
  Resource();
}
''',
      r'''
@Throws({Boom})
void f() {
  Resource();
}
''',
    );
  }

  Future<void> test_addsForMethodCall() async {
    await assertFix(
      r'''
void f(Resource resource) {
  resource.method();
}
''',
      r'''
@Throws({Boom})
void f(Resource resource) {
  resource.method();
}
''',
    );
  }

  Future<void> test_keepsDocCommentAboveAnnotation() async {
    await assertFix(
      r'''
/// Does a thing.
void f() {
  risky();
}
''',
      r'''
/// Does a thing.
@Throws({Boom})
void f() {
  risky();
}
''',
    );
  }

  Future<void> test_addsAfterExistingAnnotation() async {
    await assertFix(
      r'''
@deprecated
void f() {
  risky();
}
''',
      r'''
@deprecated
@Throws({Boom})
void f() {
  risky();
}
''',
    );
  }

  Future<void> test_addsToLocalFunctionDeclaration() async {
    // A local function is a real declaration, so it is the parent function to
    // annotate. Its own callers then see the obligation.
    await assertFix(
      r'''
void outer() {
  void inner() {
    risky();
  }

  inner();
}
''',
      r'''
void outer() {
  @Throws({Boom})
  void inner() {
    risky();
  }

  inner();
}
''',
    );
  }

  Future<void> test_addsToGetter() async {
    // Annotating a getter propagates to whoever reads it, so this is a real
    // fix rather than a way to lose the obligation.
    await assertFix(
      r'''
class Caller {
  int get value {
    risky();
    return 0;
  }
}
''',
      r'''
class Caller {
  @Throws({Boom})
  int get value {
    risky();
    return 0;
  }
}
''',
    );
  }

  // --- Extending an existing annotation. ---

  Future<void> test_extendsExistingAnnotation() async {
    await assertFix(
      r'''
@Throws({Other})
void f() {
  risky();
}
''',
      r'''
@Throws({Other, Boom})
void f() {
  risky();
}
''',
    );
  }

  Future<void> test_extendsWithOnlyTheMissingType() async {
    // `Boom` is already declared, so only `Other` is added.
    await assertFix(
      r'''
@Throws({Boom})
void f() {
  riskyTwice();
}
''',
      r'''
@Throws({Boom, Other})
void f() {
  riskyTwice();
}
''',
    );
  }

  // --- Partial handling. ---

  Future<void> test_declaresOnlyTypeNotCaught() async {
    // `Boom` is caught, so the annotation must name `Other` alone.
    await assertFix(
      r'''
void f() {
  try {
    riskyTwice();
  } on Boom {}
}
''',
      r'''
@Throws({Other})
void f() {
  try {
    riskyTwice();
  } on Boom {}
}
''',
    );
  }

  // --- Not offered. ---

  Future<void> test_noFixInsideClosure() async {
    // The closure runs at an unknown time, so its exceptions do not escape
    // through `f`. Annotating `f` would be a lie.
    await assertNoFix('''
$_preamble
void run(void Function() callback) {}

void f() {
  run(() {
    risky();
  });
}
''');
  }

  // --- Message. ---

  Future<void> test_messageNamesTheTarget() async {
    final message = await fixMessage('''
$_preamble
void handler() {
  risky();
}
''');
    expect(message, "Annotate 'handler' with '@Throws'");
  }
}
