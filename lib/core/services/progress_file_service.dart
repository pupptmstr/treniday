import 'dart:convert';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'file_download.dart';

/// Moves a progress file out of the app and back in: the thin layer over the
/// plugins (what the file holds is `ProgressFile`'s, the merge
/// `ProgressMerge`'s).
abstract final class ProgressFileService {
  static const String _mimeType = 'application/json';

  /// Offers [text] as the file [fileName]: the share sheet on a phone and in
  /// a phone's browser (save to Files, send to yourself), a download in a
  /// computer's browser. [origin] anchors the share sheet's popover on iPad.
  static Future<void> export(
    String text,
    String fileName, {
    Rect? origin,
    String? subject,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final phone = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (kIsWeb && !phone) {
      downloadFile(bytes, fileName, _mimeType);
      return;
    }
    // In a phone's browser share_plus falls back to a download by itself
    // when the browser cannot share files.
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: _mimeType)],
      fileNameOverrides: [fileName],
      subject: subject,
      sharePositionOrigin: origin,
    ));
  }

  /// The text of the file the user picks; null when they cancel. Throws a
  /// [FormatException] for a file that is not text.
  static Future<String?> pick() async {
    final file = await openFile(acceptedTypeGroups: [_typeGroup]);
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }

  /// JSON files on iOS (by their type) and in the browser (by the
  /// extension). On Android any file: the picker filters by MIME type, and a
  /// file saved from a messenger often comes as `application/octet-stream`;
  /// what is not a progress file is told apart when it is read.
  static XTypeGroup get _typeGroup {
    if (kIsWeb) {
      return const XTypeGroup(extensions: ['json']);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const XTypeGroup(uniformTypeIdentifiers: ['public.json']);
    }
    return const XTypeGroup();
  }
}
