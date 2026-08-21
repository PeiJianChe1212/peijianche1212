import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/echo_item.dart';
import 'package:peijianche_app/services/echo_album_service.dart';
import 'package:peijianche_app/services/echo_profile_storage_service.dart';

void main() {
  test('album combines current imagePaths and legacy imagePath safely', () {
    final item = EchoItem(
      id: 'echo',
      characterId: 'role',
      content: '一段记录',
      imagePaths: const ['/new-a.jpg', '/shared.jpg'],
      imagePath: '/legacy.jpg',
      createdAt: DateTime.utc(2026, 8, 21),
      sourceType: EchoSourceType.manual,
    );
    final duplicate = EchoItem(
      id: 'echo-2',
      characterId: 'role',
      content: '另一段记录',
      imagePaths: const ['/shared.jpg'],
      createdAt: DateTime.utc(2026, 8, 21),
      sourceType: EchoSourceType.manual,
    );

    expect(EchoAlbumService.imagePathsFor([item, duplicate]), [
      '/new-a.jpg',
      '/shared.jpg',
      '/legacy.jpg',
    ]);
  });

  test('blank role and user signatures share the neutral default', () {
    const roleProfile = EchoProfile(signature: '');
    const userProfile = EchoProfile(signature: '   ');
    expect(echoSignatureText(roleProfile), '这里记录我的生活。');
    expect(echoSignatureText(userProfile), '这里记录我的生活。');
  });
}
