import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

typedef PhotoFindings = ({Uint8List imageBytes, List<String> labels});

class PhotoAnalysis {
  final _picker = ImagePicker();
  static const _channel = MethodChannel('donglgewi/photos');

  Future<PhotoFindings?> pickAndAnalyze(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      requestFullMetadata: false,
    );
    return image == null ? null : _analyze(image);
  }

  Future<PhotoFindings?> recoverOnAndroid() async {
    final result = await _picker.retrieveLostData();
    final error = result.exception;
    if (error != null) throw error;
    final files = result.files;
    return files == null || files.isEmpty ? null : _analyze(files.first);
  }

  Future<PhotoFindings> _analyze(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      List<String> labels;
      try {
        labels =
            await _channel
                .invokeListMethod<String>('analyze', image.path)
                .timeout(const Duration(seconds: 3), onTimeout: () => null) ??
            [];
      } on PlatformException {
        labels = [];
      }
      return (imageBytes: bytes, labels: labels);
    } finally {
      if (!kIsWeb && Platform.isIOS && image.name.startsWith('image_picker_')) {
        try {
          await File(image.path).delete();
        } on FileSystemException {
          // Failure to remove a temporary photo does not invalidate its result.
        }
      }
    }
  }
}
