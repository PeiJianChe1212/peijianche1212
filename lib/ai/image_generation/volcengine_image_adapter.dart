import 'openai_compatible_image_adapter.dart';

class VolcengineImageAdapter extends OpenAiCompatibleImageAdapter {
  VolcengineImageAdapter({
    required super.apiKey,
    required super.endpointUrl,
    required super.model,
    super.client,
  }) : super(
         adapterName: '豆包 / 火山方舟',
         requestUrlResponse: true,
         includeWatermarkFlag: true,
       );
}
