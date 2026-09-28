import 'turtle_soup_logic_profile.dart';

class TurtleSoupProfileRegistry {
  TurtleSoupProfileRegistry._();

  static const profiles = <TurtleSoupLogicProfile>[
    _emptyCupWatermark,
    _midnightGreenhouse,
    _sealedLunchbox,
  ];

  static TurtleSoupLogicProfile? byPuzzleId(String puzzleId) =>
      profiles.where((profile) => profile.puzzleId == puzzleId).firstOrNull;

  static TurtleSoupLogicProfile? findByPuzzleId(String puzzleId) =>
      byPuzzleId(puzzleId);
}

const _emptyCupWatermark = TurtleSoupLogicProfile(
  version: 1,
  puzzleId: 'empty_cup_watermark',
  hintReasoning: [
    HintReasoningMetadata(hintText: '水不是从杯口或杯内出来的。'),
    HintReasoningMetadata(hintText: '杯子与房间空气的温度差很重要。'),
  ],
  actionableRules: [
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['水不是从杯口或杯内出来的。'],
      publicText: '可以继续确认杯外水分究竟来自哪里。',
    ),
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['杯子与房间空气的温度差很重要。'],
      publicText: '温差已明确重要，可以继续确认房间空气是否参与了水迹形成。',
    ),
  ],
  facts: [
    PuzzleFact(
      id: 'f01',
      statement: '空杯刚从低温冷藏环境中取出，杯体温度明显低于室温。',
      publicSummary: '杯子此前处于低温环境。',
      importance: PuzzleFactImportance.critical,
      category: '环境',
    ),
    PuzzleFact(
      id: 'f02',
      statement: '房间空气温暖且含有足够水汽。',
      publicSummary: '室内空气含有水汽，并且比杯子温暖。',
      importance: PuzzleFactImportance.supporting,
      category: '环境',
    ),
    PuzzleFact(
      id: 'f03',
      statement: '空气中的水汽接触冰冷杯壁后凝结成液态水珠。',
      publicSummary: '空气中的水汽在冰冷杯壁上发生了冷凝。',
      importance: PuzzleFactImportance.critical,
      category: '物理现象',
    ),
    PuzzleFact(
      id: 'f04',
      statement: '水珠沿杯子外壁流到底部，水迹并非来自杯内。',
      publicSummary: '桌面水迹来自杯外的冷凝水，不是杯内液体。',
      importance: PuzzleFactImportance.critical,
      category: '来源',
    ),
  ],
  causalEdges: [
    CausalEdge(
      id: 'e01',
      sourceFactIds: ['f01', 'f02'],
      relation: CausalRelation.causes,
      targetFactId: 'f03',
      publicSummary: '低温杯壁与温暖湿润空气共同导致水汽冷凝。',
      requiredForSolve: true,
    ),
    CausalEdge(
      id: 'e02',
      sourceFactIds: ['f03'],
      relation: CausalRelation.causes,
      targetFactId: 'f04',
      publicSummary: '杯壁冷凝水流到底部后形成了桌面水圈。',
      requiredForSolve: true,
    ),
  ],
  directions: [
    ReasoningDirection(
      id: 'd01',
      hiddenDescription: '确认低温杯体与空气水汽形成冷凝的来源机制。',
      publicActiveSummary: '继续确认水迹中的水来自哪里，以及空杯为什么会产生水。',
      publicRejectedSummary: '低温与空气水汽不是水迹来源。',
      publicSufficientSummary: '水迹来源与冷凝形成机制的公开信息已经足够。',
      relatedFactIds: ['f01', 'f02', 'f03'],
      sufficiencyFactIds: ['f01', 'f03'],
      sufficiencyEdgeIds: ['e01'],
      kind: ReasoningDirectionKind.validBranch,
    ),
    ReasoningDirection(
      id: 'd04',
      hiddenDescription: '确认冷凝水沿杯外壁到底部并接触桌面形成水迹。',
      publicActiveSummary: '继续确认杯子外部的水如何到达桌面形成水迹。',
      publicRejectedSummary: '杯外水分没有形成桌面水迹。',
      publicSufficientSummary: '冷凝水到达桌面形成水迹的过程已经足够清楚。',
      relatedFactIds: ['f03', 'f04'],
      sufficiencyFactIds: ['f04'],
      sufficiencyEdgeIds: ['e02'],
      kind: ReasoningDirectionKind.validBranch,
    ),
    ReasoningDirection(
      id: 'd05',
      hiddenDescription: '杯底必须有凹槽、凸起、锥形或特殊受压结构才能形成水圈。',
      publicRejectedSummary: '杯底具体的凹槽、凸起或锥形结构不是解释水迹的必要条件。',
      relatedFactIds: ['f04'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd06',
      hiddenDescription:
          '追查杯内具体低温物质、液体种类或挥发制冷。真相没有说明杯内曾装其他液体，不能据此回答是；具体物质种类不是解谜必需条件。',
      publicRejectedSummary: '具体低温物质的种类不是解释本局水迹的必要条件。',
      relatedFactIds: ['f01'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd02',
      hiddenDescription: '杯内曾装水或杯体发生泄漏。',
      publicRejectedSummary: '水迹不是杯内液体泄漏造成的。',
      relatedFactIds: ['f04'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd03',
      hiddenDescription: '有人向桌面洒水或桌面原本有水。',
      publicRejectedSummary: '水迹不是他人洒水，也不是桌面原有的水。',
      relatedFactIds: ['f04'],
      kind: ReasoningDirectionKind.misconception,
    ),
  ],
  boundaryGuides: [
    BoundaryGuide(
      id: 'b07',
      questionFamily: '杯子里装过除水以外的液体吗',
      expectedJudgment: ProfileExpectedJudgment.uncertain,
    ),
    BoundaryGuide(
      id: 'b08',
      questionFamily: '具体低温物质的种类是否是解谜必要条件',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd06',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b01',
      questionFamily: '杯子此前是否处于低温、冷藏或与室温存在明显温差',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
      ],
    ),
    BoundaryGuide(
      id: 'b02',
      questionFamily: '空气中的水汽是否在杯子外壁冷凝',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f03'),
        BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e01'),
      ],
    ),
    BoundaryGuide(
      id: 'b03',
      questionFamily: '水迹是否来自杯内液体、杯子漏水或曾经装水',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd02',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b04',
      questionFamily: '是否有人洒水或桌面此前已经有水',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd03',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b05',
      questionFamily: '冷凝水是否沿杯外壁流到底部形成水圈',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f04'),
        BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e02'),
      ],
    ),
    BoundaryGuide(
      id: 'b06',
      questionFamily: '杯底特殊几何形状是否是形成水圈的必要条件',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd05',
        ),
      ],
    ),
  ],
  solveCriteria: SolveCriteria(
    requiredFactIds: ['f01', 'f03', 'f04'],
    requiredEdgeIds: ['e01', 'e02'],
  ),
);

