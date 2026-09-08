import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:peijianche_app/ai/providers/openai_compatible_chat_provider.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_extraction_state.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/pages/peilink/character_creation_page.dart';
import 'package:peijianche_app/platform/media/native_file_media_store.dart';
import 'package:peijianche_app/platform/provider/provider_transport.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/platform/storage/platform_storage.dart';
import 'package:peijianche_app/services/character_profile_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';

void main() {
  late Directory root;
  late NativePlatformStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peilink_contracts_');
    storage = NativePlatformStorage(root.path);
  });
  tearDown(() async => root.delete(recursive: true));

  test('native storage supports safe replace, strict read and listing', () async {
    await storage.replaceTextSafely('a/value.json', '{"v":1}');
    expect(await storage.readText('a/value.json'), '{"v":1}');
    expect(await File('${storage.reference('a/value.json')}.tmp').exists(), isFalse);
    expect((await storage.list('a')).single.key, 'a/value.json');
    await storage.delete('a/value.json');
    expect(await storage.exists('a/value.json'), isFalse);
  });

  test('character registry keeps names and JSON shape', () async {
    final service = CharacterRegistryService(storage: storage);
    final character = AiCharacter(
      id: 'role-a',
      characterName: '角色 A',
      remark: '',
      createdAt: DateTime.utc(2026, 1, 2),
    );
    await service.saveAllCharacters([character]);
    final loaded = (await service.loadAllCharactersStrict()).single;
    expect(loaded.id, character.id);
    expect(loaded.characterName, character.characterName);
    expect(jsonDecode(await storage.readText('character_registry.json')), isA<List>());
  });

  test('settings, profile and chat round-trip through platform storage', () async {
    final registry = CharacterRegistryService(storage: storage);
    final character = AiCharacter(
      id: 'role-a', characterName: '角色 A', remark: '', createdAt: DateTime.utc(2026),
    );
    await registry.saveAllCharacters([character]);
    final settings = CharacterSettings.fromAiCharacter(character);
    final settingsService = CharacterSettingsStorageService(
      characterId: character.id, storage: storage, registry: registry,
    );
    await settingsService.saveSettings(settings);
    final loadedSettings = await settingsService.loadSettings();
    expect(loadedSettings.characterName, settings.characterName);
    expect(loadedSettings.temperature, settings.temperature);
    expect(loadedSettings.autoMemoryEnabled, settings.autoMemoryEnabled);

    final profileService = CharacterProfileStorageService(
      characterId: character.id, storage: storage,
    );
    final profile = CharacterProfile(characterId: character.id, name: '角色 A');
    await profileService.save(profile);
    expect((await profileService.load(character: character, legacySettings: settings)).toJson(), profile.toJson());

    final chat = ChatStorageService(characterId: character.id, storage: storage);
    final message = ChatMessage(role: 'user', content: '你好', id: 'm1');
    await chat.saveMessages([message]);
    expect((await chat.loadMessages()).single.toJson(), message.toJson());
  });

  test('Memory 2.0 and cursor preserve schema and reject corruption', () async {
    final memory = Memory2StorageService(characterId: 'role-a', platformStorage: storage);
    final event = EventMemory(
      id: 'e1', characterId: 'role-a', content: '事件',
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
    );
    await memory.saveEventMemories([event]);
    expect((await memory.loadEventMemoriesStrict()).single.toJson(), event.toJson());
    final memoryJson = jsonDecode(await storage.readText('characters/role-a/event_memories.json')) as Map;
    expect(memoryJson['schemaVersion'], 2);

    final stateService = MemoryExtractionStateService(
      characterId: 'role-a', platformStorage: storage,
    );
    await stateService.save(MemoryExtractionState(
      characterId: 'role-a', lastProcessedMessageId: 'm1',
    ));
    expect((await stateService.loadStrict()).lastProcessedMessageId, 'm1');

    await storage.writeText('characters/role-a/event_memories.json', '{bad');
    await expectLater(memory.loadEventMemoriesStrict(), throwsFormatException);
    expect(await storage.readText('characters/role-a/event_memories.json'), '{bad');
  });

  test('native media saves, reads and deletes bytes without changing reference', () async {
    const media = NativeFileMediaStore();
    final reference = '${root.path}/portrait.png';
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    expect(await media.saveBytes(reference, bytes), reference);
    expect(await media.readBytes(reference), bytes);
    await media.delete(reference);
    expect(await media.exists(reference), isFalse);
  });

  test('AI WORLD media persistence leaves frozen crop geometry unchanged', () async {
    const media = NativeFileMediaStore();
    final reference = '${root.path}/portrait.png';
    await media.saveBytes(reference, Uint8List.fromList([10, 20, 30]));
    expect(await media.exists(reference), isTrue);
    const screen = Size(360, 800);
    expect(backgroundCropViewportSize(screen).aspectRatio, closeTo(screen.aspectRatio, 0.000001));
    final rendered = backgroundCoverRenderSize(const Size(1920, 1080), screen);
    expect(rendered.width, greaterThanOrEqualTo(screen.width));
    expect(rendered.height, greaterThanOrEqualTo(screen.height));
  });

  test('user and dev namespace keys remain isolated', () {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    expect(PeiLinkRuntime.dataNamespace, 'peilink_user');
    expect(PeiLinkRuntime.secureStorageKey('api_key'), 'peilink_user_api_key');
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    expect(PeiLinkRuntime.dataNamespace, 'peilink_dev');
    expect(PeiLinkRuntime.secureStorageKey('api_key'), 'peilink_dev_api_key');
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
  });

  test('unsupported storage fails fast instead of returning empty data', () async {
    const unsupported = UnsupportedPlatformStorage('not implemented');
    await expectLater(unsupported.exists('character_registry.json'), throwsUnsupportedError);
    await expectLater(unsupported.readText('character_registry.json'), throwsUnsupportedError);
  });

  test('provider transport receives unchanged chat request semantics', () async {
    final transport = _RecordingTransport();
    final provider = OpenAiCompatibleChatProvider(
      settings: const ApiSettings(apiKey: 'secret', model: 'deepseek-chat'),
      transport: transport,
    );
    expect(await provider.complete(
      messages: const [{'role': 'user', 'content': '你好'}],
      temperature: 0.7, maxTokens: 520, topP: 0.9,
    ), '收到');
    expect(transport.uri.toString(), 'https://api.deepseek.com/v1/chat/completions');
    expect(transport.headers['Authorization'], 'Bearer secret');
    expect(transport.timeout, const Duration(seconds: 45));
    final body = jsonDecode(transport.body as String) as Map;
    expect(body, containsPair('stream', false));
    expect(body, containsPair('max_tokens', 520));
    expect(body, containsPair('temperature', 0.7));
    expect(body, containsPair('top_p', 0.9));
  });

  test('Android .pei MethodChannel name remains present', () {
    final source = File('lib/services/pei_file_platform_service.dart').readAsStringSync();
    final kotlin = File('android/app/src/main/kotlin/com/peilink/app/MainActivity.kt').readAsStringSync();
    expect(source, contains("MethodChannel('peilink/pei_file')"));
    expect(kotlin, contains('"peilink/pei_file"'));
  });
}

class _RecordingTransport implements ProviderTransport {
  late Uri uri;
  late Map<String, String> headers;
  late Object body;
  late Duration timeout;

  @override
  Future<ProviderTransportResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration timeout,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    this.timeout = timeout;
    return ProviderTransportResponse(
      statusCode: 200,
      bodyBytes: Uint8List.fromList(utf8.encode('{"choices":[{"message":{"content":"收到"},"finish_reason":"stop"}]}')),
    );
  }
}
