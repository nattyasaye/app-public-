import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PickedProjectPackageFile {
  final String filename;
  final String content;

  const PickedProjectPackageFile({
    required this.filename,
    required this.content,
  });
}

class ProjectPackageIoUnavailableException implements Exception {
  final String message;
  const ProjectPackageIoUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Platform file sharing and native Android SAF file-picking service for
/// portable `.daywellproject` packages.
class ProjectPackageIoService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.personalmanagement/project_package',
  );

  /// Writes [jsonContent] to a temporary `.daywellproject` file and invokes
  /// the OS share sheet so the user can save or transfer it.
  static Future<void> exportPackageFile({
    required String filename,
    required String jsonContent,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(p.join(tempDir.path, filename));
      await file.writeAsString(jsonContent, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: filename,
      );
    } on MissingPluginException {
      await Share.share(jsonContent, subject: filename);
    } on PlatformException {
      await Share.share(jsonContent, subject: filename);
    }
  }

  /// Launches Android's native `ACTION_OPEN_DOCUMENT` picker via [MethodChannel]
  /// and returns the selected `.daywellproject` filename and UTF-8 content, or
  /// `null` if the user cancelled.
  static Future<PickedProjectPackageFile?> pickProjectPackageFile() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'pickProjectPackageFile',
      );
      if (result == null) return null;
      if (result is! Map) {
        throw const FormatException(
          'Unexpected response from Android file picker.',
        );
      }
      final filename = result['filename']?.toString() ?? 'project.daywellproject';
      final content = result['content']?.toString();
      if (content == null) {
        throw const FormatException('Selected file returned no content.');
      }
      return PickedProjectPackageFile(
        filename: filename,
        content: content,
      );
    } on MissingPluginException {
      throw const ProjectPackageIoUnavailableException(
        'Native file picker is available on Android. Paste the .daywellproject JSON below to import.',
      );
    }
  }
}
