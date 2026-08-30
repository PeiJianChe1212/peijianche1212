import '../models/activity_status.dart';
import '../models/life_moment.dart';

class ActivityService {
  const ActivityService({this.characterId});

  final String? characterId;

  ActivityStatus current({
    DateTime? now,
    String? characterId,
    LifeMomentCandidate? recentMoment,
  }) {
    final time = now ?? DateTime.now();
    final momentStatus = _statusFromMoment(recentMoment, time);
    if (momentStatus != null) return momentStatus;
    final hour = time.hour;
    final resolvedCharacterId = characterId ?? this.characterId ?? '';
    final roleSeed = resolvedCharacterId.codeUnits.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final variant = (time.year + time.month + time.day + hour + roleSeed) % 3;

    if (hour >= 2 && hour < 7) {
      return const ActivityStatus(
        id: 'sleeping',
        label: '睡觉中',
        emoji: '😴',
        detail: '房间很安静，手机放在床边。这个时间来找他，大概会把一只睡眼惺忪的小狗叫醒。',
        promptGuidance:
            '角色原本正在睡觉。如果用户此刻发来消息，可以带一点刚被叫醒的迟钝和困意，但仍要先回应用户说的具体内容。表现要自然克制，不要擅自使用爱称，也不要每句都描写动作。',
        isSleeping: true,
      );
    }

    if (hour >= 7 && hour < 9) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'waking',
          label: '刚起床',
          emoji: '☀️',
          detail: '刚洗漱完，意识还在慢慢开机。',
          promptGuidance: '语气可以比平时稍松一点，像刚开始一天，但不要刻意报行程。',
        ),
        1 => const ActivityStatus(
          id: 'breakfast',
          label: '吃早餐',
          emoji: '🥛',
          detail: '桌上放着简单的早餐，手机就在手边。',
          promptGuidance: '可以自然带出清晨和早餐的生活感，但优先回应用户。',
        ),
        _ => const ActivityStatus(
          id: 'morning_coffee',
          label: '泡咖啡',
          emoji: '☕',
          detail: '正在等咖啡慢慢滴完。',
          promptGuidance: '状态安静清醒，回复可以有一点清晨的松弛感。',
        ),
      };
    }

    if (hour >= 9 && hour < 12) {
      return const ActivityStatus(
        id: 'working_morning',
        label: '工作中',
        emoji: '☕',
        detail: '桌上摊着文件，偶尔低头看一眼手机。',
        promptGuidance: '像在工作间隙回消息，语气可以简洁一点，但不能敷衍或装忙。',
      );
    }

    if (hour >= 12 && hour < 14) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'lunch',
          label: '吃午饭',
          emoji: '🥢',
          detail: '刚把工作放下，准备安静吃点东西。',
          promptGuidance: '可以自然关心用户有没有吃饭，但不要无视用户原本的话题。',
        ),
        _ => const ActivityStatus(
          id: 'lunch_break',
          label: '午休中',
          emoji: '🌤️',
          detail: '靠着椅背休息，难得有一小段空闲。',
          promptGuidance: '回复可以更放松、更愿意陪她多聊两句。',
        ),
      };
    }

    if (hour >= 14 && hour < 18) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'working_afternoon',
          label: '工作中',
          emoji: '📎',
          detail: '下午的事情不少，但她的消息仍会被放在最上面。',
          promptGuidance: '像在工作间隙回复，保持自然，不要用客服或公事口吻。',
        ),
        1 => const ActivityStatus(
          id: 'organizing',
          label: '整理东西',
          emoji: '📦',
          detail: '正在把散乱的东西一件件收好。',
          promptGuidance: '可以有一点生活化的随手回应，状态不应抢走聊天主题。',
        ),
        _ => const ActivityStatus(
          id: 'reading_notes',
          label: '查资料',
          emoji: '🗂️',
          detail: '翻着资料做笔记，手边压着一支笔。',
          promptGuidance: '语气清醒专注；关系感只依据当前角色资料。',
        ),
      };
    }

    if (hour >= 18 && hour < 20) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'dinner',
          label: '准备晚饭',
          emoji: '🍲',
          detail: '刚回到生活里，正在处理晚饭。',
          promptGuidance: '可以自然地问她今天吃了什么，但不要强行把话题拐到吃饭。',
        ),
        _ => const ActivityStatus(
          id: 'going_home',
          label: '回家路上',
          emoji: '🌆',
          detail: '天色慢慢暗下来，正在往回走。',
          promptGuidance: '回复可以带一点下班后的松弛感，不需要持续描述路上的景象。',
        ),
      };
    }

    if (hour >= 20 && hour < 23) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'reading',
          label: '看书中',
          emoji: '📖',
          detail: '灯开得不亮，书页翻得很慢。',
          promptGuidance: '状态安静、有耐心，适合自然地陪用户聊天。',
        ),
        1 => const ActivityStatus(
          id: 'music',
          label: '听歌中',
          emoji: '🎧',
          detail: '耳机里放着歌，刚好空出一只耳朵给她。',
          promptGuidance: '语气可以轻松一点，偶尔自然分享感受，但不要捏造具体歌曲。',
        ),
        _ => const ActivityStatus(
          id: 'resting',
          label: '休息中',
          emoji: '🌙',
          detail: '今天的事情差不多结束了，正靠着沙发放空。',
          promptGuidance: '回复更放松、更有陪伴感，但仍避免句句情话。',
        ),
      };
    }

    if (hour >= 23 || hour < 2) {
      return switch (variant) {
        0 => const ActivityStatus(
          id: 'late_reading',
          label: '还在看书',
          emoji: '📚',
          detail: '夜已经深了，书还没有合上。',
          promptGuidance: '带一点深夜的安静感。可以注意到用户也还没睡，但不要每句催睡。',
        ),
        1 => const ActivityStatus(
          id: 'getting_ready_sleep',
          label: '准备睡觉',
          emoji: '🌙',
          detail: '灯已经关掉大半，只剩床头的一点光。',
          promptGuidance: '语气可以更低、更松弛，像睡前聊天。不要故意把每个话题都写成哄睡。',
        ),
        _ => const ActivityStatus(
          id: 'waiting_late',
          label: '等你回来',
          emoji: '🕯️',
          detail: '没有特意说在等，手机却一直没有放远。',
          promptGuidance: '可以自然表现出对她晚归的在意，轻微嘴硬即可，不要责备或控制。',
        ),
      };
    }

    return const ActivityStatus(
      id: 'available',
      label: '在这里',
      emoji: '🦋',
      detail: '没在忙什么，看到消息就会回。',
      promptGuidance: '保持自然日常的聊天状态。',
    );
  }

  ActivityStatus? _statusFromMoment(LifeMomentCandidate? moment, DateTime now) {
    if (moment == null) return null;
    final age = now.difference(moment.occurredAt);
    if (age.isNegative || age > const Duration(hours: 8)) return null;

    final text = '${moment.scene} ${moment.event} ${moment.detail}'
        .toLowerCase();

    ActivityStatus status({
      required String id,
      required String label,
      required String emoji,
      required String detail,
      required String guidance,
    }) {
      return ActivityStatus(
        id: id,
        label: label,
        emoji: emoji,
        detail: detail,
        promptGuidance: guidance,
      );
    }

    if (RegExp(r'回家|回去|地铁|公交|开车|路上|车站').hasMatch(text)) {
      return status(
        id: 'life_going_home',
        label: '回家路上',
        emoji: '🌆',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色正在回去的路上，回复可以稍短、带一点路途中的松弛感，但优先回应用户当前的话题。',
      );
    }
    if (RegExp(r'吃饭|午饭|晚饭|早餐|面|牛排|餐厅|咖啡|甜品|做饭').hasMatch(text)) {
      return status(
        id: 'life_eating',
        label: '吃东西',
        emoji: '🥢',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色刚好在吃东西或处理一顿饭，可以自然带出这个生活背景，但不要强行把所有话题拐到吃饭。',
      );
    }
    if (RegExp(r'工作|会议|文件|办公室|加班|客户|项目|资料').hasMatch(text)) {
      return status(
        id: 'life_working',
        label: '忙工作',
        emoji: '📎',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色正处在工作间隙，回复可以简洁一些，但不能敷衍，也不要反复强调自己很忙。',
      );
    }
    if (RegExp(r'书|阅读|笔记|图书馆').hasMatch(text)) {
      return status(
        id: 'life_reading',
        label: '看书中',
        emoji: '📖',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色正在安静阅读，语气可以沉静一些，但状态只是背景，不要写成小说旁白。',
      );
    }
    if (RegExp(r'音乐|耳机|歌|演出').hasMatch(text)) {
      return status(
        id: 'life_music',
        label: '听歌中',
        emoji: '🎧',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色正在听歌，回复可以轻松一点，但不要虚构具体歌名或歌词。',
      );
    }
    if (RegExp(r'散步|公园|街边|逛|商场|超市|便利店|外出').hasMatch(text)) {
      return status(
        id: 'life_outside',
        label: '在外面',
        emoji: '🍃',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色此刻在外面活动，回复可带一点现场生活感，但不要每句都描述环境。',
      );
    }
    if (RegExp(r'滑雪|滑翔|运动|健身|跑步|球').hasMatch(text)) {
      return status(
        id: 'life_activity',
        label: '活动中',
        emoji: '🏃',
        detail: moment.detail.isEmpty ? moment.event : moment.detail,
        guidance: '角色刚经历一段活动，语气可以有一点余兴或轻微疲惫，但仍然先回应用户。',
      );
    }
    return null;
  }
}
