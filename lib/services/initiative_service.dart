import 'dart:convert';
import 'dart:io';


import '../models/activity_status.dart';
import '../models/chat_message.dart';
import '../models/initiative_state.dart';
import 'activity_service.dart';
import 'chat_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'character_scope_service.dart';
import 'life_trace_service.dart';

class InitiativeService {
  InitiativeService({
    ChatStorageService? chatStorage,
    CharacterSettingsStorageService? characterStorage,
    ActivityService? activityService,
    LifeTraceService? lifeTraceService,
    String? characterId,
  }) : _characterId = characterId,
       _chatStorage =
           chatStorage ?? ChatStorageService(characterId: characterId),
       _characterStorage = characterStorage ??
           CharacterSettingsStorageService(characterId: characterId),
       _activityService = activityService ?? const ActivityService(),
       _lifeTraceService =
           lifeTraceService ?? LifeTraceService(characterId: characterId);

  final String? _characterId;
  final ChatStorageService _chatStorage;
  final CharacterSettingsStorageService _characterStorage;
  final ActivityService _activityService;
  final LifeTraceService _lifeTraceService;

  Future<File> _stateFile() {
    return CharacterScopeService(_characterId).dataFile(
      'initiative_state.json',
      legacyDefaultFileName: 'initiative_state.json',
    );
  }

  Future<InitiativeState> loadState({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _stateFile();
    if (!await file.exists()) return InitiativeState.empty(time);
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return InitiativeState.empty(time);
      return InitiativeState.fromJson(decoded).normalized(time);
    } catch (_) {
      return InitiativeState.empty(time);
    }
  }

  Future<void> saveState(InitiativeState state) async {
    final file = await _stateFile();
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  Future<int> unreadCount() async => (await loadState()).unreadCount;

  Future<void> markAllRead() async {
    final state = await loadState();
    if (state.unreadCount == 0) return;
    await saveState(state.copyWith(unreadCount: 0));
  }

  Future<bool> maybeLeaveMessage({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final settings = await _characterStorage.loadSettings();
    if (!settings.proactiveEnabled || settings.maxProactivePerDay <= 0) {
      return false;
    }

    final slot = _slotFor(time);
    if (slot == null) return false;
    if (slot == 'late' && !settings.lateNightMessages) return false;

    final state = (await loadState(now: time)).normalized(time);
    if (state.sentCount >= settings.maxProactivePerDay ||
        state.usedSlots.contains(slot)) {
      return false;
    }

    final messages = await _chatStorage.loadMessages();
    final latest = messages.isEmpty ? null : messages.last.createdAt;
    final lastTouch = _latest(latest, state.lastSentAt);
    final requiredGap = slot == 'late'
        ? const Duration(hours: 2)
        : const Duration(hours: 3);
    if (lastTouch != null && time.difference(lastTouch) < requiredGap) {
      return false;
    }

    final activity = _activityService.current(now: time);
    final content = _messageFor(activity: activity, now: time, slot: slot);
    final nextMessages = List<ChatMessage>.from(messages)
      ..add(ChatMessage(role: 'assistant', content: content, source: 'initiative'));
    await _chatStorage.saveMessages(nextMessages);
    await _lifeTraceService.recordInitiative(now: time);
    await saveState(
      state.copyWith(
        sentCount: state.sentCount + 1,
        unreadCount: state.unreadCount + 1,
        usedSlots: [...state.usedSlots, slot],
        lastSentAt: time,
      ),
    );
    return true;
  }

  Future<void> clear() async {
    final file = await _stateFile();
    if (await file.exists()) await file.delete();
  }

  DateTime? _latest(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }

  String? _slotFor(DateTime now) {
    final hour = now.hour;
    if (hour >= 8 && hour < 11) return 'morning';
    if (hour >= 12 && hour < 15) return 'noon';
    if (hour >= 17 && hour < 21) return 'evening';
    if (hour >= 21 && hour < 23) return 'night';
    if (hour >= 23 || hour < 2) return 'late';
    return null;
  }

  String _messageFor({
    required ActivityStatus activity,
    required DateTime now,
    required String slot,
  }) {
    final seed = now.day + now.hour + activity.id.hashCode.abs();
    List<String> choices;

    if (activity.isSleeping) {
      choices = const ['还没睡？', '这么晚了，还醒着？'];
    } else {
      choices = switch (activity.id) {
        'morning_coffee' => const ['刚泡了咖啡。你醒了吗？', '早。今天别又空着肚子。'],
        'breakfast' || 'waking' => const ['醒了吗？', '早。昨晚睡得怎么样？'],
        'working_morning' ||
        'working_afternoon' => const ['忙完一阵，忽然想起你。', '今天工作顺利吗？'],
        'lunch' || 'lunch_break' => const ['吃饭了吗？', '中午了，别又忘记吃东西。'],
        'going_home' => const ['我在回去的路上。你呢？', '今天什么时候下班？'],
        'dinner' => const ['准备吃晚饭了。你今天吃什么？', '晚饭解决了吗？'],
        'reading' || 'late_reading' => const ['刚看了会儿书。你在做什么？', '今晚很安静。'],
        'music' => const ['刚听了会儿歌。忽然想找你说句话。', '在忙吗？'],
        'getting_ready_sleep' => const ['我准备睡了。你别拖得太晚。', '还不回来？'],
        'waiting_late' => const ['还没回来？', '今天一直没见到你。'],
        _ => switch (slot) {
          'morning' => const ['醒了吗？', '早。今天准备做什么？'],
          'noon' => const ['吃饭了吗？', '中午了，休息一会儿。'],
          'evening' => const ['下班了吗？', '今天过得怎么样？'],
          'night' => const ['在做什么？', '今晚有空陪我说会儿话吗？'],
          _ => const ['还不睡？', '这么晚了，怎么还醒着。'],
        },
      };
    }

    return choices[seed % choices.length];
  }
}