const _midnightGreenhouse = TurtleSoupLogicProfile(
  version: 1,
  puzzleId: 'midnight_greenhouse',
  hintReasoning: [
    HintReasoningMetadata(hintText: '灯光服务的对象不一定是人。'),
    HintReasoningMetadata(hintText: '亮灯时间由当天的环境数据决定。'),
  ],
  actionableRules: [
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['灯光服务的对象不一定是人。'],
      publicText: '可以继续确认灯光服务的对象与用途。',
    ),
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['亮灯时间由当天的环境数据决定。'],
      publicText: '可以继续确认当天环境变化如何影响亮灯安排。',
    ),
  ],
  facts: [
    PuzzleFact(
      id: 'f01',
      statement: '温室内种植着需要特定光照时长的热带幼苗。',
      publicSummary: '灯光服务的对象是需要补光的热带幼苗。',
      importance: PuzzleFactImportance.critical,
      category: '对象',
    ),
    PuzzleFact(
      id: 'f02',
      statement: '自动系统会读取当天自然光照数据。',
      publicSummary: '系统会根据当天的自然光照数据作出判断。',
      importance: PuzzleFactImportance.supporting,
      category: '设备',
    ),
    PuzzleFact(
      id: 'f03',
      statement: '当天自然光照不足时，幼苗尚未获得足够光照时长。',
      publicSummary: '亮灯当天的自然光照不足。',
      importance: PuzzleFactImportance.critical,
      category: '环境',
    ),
    PuzzleFact(
      id: 'f04',
      statement: '自动补光系统会在夜间开启植物补光灯。',
      publicSummary: '夜间亮灯是自动补光系统主动开启的。',
      importance: PuzzleFactImportance.critical,
      category: '自动化',
    ),
    PuzzleFact(
      id: 'f05',
      statement: '值班员只需远程确认设备状态，温室内不需要有人。',
      publicSummary: '值班员通过远程方式确认设备，现场无需有人。',
      importance: PuzzleFactImportance.critical,
      category: '职业流程',
    ),
    PuzzleFact(
      id: 'f06',
      statement: '补光时遮光帘会同时降低，以控制光线外溢和环境。',
      publicSummary: '补光期间系统还会联动控制遮光帘。',
      importance: PuzzleFactImportance.supporting,
      category: '设备',
    ),
  ],
  causalEdges: [
    CausalEdge(
      id: 'e01',
      sourceFactIds: ['f02', 'f03'],
      relation: CausalRelation.causes,
      targetFactId: 'f04',
      publicSummary: '系统检测到当天光照不足，因此在夜间自动补光。',
      requiredForSolve: true,
    ),
    CausalEdge(
      id: 'e02',
      sourceFactIds: ['f04'],
      relation: CausalRelation.enables,
      targetFactId: 'f01',
      publicSummary: '夜间补光帮助幼苗补足所需光照时长。',
      requiredForSolve: true,
    ),
    CausalEdge(
      id: 'e03',
      sourceFactIds: ['f04'],
      relation: CausalRelation.enables,
      targetFactId: 'f06',
      publicSummary: '补光启动时会联动控制遮光帘。',
    ),
  ],
  directions: [
    ReasoningDirection(
      id: 'd01',
      hiddenDescription: '从植物需求、环境数据和自动补光流程推进。',
      publicActiveSummary: '继续确认夜间灯光服务什么对象、为何触发以及如何管理。',
      publicRejectedSummary: '植物需求与自动化设备仍是有效调查方向。',
      publicSufficientSummary: '夜间亮灯的用途、触发条件与管理流程已经足够清楚。',
      relatedFactIds: ['f01', 'f02', 'f03', 'f04', 'f05', 'f06'],
      sufficiencyFactIds: ['f01', 'f03', 'f04', 'f05'],
      sufficiencyEdgeIds: ['e01', 'e02'],
      kind: ReasoningDirectionKind.validBranch,
    ),
    ReasoningDirection(
      id: 'd02',
      hiddenDescription: '温室有人加班或值班员隐瞒现场人员。',
      publicRejectedSummary: '亮灯不是因为温室内有人加班。',
      relatedFactIds: ['f05'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd03',
      hiddenDescription: '工作人员忘记关闭普通照明。',
      publicRejectedSummary: '灯不是被工作人员遗忘关闭的。',
      relatedFactIds: ['f04'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd04',
      hiddenDescription: '灯光用于防盗、拍摄或为游客照明。',
      publicRejectedSummary: '灯光用途不是防盗、拍摄或服务游客。',
      relatedFactIds: ['f01'],
      kind: ReasoningDirectionKind.misconception,
    ),
  ],
  boundaryGuides: [
    BoundaryGuide(
      id: 'b01',
      questionFamily: '灯光是否服务需要特定光照时长的热带幼苗',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
      ],
    ),
    BoundaryGuide(
      id: 'b02',
      questionFamily: '夜间植物补光灯是否由自动补光系统根据环境数据开启',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f02'),
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f04'),
      ],
    ),
    BoundaryGuide(
      id: 'b03',
      questionFamily: '当天是否自然光照不足或植物没有获得足够光照',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f03'),
      ],
    ),
    BoundaryGuide(
      id: 'b04',
      questionFamily: '值班员是否只需远程检查而不进入温室',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f05'),
      ],
    ),
    BoundaryGuide(
      id: 'b05',
      questionFamily: '温室内是否有人加班或值班员说谎',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd02',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b06',
      questionFamily: '灯是否因为工作人员忘记关闭',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd03',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b07',
      questionFamily: '灯是否用于防盗、拍摄或服务游客',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd04',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b08',
      questionFamily: '夜间补光是否帮助幼苗满足光照时长',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e02'),
      ],
    ),
  ],
  solveCriteria: SolveCriteria(
    requiredFactIds: ['f01', 'f03', 'f04', 'f05'],
    requiredEdgeIds: ['e01', 'e02'],
  ),
);

