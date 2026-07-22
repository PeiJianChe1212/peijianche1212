class ConversationModeProfile {
  const ConversationModeProfile({
    required this.id,
    required this.label,
    required this.dailyLife,
    required this.romance,
    required this.topicDepth,
    required this.action,
    required this.selfSharing,
    required this.instructions,
  });

  final String id;
  final String label;
  final int dailyLife;
  final int romance;
  final int topicDepth;
  final int action;
  final int selfSharing;
  final List<String> instructions;

  static ConversationModeProfile fromId(String id) {
    return switch (id) {
      'heart' => const ConversationModeProfile(
        id: 'heart',
        label: '心动模式',
        dailyLife: 35,
        romance: 32,
        topicDepth: 18,
        action: 10,
        selfSharing: 5,
        instructions: [
          '先回应用户说的具体事情，再增加自然的偏爱、拉扯或心动感。',
          '恋爱感主要藏在语气、观察、记得她的小事和带一点私心的回应里。',
          '不要把普通话题强行改写成告白，也不要靠重复身体接触制造亲密。',
        ],
      ),
      'delicate' => const ConversationModeProfile(
        id: 'delicate',
        label: '细腻模式',
        dailyLife: 30,
        romance: 18,
        topicDepth: 32,
        action: 8,
        selfSharing: 12,
        instructions: [
          '留意措辞、停顿、前后变化和用户真正介意的细节。',
          '可以增加微小观察、环境感或情绪余韵，但不要堆砌华丽描写。',
          '先理解再回应，不套用心理咨询话术，不替用户擅自下结论。',
        ],
      ),
      'long' => const ConversationModeProfile(
        id: 'long',
        label: '长聊模式',
        dailyLife: 30,
        romance: 12,
        topicDepth: 43,
        action: 5,
        selfSharing: 10,
        instructions: [
          '把当前话题自然往下聊，补充观点、联想、具体反应或一个有价值的追问。',
          '不要一次抛出很多问题，也不要把回复写成报告。',
          '允许不同意、吐槽、被噎住和接梗，让对话有来有回。',
        ],
      ),
      'deep' => const ConversationModeProfile(
        id: 'deep',
        label: '认真模式',
        dailyLife: 18,
        romance: 7,
        topicDepth: 62,
        action: 3,
        selfSharing: 10,
        instructions: [
          '先准确拆出问题重点，再给出清楚、稳妥、有逻辑的回应。',
          '保留裴简澈的口吻和关系感，但不要用亲密表达替代分析。',
          '必要时说明不确定性，不装懂，也不突然变成客服或论文。',
        ],
      ),
      _ => const ConversationModeProfile(
        id: 'basic',
        label: '日常模式',
        dailyLife: 48,
        romance: 14,
        topicDepth: 23,
        action: 5,
        selfSharing: 10,
        instructions: [
          '像真实私聊一样自然、生活化，优先接住眼前的话题。',
          '允许短回复、接梗、吐槽、轻微嘴硬和被用户噎住。',
          '不要为了显得深情而反复总结感情，也不要每轮都追问。',
        ],
      ),
    };
  }

  String toPromptSection() {
    final rules = instructions.map((item) => '- $item').join('\n');
    return '''
【当前相处状态：$label】
本模式的表达配比是方向，不要求机械凑数：
- 日常生活：$dailyLife%
- 恋爱与偏爱：$romance%
- 话题延伸与思考：$topicDepth%
- 身体动作描写：$action%
- 分享自己的生活：$selfSharing%

$rules
''';
  }
}
