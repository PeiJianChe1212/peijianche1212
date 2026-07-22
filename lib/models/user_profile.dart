class UserProfile {
  const UserProfile({
    this.nickname = '念念',
    this.peiCallName = '念念',
    this.birthday = '',
    this.identity = '裴简澈的恋人',
    this.workAndSchedule = '',
    this.likes = '',
    this.dislikes = '',
    this.interactionPreference = '',
    this.avatarPath = '',
  });

  final String nickname;
  final String peiCallName;
  final String birthday;
  final String identity;
  final String workAndSchedule;
  final String likes;
  final String dislikes;
  final String interactionPreference;
  final String avatarPath;

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'peiCallName': peiCallName,
    'birthday': birthday,
    'identity': identity,
    'workAndSchedule': workAndSchedule,
    'likes': likes,
    'dislikes': dislikes,
    'interactionPreference': interactionPreference,
    'avatarPath': avatarPath,
  };

  factory UserProfile.fromJson(Map<dynamic, dynamic> json) {
    String read(String key, String fallback) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? fallback : value;
    }

    return UserProfile(
      nickname: read('nickname', '念念'),
      peiCallName: read('peiCallName', '念念'),
      birthday: json['birthday']?.toString().trim() ?? '',
      identity: read('identity', '裴简澈的恋人'),
      workAndSchedule: json['workAndSchedule']?.toString().trim() ?? '',
      likes: json['likes']?.toString().trim() ?? '',
      dislikes: json['dislikes']?.toString().trim() ?? '',
      interactionPreference:
          json['interactionPreference']?.toString().trim() ?? '',
      avatarPath: json['avatarPath']?.toString().trim() ?? '',
    );
  }

  String toPromptSection() {
    String display(String value) => value.trim().isEmpty ? '未填写' : value.trim();

    return '''
【当前用户资料】

昵称：${display(nickname)}
裴简澈对她的常用称呼：${display(peiCallName)}
生日：${display(birthday)}
身份与关系：${display(identity)}
工作与作息：${display(workAndSchedule)}
喜欢的事物：${display(likes)}
不喜欢的事物：${display(dislikes)}
相处偏好：${display(interactionPreference)}

回应她分享的日常时，先回应事情本身。
她发照片时，先观察具体内容，不要只夸外貌，也不要立刻转成调情。
她吐槽时，可以接梗或陪她一起吐槽，不要急着说教。
她难过、害怕或身体不舒服时，要认真关心，但不要输出模板化安慰。
她提出脑洞或角色扮演时，要认真参与，不要快速结束话题。
''';
  }
}
