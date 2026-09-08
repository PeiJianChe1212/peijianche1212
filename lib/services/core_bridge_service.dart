import '../models/chat_message.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'deepseek_service.dart';

typedef CoreBridgeReplySender =
    Future<String> Function({
      required List<ChatMessage> messages,
      required String characterId,
      required String conversationMode,
      required double temperature,
      required String replyLength,
      required double initiative,
      required double intimacy,
      required double tsundere,
      String? physicalSpeechContract,
    });

class CoreBridgeService {
  CoreBridgeService({
    CharacterRegistryService? registry,
    CoreBridgeReplySender? replySender,
  }) : _registry = registry ?? CharacterRegistryService(),
       _deepSeek = replySender == null ? DeepSeekService() : null,
       _replySender = replySender;

  final CharacterRegistryService _registry;
  final DeepSeekService? _deepSeek;
  final CoreBridgeReplySender? _replySender;

  Future<String> reply({
    required String characterId,
    required String userText,
    List<ChatMessage> transientContext = const [],
    String? physicalSpeechContract,
  }) async {
    final characters = await _registry.loadCharacters();
    if (!characters.any((character) => character.id == characterId)) {
      throw const CoreBridgeException(
        'CHARACTER_NOT_FOUND',
        '指定角色不存在',
        statusCode: 404,
      );
    }

    final history = await ChatStorageService(
      characterId: characterId,
    ).loadMessages();
    final messages = <ChatMessage>[
      ...history,
      ...transientContext,
      ChatMessage(role: 'user', content: userText),
    ];
    final settings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();

    final sender =
        _replySender ??
        ({
          required messages,
          required characterId,
          required conversationMode,
          required temperature,
          required replyLength,
          required initiative,
          required intimacy,
          required tsundere,
          String? physicalSpeechContract,
        }) => _deepSeek!.sendMessage(
          messages: messages,
          characterId: characterId,
          conversationMode: conversationMode,
          temperature: temperature,
          replyLength: replyLength,
          initiative: initiative,
          intimacy: intimacy,
          tsundere: tsundere,
          physicalSpeechContract: physicalSpeechContract,
        );
    return sender(
      messages: messages,
      characterId: characterId,
      conversationMode: settings.conversationMode,
      temperature: settings.temperature,
      replyLength: settings.replyLength,
      initiative: settings.initiative,
      intimacy: settings.intimacy,
      tsundere: settings.tsundere,
      physicalSpeechContract: physicalSpeechContract,
    );
  }

  void dispose() => _deepSeek?.dispose();
}

class CoreBridgeException implements Exception {
  const CoreBridgeException(this.code, this.message, {this.statusCode = 400});

  final String code;
  final String message;
  final int statusCode;
}
