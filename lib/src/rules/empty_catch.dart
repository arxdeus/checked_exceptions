import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:checked_exceptions/src/util/annotations.dart';

/// Reports `catch` clauses that swallow the exception: the body does nothing,
/// does not rethrow, and never looks at the caught exception.
///
/// This is deliberately stricter than the built-in `empty_catches` lint, which
/// is satisfied by naming the exception `_`. Naming a variable does not handle
/// anything, and it is exactly what happens when a `@Throws` call is "handled"
/// only to make another diagnostic go away.
final class EmptyCatchRule extends AnalysisRule {
  /// Creates the rule.
  EmptyCatchRule()
    : super(
        name: 'empty_catch',
        description:
            'Catch clauses should not silently swallow the caught exception.',
      );

  /// The diagnostic reported by this rule.
  ///
  /// Declared as a single `static const` so that the analysis server can match
  /// the code, which is what makes `// ignore: checked_exceptions/empty_catch`
  /// work.
  static const LintCode code = LintCode(
    'empty_catch',
    'This clause catches {0} and does nothing with it: the body is empty, '
        'nothing is rethrown, and the caught exception is never used.',
    correctionMessage:
        "Try handling the exception, rethrowing it with 'rethrow', or "
        'explaining in a comment inside the block why it can be ignored.',
    uniqueName: 'LintCode.empty_catch',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCatchClause(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitCatchClause(CatchClause node) {
    if (!_isEmpty(node.body)) {
      return;
    }
    // A comment inside the braces is a deliberate "ignored on purpose" marker,
    // and it is the documented way out of this rule.
    if (_hasComment(node.body)) {
      return;
    }

    rule.reportAtNode(node, arguments: [_what(node)]);
  }

  /// Whether [block] has no effect at all.
  ///
  /// `;` is a statement in the AST but does nothing, so a body made only of
  /// empty statements counts as empty.
  bool _isEmpty(Block block) =>
      block.statements.every((statement) => statement is EmptyStatement);

  /// Whether any comment is written inside the braces of [block].
  bool _hasComment(Block block) {
    for (
      var token = block.leftBracket.next;
      token != null && token != block.rightBracket.next;
      token = token.next
    ) {
      if (token.precedingComments != null) {
        return true;
      }
    }
    return false;
  }

  /// A description of what [node] catches, used in the message.
  ///
  /// A clause that swallows exceptions declared by a `@Throws` call in the
  /// protected body is called out separately: there the swallowing is not just
  /// sloppy, it defeats a declaration the callee made on purpose.
  String _what(CatchClause node) {
    final caught = node.exceptionType?.type?.getDisplayString();
    final subject = caught == null ? 'every exception' : "'$caught'";
    final parent = node.parent;
    if (parent is TryStatement && _containsThrowsCall(parent.body)) {
      return '$subject declared by a @Throws call';
    }
    return subject;
  }

  /// Whether [body] contains a call to a `@Throws`-annotated target.
  bool _containsThrowsCall(Block body) {
    final finder = _ThrowsCallFinder();
    body.accept(finder);
    return finder.found;
  }
}

/// Finds whether a subtree calls anything annotated with `@Throws`.
final class _ThrowsCallFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _check(node.element);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  void _check(Element? element) {
    if (found) {
      return;
    }
    final declared = declaredThrows(normalizeElement(element));
    if (declared != null && declared.isNotEmpty) {
      found = true;
    }
  }
}
