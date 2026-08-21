import '../models/echo_item.dart';

class EchoAlbumService {
  const EchoAlbumService._();

  /// Keeps the current list format and the legacy single imagePath format.
  /// Missing files are intentionally retained so the UI can show a safe tile.
  static List<String> imagePathsFor(Iterable<EchoItem> items) {
    final paths = <String>[];
    final seen = <String>{};
    for (final item in items) {
      for (final raw in [...item.imagePaths, item.imagePath]) {
        final path = raw.trim();
        if (path.isNotEmpty && seen.add(path)) paths.add(path);
      }
    }
    return paths;
  }
}
