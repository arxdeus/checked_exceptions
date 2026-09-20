import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:checked_exceptions/src/util/throws_analysis.dart';

/// Reports calls to `@Throws`-annotated targets whose declared exceptions are
/// neither caught at the call site nor re-declared by the enclosing function.
///
/// A table of SDK members that are known to throw (`int.parse`, `jsonDecode`,
/// `Iterable.first`, ...) is treated exactly as if those members carried a
/// `@Throws` annotation, so the common sources of an uncaught
/// `FormatException` or `StateError` are covered without annotating the SDK.
final class UnhandledThrowsRule extends AnalysisRule {
  /// Creates the rule.
  UnhandledThrowsRule()
    : super(
        name: 'unhandled_throws',
        description:
            'Calls to @Throws-annotated functions should be caught or '
            'propagated with @Throws.',
      );

  /// The diagnostic reported by this rule.
  ///
  /// Declared as a single `static const` so that the analysis server can match
  /// the code, which is what makes `// ignore: checked_exceptions/unhandled_throws`
  /// work, and what the `@Throws` quick fix registers against.
  static const LintCode code = LintCode(
    'unhandled_throws',
    'This call may throw {0}, which is neither caught here nor declared by '
        'the enclosing function.',
    correctionMessage:
        "Try catching it with 'try'/'catch', or annotating the enclosing "
        "function with '@Throws'.",
    uniqueName: 'LintCode.unhandled_throws',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addMethodInvocation(this, visitor)
      ..addFunctionExpressionInvocation(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      // `list.first` is a property read, not a call, so the getters of the SDK
      // table need their own entry points.
      ..addPropertyAccess(this, visitor)
      ..addPrefixedIdentifier(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, RuleContext context)
    : analysis = ThrowsAnalysis(
        typeSystem: context.typeSystem,
        typeProvider: context.typeProvider,
      );

  final AnalysisRule rule;

  /// The shared decision procedure, which the quick fix reuses so that the two
  /// always agree on which exceptions escape.
  final ThrowsAnalysis analysis;

  @override
  void visitMethodInvocation(MethodInvocation node) => _check(node);

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      _check(node);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _check(node);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _check(node);

  /// Reports [node] when it may throw something nothing handles.
  void _check(Expression node) {
    final pending = analysis.unhandledAt(node);
    if (pending.isEmpty) {
      return;
    }
    final names = [for (final type in pending) type.getDisplayString()]..sort();
    rule.reportAtNode(node, arguments: [names.join(', ')]);
  }
}
