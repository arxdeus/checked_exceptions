import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:checked_exceptions/main.dart' as entry_point;
import 'package:checked_exceptions/src/fixes/add_throws.dart';
import 'package:checked_exceptions/src/plugin.dart';
import 'package:checked_exceptions/src/rules/empty_catch.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';
import 'package:test/test.dart';

void main() {
  group('CheckedExceptionsPlugin', () {
    test('exposes a plugin instance from the generated entry point', () {
      // The analysis server generates code that imports `lib/main.dart` and
      // reads this top-level variable, so its name and type are part of the
      // contract with the server.
      expect(entry_point.plugin, isA<CheckedExceptionsPlugin>());
      expect(entry_point.plugin.name, 'checked_exceptions');
    });

    test('registers exactly the two rules, all as warnings', () {
      final registry = _RecordingRegistry();
      CheckedExceptionsPlugin().register(registry);

      // Exact equality, not `containsAll`: registering an extra or duplicate
      // rule is a defect this test must catch.
      expect(registry.warningRuleNames, ['empty_catch', 'unhandled_throws']);

      // Warning rules are on as soon as the plugin is enabled; lint rules
      // would silently require opt-in from every consumer.
      expect(registry.lintRuleNames, isEmpty);
    });

    test('registers a quick fix for each rule that has one', () {
      // A fix that is implemented but never registered is invisible in the
      // IDE, and no producer-level test would notice.
      final registry = _RecordingRegistry();
      CheckedExceptionsPlugin().register(registry);

      // The *generator* is asserted, not just the code. Recording only the
      // code would keep passing if a rule were wired to somebody else's
      // producer, which would offer the wrong fix with no test noticing.
      expect(registry.fixes, [('unhandled_throws', AddThrowsFix.new)]);
    });

    test('declares one diagnostic code per rule, matching the rule name', () {
      // The code's name is what appears in
      // `// ignore: checked_exceptions/<name>` and in the `diagnostics:`
      // section, so it must track the rule name.
      for (final rule in [EmptyCatchRule(), UnhandledThrowsRule()]) {
        expect(rule.diagnosticCodes, hasLength(1));
        final code = rule.diagnosticCodes.single;
        expect(code.lowerCaseName, rule.name);
        expect(code.severity, DiagnosticSeverity.WARNING);
      }
    });

    test('reuses one diagnostic code instance per rule', () {
      // The analysis server matches diagnostics by code identity. Handing out
      // a fresh instance per call breaks `// ignore:` suppression, which no
      // rule-behaviour test would notice.
      expect(
        identical(
          EmptyCatchRule().diagnosticCode,
          EmptyCatchRule().diagnosticCode,
        ),
        isTrue,
      );
      expect(
        identical(
          UnhandledThrowsRule().diagnosticCode,
          UnhandledThrowsRule().diagnosticCode,
        ),
        isTrue,
      );
    });
  });
}

/// A [PluginRegistry] that records what a plugin registers, in order.
///
/// Used instead of the real registry so that the assertions cannot be
/// satisfied by rules some other test already registered globally.
final class _RecordingRegistry implements PluginRegistry {
  final List<String> warningRuleNames = [];
  final List<String> lintRuleNames = [];

  /// Each registered fix, as the diagnostic's name paired with the generator
  /// the plugin supplied for it.
  final List<(String, Object?)> fixes = [];

  @override
  void registerWarningRule(AbstractAnalysisRule rule) =>
      warningRuleNames.add(rule.name);

  @override
  void registerLintRule(AbstractAnalysisRule rule) =>
      lintRuleNames.add(rule.name);

  @override
  void registerFixForRule(DiagnosticCode code, Object? generator) =>
      fixes.add((code.lowerCaseName, generator));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}