const _sealedLunchbox = TurtleSoupLogicProfile(
  version: 1,
  puzzleId: 'sealed_lunchbox',
  hintReasoning: [
    HintReasoningMetadata(hintText: '异常来自盒子的外观，不来自食物。'),
    HintReasoningMetadata(hintText: '盒子反映了房间里一种看不见的环境变化。'),
  ],
  actionableRules: [
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['异常来自盒子的外观，不来自食物。'],
      publicText: '可以继续确认盒子外观发生了什么变化。',
    ),
    ActionableReasoningRule(
      directionId: 'd01',
      requiredHintTexts: ['盒子反映了房间里一种看不见的环境变化。'],
      publicText: '可以继续确认房间环境与盒子外观变化之间的关系。',
    ),
  ],
  facts: [
    PuzzleFact(
      id: 'f01',
      statement: '午餐盒使用会随内外气压差发生形变的柔性密封盖。',
      publicSummary: '午餐盒的柔性密封盖会随气压变化而形变。',
      importance: PuzzleFactImportance.critical,
      category: '物品性质',
    ),
    PuzzleFact(
      id: 'f02',
      statement: '楼宇换气系统故障，使实验楼内形成持续负压。',
      publicSummary: '楼内换气系统异常造成了持续负压。',
      importance: PuzzleFactImportance.critical,
      category: '设备故障',
    ),
    PuzzleFact(
      id: 'f03',
      statement: '持续负压使午餐盒柔性密封盖出现异常内凹。',
      publicSummary: '楼内负压使密封盒盖异常向内凹陷。',
      importance: PuzzleFactImportance.critical,
      category: '物理因果',
    ),
    PuzzleFact(
      id: 'f04',
      statement: '同层用于直接报警的压力传感器当时正在维护。',
      publicSummary: '同层压力传感器当时正在维护，无法提供正常提示。',
      importance: PuzzleFactImportance.critical,
      category: '设备状态',
    ),
    PuzzleFact(
      id: 'f05',
      statement: '研究员在未打开盒子的情况下观察到了盒盖异常。',
      publicSummary: '研究员通过盒盖外观发现异常，没有打开午餐盒。',
      importance: PuzzleFactImportance.critical,
      category: '观察',
    ),
    PuzzleFact(
      id: 'f06',
      statement: '研究员用盒盖现象确认环境异常并上报，避免人员继续进入。',
      publicSummary: '研究员据此确认并上报楼内环境问题。',
      importance: PuzzleFactImportance.critical,
      category: '安全流程',
    ),
  ],
  causalEdges: [
    CausalEdge(
      id: 'e01',
      sourceFactIds: ['f02'],
      relation: CausalRelation.causes,
      targetFactId: 'f03',
      publicSummary: '换气系统异常形成的负压导致盒盖内凹。',
      requiredForSolve: true,
    ),
    CausalEdge(
      id: 'e02',
      sourceFactIds: ['f01', 'f02'],
      relation: CausalRelation.explains,
      targetFactId: 'f03',
      publicSummary: '柔性密封结构使盒盖能够反映楼内气压异常。',
      requiredForSolve: true,
    ),
    CausalEdge(
      id: 'e03',
      sourceFactIds: ['f04', 'f05'],
      relation: CausalRelation.enables,
      targetFactId: 'f06',
      publicSummary: '压力传感器维护期间，盒盖现象成为研究员确认问题的依据。',
      requiredForSolve: true,
    ),
  ],
  directions: [
    ReasoningDirection(
      id: 'd01',
      hiddenDescription: '从密封盒结构、气压、换气系统和安全流程推进。',
      publicActiveSummary: '继续确认午餐盒外观变化与楼内环境异常之间的关系。',
      publicRejectedSummary: '密封结构、气压和楼宇设备仍是有效方向。',
      publicSufficientSummary: '盒盖变化、环境异常与发现上报流程已经足够清楚。',
      relatedFactIds: ['f01', 'f02', 'f03', 'f04', 'f05', 'f06'],
      sufficiencyFactIds: ['f01', 'f02', 'f03', 'f04', 'f05', 'f06'],
      sufficiencyEdgeIds: ['e01', 'e02', 'e03'],
      kind: ReasoningDirectionKind.validBranch,
    ),
    ReasoningDirection(
      id: 'd02',
      hiddenDescription: '食物变质、有毒或盒内生物导致异常。',
      publicRejectedSummary: '异常与食物变质、有毒或盒内生物无关。',
      relatedFactIds: ['f05'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd03',
      hiddenDescription: '有人打开、调包或破坏了午餐盒。',
      publicRejectedSummary: '午餐盒没有被人打开、调包或破坏。',
      relatedFactIds: ['f05'],
      kind: ReasoningDirectionKind.misconception,
    ),
    ReasoningDirection(
      id: 'd04',
      hiddenDescription: '压力传感器已经正常报警并直接告知研究员。',
      publicRejectedSummary: '研究员不是通过正常工作的压力传感器收到报警。',
      relatedFactIds: ['f04', 'f06'],
      kind: ReasoningDirectionKind.misconception,
    ),
  ],
  boundaryGuides: [
    BoundaryGuide(
      id: 'b01',
      questionFamily: '盒盖是否柔软、密封并会随气压变化',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
      ],
    ),
    BoundaryGuide(
      id: 'b02',
      questionFamily: '楼内持续负压是否由换气系统故障造成',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f02'),
      ],
    ),
    BoundaryGuide(
      id: 'b03',
      questionFamily: '负压是否导致柔性盒盖向内凹陷',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f03'),
        BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e01'),
        BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e02'),
      ],
    ),
    BoundaryGuide(
      id: 'b04',
      questionFamily: '同层压力传感器是否因正在维护而无法正常提示',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f04'),
      ],
    ),
    BoundaryGuide(
      id: 'b05',
      questionFamily: '研究员是否通过盒盖外观而非打开盒子发现异常',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f05'),
      ],
    ),
    BoundaryGuide(
      id: 'b06',
      questionFamily: '食物是否变质、有毒或盒内有生物',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd02',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b07',
      questionFamily: '午餐盒是否被打开、调包或人为破坏',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd03',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b08',
      questionFamily: '研究员是否由正常工作的压力传感器直接获知异常',
      expectedJudgment: ProfileExpectedJudgment.no,
      effects: [
        BoundaryEffect(
          type: BoundaryEffectType.rejectDirection,
          targetId: 'd04',
        ),
      ],
    ),
    BoundaryGuide(
      id: 'b09',
      questionFamily: '盒盖现象是否帮助研究员确认并上报楼内问题',
      expectedJudgment: ProfileExpectedJudgment.yes,
      effects: [
        BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f06'),
      ],
    ),
  ],
  solveCriteria: SolveCriteria(
    requiredFactIds: ['f01', 'f02', 'f03', 'f04', 'f05', 'f06'],
    requiredEdgeIds: ['e01', 'e02', 'e03'],
  ),
);
