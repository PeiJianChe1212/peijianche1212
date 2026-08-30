import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/physical_speech_text_adapter.dart';

void main() {
  test('uses formal sanitizer and parser before speech', () {
    const reply = '（扫眼屏幕，指节抵着唇弯了下）行，测吧。<|PEILINK_MSG|>要我配合什么？';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(reply), '行，测吧。\n要我配合什么？');
  });

  test('removes the real Stage D vocal stage direction', () {
    const reply =
        '（翻东西的动作顿了半秒，尾音带着点漫不经心的调侃）'
        '你这是在给录音设备报数，还是在测试我听力？';
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply(reply),
      '你这是在给录音设备报数，还是在测试我听力？',
    );
  });
}
