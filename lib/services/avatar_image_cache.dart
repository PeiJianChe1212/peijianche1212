import 'dart:io';

import 'package:flutter/painting.dart';

class AvatarImageCache {
  const AvatarImageCache._();

  /// Evicts only the bitmap backed by [path]. This is intentionally scoped;
  /// other live images remain cached.
  static bool evictPath(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return false;
    return imageCache.evict(FileImage(File(clean)), includeLive: true);
  }
}
