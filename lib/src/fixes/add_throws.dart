import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:checked_exceptions/src/util/throws_analysis.dart';

/// The URI that declares the `@Throws` annotation.
const _annotationUri = 'package:checked_exceptions/checked_exceptions.dart';

/// A quick fix for `unhandled_throws` that declares the escaping exceptions on
/// the enclosing function.
///
/// The warning offers two ways out: catch the exception, or propagate it. This
/// automates the second. Propagating is the right default when the enclosing
/// function has no useful way to recover, and it is the tedious one to write
/// by hand, because it means naming every escaping type and importing both the
/// annotation and any exception class that is not already in scope.
///
/// The exceptions are taken from the same [ThrowsAnalysis] the rule used, so
/// the annotation this writes always discharges exactly the reported warning:
/// no more, which would silence something the developer was not told about,
/// and no less, which would leave the warning in place after applying the fix.
final class AddThrowsFix extends ResolvedCorrectionProducer {
  /// Creates the producer.
  AddThrowsFix({required super.context});

  /// The kind advertised to the editor.
  static const FixKind kind = FixKind(
    'checked_exceptions.addThrows',
    // Above the generic "ignore" fixes, which are the only competition on this
    // diagnostic, and which resolve nothing.
    50,
    "Annotate '{0}' with '@Throws'",
  );

  /// The name of the enclosing declaration, for the fix message.
  String _targetName = '';

  @override
  CorrectionApplicability get applicability =>
      // Each application edits a different declaration, but two calls in the
      // same function would produce overlapping edits to one annotation, so
      // this is deliberately not offered in bulk.
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [_targetName];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final analysis = ThrowsAnalysis(
      typeSystem: typeSystem,
      typeProvider: typeProvider,
    );

    // The diagnostic covers the whole call, so `coveringNode` is the node the
    // rule reported on. Falling back to `node` keeps the fix working when it
    // is invoked from a plain selection rather than from the diagnostic.
    final reported = coveringNode ?? node;
    final pending = analysis.unhandledAt(reported);
    if (pending.isEmpty) {
      return;
    }

    final target = annotatableDeclaration(reported);
    if (target == null) {
      // The call is inside a closure, whose exceptions do not escape through
      // the enclosing declaration. Annotating it would be a lie.
      return;
    }
    final name = _nameOf(target);
    if (name == null) {
      return;
    }
    _targetName = name;

    final existing = _throwsAnnotation(target);
    if (existing == null) {
      await _addAnnotation(builder, target, pending);
    } else {
      await _extendAnnotation(builder, existing, pending);
    }
  }

  /// Writes a new `@Throws({...})` above [target].
  ///
  /// The annotation goes on its own line, at the indentation of the
  /// declaration, after any documentation comment and existing metadata so
  /// that it reads as the last annotation rather than splitting a doc comment
  /// from what it documents.
  Future<void> _addAnnotation(
    ChangeBuilder builder,
    Declaration target,
    List<DartType> exceptions,
  ) async {
    final offset = _insertionOffset(target);
    final indent = _indentAt(offset);

    await builder.addDartFileEdit(file, (fileBuilder) {
      // Imports are added through the *file* builder, and the names they
      // resolve to must be known before the insertion is written.
      final throws = _importedName(
        fileBuilder,
        'Throws',
        Uri.parse(_annotationUri),
      );
      final types = _typeList(fileBuilder, exceptions);

      fileBuilder.addInsertion(offset, (builder) {
        builder.write('@$throws({$types})');
        builder.writeln();
        builder.write(indent);
      });
    });
  }

  /// Adds the missing types to an existing `@Throws({...})`.
  ///
  /// Editing the set in place keeps a single annotation on the declaration,
  /// which is what `declaredThrows` reads; a second `@Throws` would be ignored.
  Future<void> _extendAnnotation(
    ChangeBuilder builder,
    Annotation existing,
    List<DartType> exceptions,
  ) async {
    final literal = _exceptionSet(existing);
    if (literal == null) {
      return;
    }

    await builder.addDartFileEdit(file, (fileBuilder) {
      final types = _typeList(fileBuilder, exceptions);

      if (literal.elements.isEmpty) {
        // `@Throws({})`: there is nothing to separate the new entries from.
        fileBuilder.addSimpleInsertion(literal.leftBracket.end, types);
        return;
      }
      fileBuilder.addSimpleInsertion(literal.elements.last.end, ', $types');
    });
  }

  /// Returns the comma-separated type names to write, importing each one.
  ///
  /// Sorted so that the written order is stable and matches the order the
  /// warning message lists them in.
  String _typeList(DartFileEditBuilder builder, List<DartType> exceptions) {
    final names = <String>[];
    for (final type in exceptions) {
      final element = type.element;
      final uri = element is Element ? element.library?.uri : null;
      final name = type.getDisplayString();
      names.add(
        uri == null ? name : _importedName(builder, name, uri),
      );
    }
    names.sort();
    return names.join(', ');
  }

  /// Returns the name to write for [name] from [uri], adding an import when
  /// the library is not already in scope.
  ///
  /// Returns a prefixed name when the existing import uses a prefix, so the
  /// written annotation compiles either way.
  String _importedName(DartFileEditBuilder builder, String name, Uri uri) {
    final prefix = builder.importLibraryElement(uri, showName: name).prefix;
    return prefix == null || prefix.isEmpty ? name : '$prefix.$name';
  }

  /// Returns the existing `@Throws` annotation on [target], or `null`.
  Annotation? _throwsAnnotation(Declaration target) {
    for (final annotation in target.metadata) {
      if (annotation.name.name.split('.').last == 'Throws') {
        return annotation;
      }
    }
    return null;
  }

  /// Returns the set literal of an `@Throws({...})` annotation.
  SetOrMapLiteral? _exceptionSet(Annotation annotation) {
    final arguments = annotation.arguments?.arguments;
    if (arguments == null || arguments.isEmpty) {
      return null;
    }
    final first = arguments.first;
    final expression = first is NamedArgument
        ? first.argumentExpression
        : first;
    return expression is SetOrMapLiteral ? expression : null;
  }

  /// Returns the offset to insert a new annotation at.
  ///
  /// Uses the first token of the declaration *including* its metadata and
  /// documentation, then steps past them, so the annotation lands directly
  /// above the declaration rather than above its doc comment.
  int _insertionOffset(Declaration target) {
    final metadata = target.metadata;
    if (metadata.isNotEmpty) {
      return metadata.last.end + 1;
    }
    return target.firstTokenAfterCommentAndMetadata.offset;
  }

  /// Returns the whitespace that indents the line containing [offset].
  String _indentAt(int offset) {
    final content = unitResult.content;
    final lineStart = unitResult.lineInfo.getOffsetOfLine(
      unitResult.lineInfo.getLocation(offset).lineNumber - 1,
    );
    final line = content.substring(lineStart, offset);
    final indent = line.length - line.trimLeft().length;
    return line.substring(0, indent);
  }

  /// Returns the display name of [target], for the fix message.
  String? _nameOf(Declaration target) => switch (target) {
    MethodDeclaration(:final name) => name.lexeme,
    FunctionDeclaration(:final name) => name.lexeme,
    ConstructorDeclaration(:final name, :final typeName) =>
      name == null
          ? (typeName?.name ?? 'constructor')
          : '${typeName?.name ?? ''}.${name.lexeme}',
    _ => null,
  };
}
