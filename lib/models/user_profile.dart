class UserProfile {
  const UserProfile({
    this.nickname = '未设置',
    this.peiLinkId = '未设置',
    this.gender = '',
    this.region = '',
    this.signature = '',
    this.profileBirthday = '',
    this.peiCallName = '未填写',
    this.birthday = '',
    this.identity = '未填写',
    this.workAndSchedule = '',
    this.likes = '',
    this.dislikes = '',
    this.interactionPreference = '',
    this.avatarPath = '',
  });

  /// 展示在“我”、Echo 等用户界面中的个人资料。
  /// 这些字段不会自动发送给 AI。
  final String nickname;
  final String peiLinkId;
  final String gender;
  final String region;
  final String signature;

  /// 用户个人资料中的公开生日，不参与模型 Context。
  final String profileBirthday;
  final String avatarPath;

  /// AI 可见资料。与上面的公开个人资料分开保存和使用。
  final String peiCallName;
  final String birthday;
  final String identity;
  final String workAndSchedule;
  final String likes;
  final String dislikes;
  final String interactionPreference;

  UserProfile copyWith({
    String? nickname,
    String? peiLinkId,
    String? gender,
    String? region,
    String? signature,
    String? profileBirthday,
    String? peiCallName,
    String? birthday,
    String? identity,
    String? workAndSchedule,
    String? likes,
    String? dislikes,
    String? interactionPreference,
    String? avatarPath,
  }) {
    return UserProfile(
      nickname: nickname ?? this.nickname,
      peiLinkId: peiLinkId ?? this.peiLinkId,
      gender: gender ?? this.gender,
      region: region ?? this.region,
      signature: signature ?? this.signature,
      profileBirthday: profileBirthday ?? this.profileBirthday,
      peiCallName: peiCallName ?? this.peiCallName,
      birthday: birthday ?? this.birthday,
      identity: identity ?? this.identity,
      workAndSchedule: workAndSchedule ?? this.workAndSchedule,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      interactionPreference:
          interactionPreference ?? this.interactionPreference,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'peiLinkId': peiLinkId,
    'gender': gender,
    'region': region,
    'signature': signature,
    'profileBirthday': profileBirthday,
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
      nickname: read('nickname', '未设置'),
      peiLinkId: read('peiLinkId', '未设置'),
      gender: json['gender']?.toString().trim() ?? '',
      region:
          json['region']?.toString().trim() ??
          json['location']?.toString().trim() ??
          '',
      signature: json['signature']?.toString().trim() ?? '',
      profileBirthday: json['profileBirthday']?.toString().trim() ?? '',
      peiCallName: read('peiCallName', '未填写'),
      birthday: json['birthday']?.toString().trim() ?? '',
      identity: read('identity', '未填写'),
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
【当前用户希望角色知道的资料】

角色对用户的称呼：${display(peiCallName)}
生日：${display(birthday)}
身份与关系：${display(identity)}
工作与作息：${display(workAndSchedule)}
喜欢的事物：${display(likes)}
不喜欢的事物：${display(dislikes)}
相处偏好：${display(interactionPreference)}

注意：昵称、头像、性别、地区、PeiLink ID 和个性签名属于用户个人资料，不应从这里推断或主动提及。
回应她分享的日常时，先回应事情本身。
她发照片时，先观察具体内容，不要只夸外貌，也不要立刻转成调情。
她吐槽时，可以接梗或陪她一起吐槽，不要急着说教。
她难过、害怕或身体不舒服时，要认真关心，但不要输出模板化安慰。
她提出脑洞或角色扮演时，要认真参与，不要快速结束话题。
''';
  }
}
