import '../models/activity_status.dart';

class PresenceService {
  const PresenceService();

  String homeGreeting({
    required DateTime now,
    required ActivityStatus activity,
  }) {
    if (activity.isSleeping) return '这么晚来找我，是有什么事？';
    if (now.hour < 9) return '醒了？先过来让我看看。';
    if (now.hour < 12) return '上午还算安静，你今天忙不忙。';
    if (now.hour < 14) return '到饭点了。你别又只顾着忙。';
    if (now.hour < 18) return '下午过了一半，今天还顺利吗。';
    if (now.hour < 21) return '回来了？今天的事慢慢说。';
    if (now.hour < 23) return '今晚不急，我在。';
    return '又拖到这么晚才回来。';
  }
}
