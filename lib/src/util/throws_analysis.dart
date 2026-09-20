import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:checked_exceptions/src/util/annotations.dart';
import 'package:checked_exceptions/src/util/sdk_throws.dart';

/// Decides which exceptions escape a call unhandled.
///
/// Shared by the `unhandled_throws` rule, which reports them, and by the
/// `@Throws` quick fix, which declares them on the enclosing function. Both
/// must agree exactly: a fix that declared a different set than the rule
/// reported would either leave the warning in place or silence more than the
/// developer was told about.
///
/// Takes a [TypeSystem] and [TypeProvider] rather than a rule context so that
/// it can also run from a correction producer, which has no rule context.
final class ThrowsAnalysis {
  /// Creates an analysis that resolves types with [typeSystem] and
  /// [typeProvider].
  const ThrowsAnalysis({
    required this.typeSystem,
    required this.typeProvider,
  });

  final TypeSystem typeSystem;
  final TypeProvider typeProvider;

  /// Returns the exceptions [node] may throw that nothing handles, or an empty
  /// list when the call is fine.
  ///
  /// Returns an empty list for anything that is not a call to a target with
  /// declared exceptions, so a caller can treat "nothing to report" and "not
  /// interesting" alike.
  List<DartType> unhandledAt(AstNode node) {
    final call = _callOf(node);
    if (call == null) {
      return const [];
    }
    final declared =
        declaredThrows(call.callee) ?? sdkThrows(call.callee, typeProvider);
    if (declared == null || declared.isEmpty) {
      return const [];
    }
    return _unhandled(call.expression, declared);
  }

  /// Returns the call [node] denotes, or `null` when it is not one.
  ///
  /// Mirrors the node types the rule registers for, so that a fix invoked on a
  /// reported node resolves the same callee the rule did.
  ({Expression expression, Element? callee})? _callOf(AstNode node) {
    switch (node) {
      case MethodInvocation():
        return (
          expression: node,
          callee: normalizeElement(node.methodName.element),
        );
      case FunctionExpressionInvocation():
        return (expression: node, callee: normalizeElement(node.element));
      case InstanceCreationExpression():
        return (
          expression: node,
          callee: normalizeElement(node.constructorName.element),
        );
      case PropertyAccess():
        return _read(node, node.propertyName.element);
      case PrefixedIdentifier():
        return _read(node, node.identifier.element);
      case _:
        return null;
    }
  }

  /// Returns the property *read* [node] denotes, or `null` for a tear-off.
  ///
  /// Only a getter runs on being read. Naming a method without calling it
  /// produces a function value and runs nothing, so it cannot throw.
  ///
  /// The getter element is used directly rather than normalized to its
  /// variable: a `@Throws` written on a getter belongs to the getter, and
  /// normalizing would look for it on the synthetic field instead and never
  /// find it. An explicit getter has no variable to carry the annotation
  /// anyway. The fallback to the variable keeps an annotated *field* working,
  /// which is where a synthetic getter's annotation really does live.
  ({Expression expression, Element? callee})? _read(
    Expression node,
    Element? element,
  ) {
    if (element is! GetterElement) {
      return null;
    }
    final own = element.baseElement;
    if (declaredThrows(own) != null) {
      return (expression: node, callee: own);
    }
    return (expression: node, callee: normalizeElement(element));
  }

  /// Returns the declared types that are not handled at [node].
  ///
  /// Walks up from the call, letting enclosing `try` statements and a `@Throws`
  /// annotation on the enclosing function discharge types, and stops at the
  /// first function boundary.
  List<DartType> _unhandled(Expression node, List<DartType> declared) {
    // A future that is not awaited escapes any enclosing `try`, because the
    // error surfaces after the `try` has already completed.
    final escapesTry = _isUnawaitedFuture(node);

    final pending = [...declared];
    var child = node as AstNode;
    var current = node.parent;

    while (current != null && pending.isNotEmpty) {
      // Only the protected region of a `try` is covered by its catch clauses;
      // a call inside a `catch` or `finally` block is not.
      if (!escapesTry &&
          current is TryStatement &&
          identical(child, current.body)) {
        final clauses = current.catchClauses;
        pending.removeWhere(
          (type) => clauses.any((clause) => _catches(clause, type)),
        );
      }
      if (isFunctionBoundary(current)) {
        final propagated = declaredThrows(elementOfBoundary(current));
        if (propagated != null) {
          pending.removeWhere(
            (type) => propagated.any(
              (declared) => typeSystem.isSubtypeOf(type, declared),
            ),
          );
        }
        break;
      }
      child = current;
      current = current.parent;
    }
    return pending;
  }

  /// Whether [clause] catches [type].
  ///
  /// A bare `catch (e)` has no exception type and catches everything; an
  /// `on Object` clause is covered by the ordinary subtype check.
  bool _catches(CatchClause clause, DartType type) {
    final caught = clause.exceptionType?.type;
    if (caught == null) {
      return true;
    }
    return typeSystem.isSubtypeOf(type, caught);
  }

  /// Whether [node] produces a future that nobody awaits.
  bool _isUnawaitedFuture(Expression node) {
    final type = node.staticType;
    if (type == null || !(type.isDartAsyncFuture || type.isDartAsyncFutureOr)) {
      return false;
    }
    return node.parent is! AwaitExpression;
  }
}

/// Whether [node] ends the region that can handle a call inside it.
///
/// A function expression is a boundary because it runs at an unknown time, so
/// neither a surrounding `try` nor a surrounding `@Throws` applies to it. The
/// function expression that *is* the body of a declaration is not a boundary,
/// so that the declaration's own `@Throws` is still read.
bool isFunctionBoundary(AstNode node) {
  if (node is MethodDeclaration ||
      node is FunctionDeclaration ||
      node is ConstructorDeclaration) {
    return true;
  }
  return node is FunctionExpression &&
      node.parent is! FunctionDeclaration &&
      node.parent is! MethodDeclaration;
}

/// Returns the element declared by a function-boundary [node].
Element? elementOfBoundary(AstNode node) => switch (node) {
  MethodDeclaration(:final declaredFragment) => declaredFragment?.element,
  FunctionDeclaration(:final declaredFragment) => declaredFragment?.element,
  ConstructorDeclaration(:final declaredFragment) => declaredFragment?.element,
  _ => null,
};

/// Returns the declaration that a call inside [node] propagates out of, or
/// `null` when there is none that can carry an annotation.
///
/// This is the declaration the `@Throws` quick fix annotates. A closure is
/// skipped deliberately: writing `@Throws` on the enclosing *declaration*
/// would be a lie, because the closure's exceptions do not escape through it.
Declaration? annotatableDeclaration(AstNode node) {
  for (AstNode? current = node; current != null; current = current.parent) {
    if (!isFunctionBoundary(current)) {
      continue;
    }
    return switch (current) {
      MethodDeclaration() ||
      FunctionDeclaration() ||
      ConstructorDeclaration() => current as Declaration,
      // A closure boundary: its exceptions do not propagate to the enclosing
      // declaration, so there is nothing to annotate.
      _ => null,
    };
  }
  return null;
}
