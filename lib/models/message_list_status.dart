import 'activity_status.dart';

enum MessageListStatusKind { online, busy, resting, sleeping, outside, music }

class MessageListStatus {
  const MessageListStatus(this.kind, this.label);

  final MessageListStatusKind kind;
  final String label;

  static const online = MessageListStatus(MessageListStatusKind.online, '在线');

  factory MessageListStatus.fromActivity(ActivityStatus activity) {
    if (activity.isSleeping || activity.id == 'sleeping') {
      return const MessageListStatus(MessageListStatusKind.sleeping, '睡觉中');
    }

    if (const {
      'working_morning',
      'working_afternoon',
      'reading_notes',
      'life_working',
    }.contains(activity.id)) {
      return const MessageListStatus(MessageListStatusKind.busy, '忙碌中');
    }

    if (const {
      'resting',
      'lunch_break',
      'getting_ready_sleep',
    }.contains(activity.id)) {
      return const MessageListStatus(MessageListStatusKind.resting, '休息中');
    }

    if (const {
      'going_home',
      'life_going_home',
      'life_outside',
    }.contains(activity.id)) {
      return const MessageListStatus(MessageListStatusKind.outside, '外出中');
    }

    if (const {'music', 'life_music'}.contains(activity.id)) {
      return const MessageListStatus(MessageListStatusKind.music, '听歌中');
    }

    return online;
  }
}
