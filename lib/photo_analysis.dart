import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PhotoAnalysis {
  final _picker = ImagePicker();
  static const _channel = MethodChannel('donglgewi/photos');

  Future<({Uint8List imageBytes, List<String> labels})?>
  pickAndAnalyze() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    try {
      final bytes = await image.readAsBytes();
      List<String> labels;
      try {
        labels =
            await _channel.invokeListMethod<String>('analyze', image.path) ??
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
