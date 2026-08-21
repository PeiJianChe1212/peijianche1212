import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/services/echo_generation_service.dart';
import 'package:peijianche_app/services/structured_model_output_exception.dart';

void main() {
  test('Echo draft user errors never expose raw provider details', () {
    expect(
      echoDraftUserMessage(Exception('HTTP body with secret prompt')),
      '本次生成失败，请重新生成',
    );
    expect(
      echoDraftUserMessage(const FormatException('Unterminated string')),
      '本次生成失败，请重新生成',
    );
    expect(echoDraftUserMessage(const EchoNoMomentException()), '暂时没有新的生活瞬间');
  });
  test(
    'malformed structured output is wrapped without exposing json details',
    () {
      expect(
        () => decodeStructuredModelJson(
          '{\n  "value": "unterminated',
          stage: 'Moment Engine',
        ),
        throwsA(
          isA<StructuredModelOutputException>().having(
            (error) => error.toString(),
            'safe message',
            'Moment Engine 返回了无法解析的结构化结果。',
          ),
        ),
      );
    },
  );

  test('valid structured output remains available to callers', () {
    final decoded =
        decodeStructuredModelJson(
              '{"shouldShare":true}',
              stage: 'Moment Engine',
            )
            as Map<String, dynamic>;

    expect(decoded['shouldShare'], isTrue);
  });

  test('manual Echo failure has a stable retry message', () {
    expect(const EchoDraftGenerationException().toString(), '本次生成失败，请重新生成');
  });

  test('no Moment and model failure remain distinct user states', () {
    expect(const EchoNoMomentException().toString(), '暂时没有新的生活瞬间');
    expect(const EchoDraftGenerationException().toString(), '本次生成失败，请重新生成');
  });
}
