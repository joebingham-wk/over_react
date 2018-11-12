import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

import 'package:over_react/src/builder/generation/declaration_parsing.dart';
import 'package:over_react/src/builder/generation/impl_generation.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';


Builder overReactBuilder(BuilderOptions options) => new OverReactBuilder();

class OverReactBuilder implements Builder {
  OverReactBuilder();

  static const _outputExtension = '.overReact.g.dart';

  /// Converts [id] to a "package:" URI.
  ///
  /// This will return a schemeless URI if [id] doesn't represent a library in
  /// `lib/`.
  static Uri idToPackageUri(AssetId id) {
    if (!id.path.startsWith('lib/')) {
      return new Uri(path: id.path);
    }

    return new Uri(scheme: 'package',
        path: p.url.join(id.package, id.path.replaceFirst('lib/', '')));
  }

  /// Generates the part of directive for the build output from the build target
  /// library.
  String _generatePartOfDirective(LibraryElement entryLib, AssetId inputId) {
    var outputBuffer = StringBuffer('part of ');
    var hasLibraryDirective = false;
    for (final directive in entryLib.definingCompilationUnit.computeNode().directives) {
      if (directive.keyword.toString().contains('library')) {
        hasLibraryDirective = true;
        var token = directive.keyword.next;
        while (!(token.toString().contains(';'))) {
          outputBuffer.write(token.toString());
          token = token.next;
        }
        break;
      }
    };

    if (!hasLibraryDirective) {
      // then the part of directive will just have the parent file name
      outputBuffer.write('\'${inputId.pathSegments.last}\'');
    }
    outputBuffer.writeln(';\n');
    return outputBuffer.toString();
  }

  String _generateForFile(AssetId inputId, String primaryInputContents, CompilationUnit resolvedUnit) {
    void _logNoDeclarations() {
      log.fine(
          'There were no declarations found for file: ${inputId
              .toString()}');
    }

    var sourceFile = new SourceFile.fromString(
        primaryInputContents, url: idToPackageUri(inputId));

    ImplGenerator generator;
    if (ParsedDeclarations.mightContainDeclarations(primaryInputContents)) {
      var declarations = new ParsedDeclarations(resolvedUnit, sourceFile, log);

      if (!declarations.hasErrors && declarations.hasDeclarations) {
        generator = new ImplGenerator(log, sourceFile)..generate(declarations);
      } else {
        if (declarations.hasErrors) {
          log.severe(
              'There was an error parsing the file declarations for file: ${inputId.toString()}');
        }
        if (!declarations.hasDeclarations) {
          _logNoDeclarations();
        }
      }
    } else {
      _logNoDeclarations();
    }
    return generator?.outputContentsBuffer?.toString() ?? '';
  }

  @override
  Future build(BuildStep buildStep) async {
    // Don't build on part files
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    final inputId = await buildStep.inputId;
    final outputId = buildStep.inputId.changeExtension(_outputExtension);
    final entryLib = await buildStep.inputLibrary;


    // Get list of compilation units for each part in this library
    final compUnits = [
      [entryLib.definingCompilationUnit],
      entryLib.parts.expand((p) => [p]),
    ].expand((t) => t).toList();

    var contentBuffer = new StringBuffer();
    for (final unit in compUnits) {
      log.fine('Generating implementations for file: ${unit.name}');
      // unit.uri is null for the base library file
      final assetId = AssetId.resolve(unit.uri ?? unit.name, from: inputId);

      // Only generate on part files which were not generated by this builder and
      // which can be read.
      if (!assetId.toString().contains(_outputExtension) && await buildStep.canRead(assetId)) {
        final resolvedUnit = unit.computeNode();
        final inputContents = await buildStep.readAsString(assetId);
        contentBuffer.write(_generateForFile(assetId, inputContents, resolvedUnit));
      }
    }

    if (contentBuffer.isNotEmpty) {
      var outputBuffer = new StringBuffer(_generatePartOfDirective(entryLib, inputId));
      outputBuffer.write(contentBuffer);
      await buildStep.writeAsString(outputId, outputBuffer.toString());
    } else {
      log.fine('No output generated for file: ${inputId.toString()}');
    }
  }

  @override
  Map<String, List<String>> get buildExtensions =>
      {'.dart': const [_outputExtension]};
}
