import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/services/echo_profile_storage_service.dart';

void main() {
  test('legacy EchoProfile without signature keeps a neutral default', () {
    final profile = EchoProfile.fromJson({'coverPath': '/cover.jpg'});
    expect(profile.signature, isEmpty);
    expect(echoSignatureText(profile), '这里记录我的生活。');
  });

  test('signature survives serialization and is used as space text', () {
    const profile = EchoProfile(
      coverPath: '/cover.jpg',
      signature: '慢慢记录正在发生的事。',
    );
    final restored = EchoProfile.fromJson(profile.toJson());
    expect(restored.signature, profile.signature);
    expect(echoSignatureText(restored), profile.signature);
  });
}
