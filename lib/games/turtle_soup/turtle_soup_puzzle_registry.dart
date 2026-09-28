import 'dart:math';

import 'turtle_soup_models.dart';

class TurtleSoupPuzzleRegistry {
  TurtleSoupPuzzleRegistry._();
  static const puzzles = <TurtleSoupPuzzle>[
    TurtleSoupPuzzle(
      id: 'late_library',
      title: '迟到的闭馆铃',
      surface: '小岚每天都在闭馆铃响后才离开图书馆，管理员却从不催她。为什么？',
      truth: '小岚是图书馆的志愿者。闭馆铃响后，她要协助管理员确认阅览室无人，再一起离开。',
      hints: ['她不是普通读者。', '她离开前还有一项固定工作。'],
      requiredTruthPoints: ['志愿者', '协助管理员', '确认无人'],
      reasoningDimensions: ['人物身份', '时间', '职业流程'],
      yesKeywords: ['工作', '管理员', '志愿者', '检查', '帮忙', '闭馆'],
      noKeywords: ['被困', '睡着', '偷书', '惩罚'],
      irrelevantKeywords: ['天气', '年龄', '早餐'],
    ),
    TurtleSoupPuzzle(
      id: 'silent_piano',
      title: '没有声音的钢琴',
      surface: '阿澄每天坐在钢琴前练习一小时，邻居却从没听见琴声。为什么？',
      truth: '阿澄使用的是带耳机的电钢琴，练习时琴声只从耳机里播放。',
      hints: ['这架琴不完全是传统钢琴。', '声音确实存在，只是传播范围很小。'],
      requiredTruthPoints: ['电钢琴', '耳机', '声音只在耳机'],
      reasoningDimensions: ['设备类型', '声音传播', '人物行为'],
      yesKeywords: ['电子', '电钢琴', '耳机', '静音', '音量'],
      noKeywords: ['邻居不在', '隔音房', '假装', '失聪'],
      irrelevantKeywords: ['曲目', '楼层', '性别'],
    ),
    TurtleSoupPuzzle(
      id: 'empty_umbrella',
      title: '空着的雨伞架',
      surface: '外面下着大雨，咖啡店门口的雨伞架却一直是空的，客人们也没有淋湿。为什么？',
      truth: '咖啡店位于商场内部，客人从地下停车场或有顶连廊进入，根本不需要撑伞。',
      hints: ['咖啡店门外不等于室外。', '客人有不接触雨水的到达路线。'],
      requiredTruthPoints: ['商场内部', '地下停车场或连廊', '无需撑伞'],
      reasoningDimensions: ['空间关系', '环境', '到达路线'],
      yesKeywords: ['商场', '室内', '停车场', '连廊', '有顶', '不用伞'],
      noKeywords: ['雨停', '伞被偷', '都带雨衣'],
      irrelevantKeywords: ['咖啡价格', '人数', '店员'],
    ),
    TurtleSoupPuzzle(
      id: 'one_page_calendar',
      title: '只撕一页的日历',
      surface: '一整个月过去，阿禾只从日历上撕掉了一页，却没有记错日期。为什么？',
      truth: '那是一本每月一页的月历，不是每天一页的日历；一个月结束只需要撕一页。',
      hints: ['日历的分页方式很关键。', '一页代表的不是一天。'],
      requiredTruthPoints: ['月历', '每月一页', '一个月撕一页'],
      reasoningDimensions: ['物品类型', '时间单位', '使用方式'],
      yesKeywords: ['月历', '一月一页', '每月', '分页'],
      noKeywords: ['忘记', '电子日历', '没出门'],
      irrelevantKeywords: ['月份', '颜色', '地点'],
    ),
    TurtleSoupPuzzle(
      id: 'dry_delivery_box',
      title: '雨后的干纸箱',
      surface: '门外刚下过一场大雨，放在门口的纸箱却完全干燥，箱子也没有套塑料袋。为什么？',
      truth: '纸箱是雨停后才由快递员送到的，并被放在门廊向内凹进的屋檐下。地面较湿是先前的雨造成的，纸箱从未淋到雨。',
      hints: ['纸箱和雨到达门口的时间并不相同。', '门口有一块不会直接淋雨的区域。'],
      requiredTruthPoints: ['雨停后才配送', '纸箱放在屋檐遮挡处'],
      reasoningDimensions: ['时间顺序', '空间位置', '天气环境'],
      yesKeywords: ['雨停后', '后来送到', '快递', '屋檐', '门廊', '遮挡'],
      noKeywords: ['防水纸箱', '塑料袋', '有人擦干', '雨是假的'],
      irrelevantKeywords: ['快递品牌', '箱内物品', '收件人职业'],
    ),
    TurtleSoupPuzzle(
      id: 'slow_display_clock',
      title: '每天慢一分钟的钟',
      surface: '大厅里的一只钟每天看起来都会比昨天慢一分钟，维修员却确认它走时准确。为什么？',
      truth:
          '人们是在大厅的信息屏上看这只钟的实时摄像画面。信息屏正在进行“时间延迟”艺术展示，程序每天把画面延迟量增加一分钟，月底再重置；实体钟始终准确，逐日变慢的是屏幕中的画面。',
      hints: ['人们并不是直接看着实体钟作比较。', '变化来自展示画面的延迟，而不是钟的机械走时。'],
      requiredTruthPoints: ['通过信息屏观看钟', '画面延迟每天增加一分钟', '实体钟始终准确'],
      reasoningDimensions: ['观察方式', '时间记录', '显示设备'],
      yesKeywords: ['摄像', '屏幕', '画面延迟', '艺术展示', '显示', '程序'],
      noKeywords: ['钟坏了', '电池不足', '故意调慢', '时区变化'],
      irrelevantKeywords: ['钟的颜色', '大厅人数', '维修员年龄'],
    ),
    TurtleSoupPuzzle(
      id: 'sealed_window_check',
      title: '从不打开的窗',
      surface: '工作人员每天进入房间后的第一件事都是检查窗户，却从来不打开它。为什么？',
      truth:
          '这是恒温恒湿的档案室，窗户必须保持密闭。工作人员检查窗框上的封条和结露情况，以确认密封与环境控制正常；打开窗户反而会破坏保存条件。',
      hints: ['检查的目的不是通风。', '房间里的环境需要与室外隔离。'],
      requiredTruthPoints: ['恒温恒湿档案室', '检查窗户密封状态'],
      reasoningDimensions: ['房间用途', '环境控制', '职业流程'],
      yesKeywords: ['档案', '恒温', '恒湿', '密封', '封条', '结露', '保存'],
      noKeywords: ['怕人逃走', '窗外危险', '窗户打不开', '监视'],
      irrelevantKeywords: ['楼层', '窗帘颜色', '工作人员姓名'],
    ),
    TurtleSoupPuzzle(
      id: 'empty_cup_watermark',
      title: '空杯下的水迹',
      surface: '桌上的空杯从未装过水，拿开后桌面却留下了一圈明显水迹。为什么？',
      truth: '空杯刚从低温冷藏柜中取出。室内温暖潮湿的空气接触冰冷杯壁后凝结成水珠，水珠沿杯壁流到底部，在桌面留下水圈；水并非来自杯内。',
      hints: ['水不是从杯口或杯内出来的。', '杯子与房间空气的温度差很重要。'],
      requiredTruthPoints: ['杯子此前处于低温环境', '空气水汽在杯壁冷凝', '水迹来自杯外冷凝水'],
      reasoningDimensions: ['温度', '环境湿度', '物理现象'],
      yesKeywords: ['冷藏', '低温', '冷凝', '水汽', '温差', '杯壁'],
      noKeywords: ['杯子漏水', '有人洒水', '桌面原本有水', '杯里冰块融化'],
      irrelevantKeywords: ['杯子颜色', '饮料口味', '桌子价格'],
    ),
    TurtleSoupPuzzle(
      id: 'midnight_greenhouse',
      title: '午夜温室的灯',
      surface: '植物园闭园后，温室每晚都会亮灯，值班员却说里面没有人，也不是忘了关灯。为什么？',
      truth: '温室种植着需要补光的热带幼苗。自动系统会根据当日光照不足，在夜间开启植物补光灯，并同时降低遮光帘，值班员只需远程确认设备状态。',
      hints: ['灯光服务的对象不一定是人。', '亮灯时间由当天的环境数据决定。'],
      requiredTruthPoints: ['热带幼苗', '自动补光系统', '当日光照不足', '夜间开启补光灯'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['人物', '时间', '环境', '设备'],
      yesKeywords: ['植物', '幼苗', '补光', '自动', '光照', '设备', '遮光帘'],
      noKeywords: ['有人加班', '忘关灯', '防盗', '拍电影'],
      irrelevantKeywords: ['票价', '值班员年龄', '游客人数'],
    ),
    TurtleSoupPuzzle(
      id: 'dry_raincoat',
      title: '雨夜里干燥的雨衣',
      surface: '暴雨夜，配送员进门时全身湿透，背包里的雨衣却完全干燥。他没有忘记带，也不是雨衣坏了。为什么？',
      truth:
          '配送员先穿雨衣护送怕水的文件到另一栋楼，返程前把湿雨衣留给同事继续使用；背包里的干雨衣是收件人归还的备用雨衣，并非他来程穿的那件。',
      hints: ['背包里的雨衣不是他来时使用的那件。', '途中发生了一次物品交接。'],
      requiredTruthPoints: ['护送怕水文件', '湿雨衣留给同事', '备用雨衣', '返程淋湿'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['物品', '时间顺序', '人物', '目的'],
      yesKeywords: ['文件', '同事', '另一件', '备用', '交换', '返程', '交接'],
      noKeywords: ['没穿雨衣', '雨衣漏水', '瞬间干燥', '放在家里'],
      irrelevantKeywords: ['品牌', '颜色', '配送费'],
    ),
    TurtleSoupPuzzle(
      id: 'silent_alarm',
      title: '没有响声的警报',
      surface: '展厅警报启动后没有发出任何声音，保安却立刻疏散了所有人，而且确认系统工作正常。为什么？',
      truth: '展厅当天举办听障观众专场。传感器触发的是闪光与手环震动警报，控制室同步收到分区位置；保安按无声疏散预案引导观众离场。',
      hints: ['警报不一定依赖声音。', '当天观众的沟通需求与平时不同。'],
      requiredTruthPoints: ['听障专场', '闪光与手环震动', '控制室分区提示', '无声疏散预案'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['人物', '设备', '环境', '流程'],
      yesKeywords: ['听障', '闪光', '震动', '手环', '控制室', '预案'],
      noKeywords: ['警报坏了', '演习', '保安猜到', '停电'],
      irrelevantKeywords: ['展品价格', '天气', '保安姓名'],
    ),
    TurtleSoupPuzzle(
      id: 'remote_meeting_room',
      title: '没有人的会议室',
      surface: '预约系统显示会议室正在使用，但整场会议期间房间里一直没有人。系统和门锁都没有故障。为什么？',
      truth:
          '团队预约的是会议室内的专用视频会议主机和授权线路，用来连接两地远程演示。设备按预约时间自动入会并占用会议室资源，所有参会者都从各自电脑接入，没有人需要进入房间。',
      hints: ['被使用的不一定是房间里的座位。', '预约同时保留了一套只能绑定该房间的设备资源。'],
      requiredTruthPoints: ['预约的是专用视频会议资源', '设备自动入会', '参会者全部远程接入'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['资源定义', '远程协作', '自动化', '空间'],
      yesKeywords: ['视频会议', '远程', '主机', '线路', '自动入会', '资源'],
      noKeywords: ['忘记取消', '系统故障', '有人隐身', '会议取消'],
      irrelevantKeywords: ['会议主题', '公司规模', '桌椅数量'],
    ),
    TurtleSoupPuzzle(
      id: 'lit_elevator_button',
      title: '一直亮着的电梯按钮',
      surface: '大楼某层的电梯呼叫按钮亮了很久，走廊里却没有人等电梯。物业说这是正常工作流程。为什么？',
      truth:
          '搬运团队正在用货运模式调度电梯。工作人员在仓库内通过无线终端持续预约该层，亮灯表示货梯下一次仍需返回此层装货；他们在防火门后的仓库等待，不站在走廊按钮旁。',
      hints: ['亮灯代表的请求仍然有效，但请求者不在按钮旁。', '这次电梯承担的是连续搬运任务。'],
      requiredTruthPoints: ['货运模式', '无线终端持续预约', '工作人员在仓库内等待', '电梯需反复返回装货'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['设备模式', '人物位置', '工作流程', '空间关系'],
      yesKeywords: ['货梯', '搬运', '无线终端', '预约', '仓库', '反复返回'],
      noKeywords: ['按钮卡住', '恶作剧', '有人离开', '电梯故障'],
      irrelevantKeywords: ['楼层数字', '货物价格', '按钮颜色'],
    ),
    TurtleSoupPuzzle(
      id: 'unopened_fragile_package',
      title: '没有打开的包裹',
      surface: '包裹封条完整，收件人却在拆箱前就确定里面一件东西已经坏了。为什么？',
      truth:
          '包裹里有一只带机械指针的精密仪表，发货人将指针锁在运输标记位置。透明观察窗从纸箱侧面的检查孔可见，收件人看到指针已脱离锁定位且箱内有松动零件声，因此能在不破坏封条的情况下确认仪表受损。',
      hints: ['损坏留下了可以从包装外观察到的迹象。', '包装专门留有运输检查窗口。'],
      requiredTruthPoints: ['内装机械仪表', '包装有外部观察孔', '指针脱离运输锁定位', '松动声进一步确认损坏'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['物品性质', '包装结构', '外部迹象', '运输流程'],
      yesKeywords: ['仪表', '指针', '观察窗', '检查孔', '锁定', '异响', '松动'],
      noKeywords: ['拆过再封', '透视能力', '快递员告知', '封条造假'],
      irrelevantKeywords: ['快递公司', '购买价格', '包裹颜色'],
    ),
    TurtleSoupPuzzle(
      id: 'midnight_auto_report',
      title: '凌晨打印的纸',
      surface: '办公室每天凌晨都会自动打印一张纸，没有员工操作，也没人认为浪费。为什么？',
      truth:
          '机房的备份系统每天凌晨完成数据校验后，会把校验摘要发送到独立的针式打印机。纸质报告用于值班人员早晨签字留档，并在网络故障时保留不可依赖服务器读取的备份记录；打印任务由计划程序自动触发。',
      hints: ['这张纸是某个夜间流程的结果。', '纸质形式是为了在电子系统不可用时仍能查验。'],
      requiredTruthPoints: ['夜间备份校验', '计划任务自动打印', '纸质摘要供签字留档', '网络故障时可独立查验'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['时间', '自动化', '设备', '审计流程'],
      yesKeywords: ['备份', '校验', '报告', '计划任务', '自动打印', '留档', '网络故障'],
      noKeywords: ['员工遥控', '打印机故障', '闹鬼', '广告'],
      irrelevantKeywords: ['纸张品牌', '字体', '办公室人数'],
    ),
    TurtleSoupPuzzle(
      id: 'empty_access_seat',
      title: '从未坐人的座位',
      surface: '公共阅览室每天都会特意留出一个没人坐的位置，即使其他座位已经坐满。为什么？',
      truth:
          '那是无障碍阅读设备旁的转移空间，不是普通座位。桌边必须留出轮椅转向和停靠的位置，地面上的座位编号用于预约整套无障碍工位；使用者坐在自己的轮椅上，所以那里始终不会摆椅子或有人坐下。',
      hints: ['被保留的是一块使用空间，不是一把空椅子。', '使用这套工位的人会带着自己的座位到来。'],
      requiredTruthPoints: ['无障碍阅读工位', '空位用于轮椅停靠转向', '使用者坐在自己的轮椅上'],
      difficulty: TurtleSoupDifficulty.normal,
      reasoningDimensions: ['空间用途', '无障碍设计', '人物行为', '公共设施'],
      yesKeywords: ['无障碍', '轮椅', '转向', '停靠', '阅读设备', '工位'],
      noKeywords: ['纪念座位', '有人占座', '座椅损坏', '工作人员专座'],
      irrelevantKeywords: ['书籍类型', '开放时间', '读者年龄'],
    ),
    TurtleSoupPuzzle(
      id: 'last_train_ticket',
      title: '末班车后的车票',
      surface: '末班车早已离站，一名乘客却在空站台买了一张当天有效的车票，随后满意地离开，并没有乘车。为什么？',
      truth:
          '乘客是事故调查的目击者。他需要用售票机生成带精确时间和站点编号的票据，证明自己按警方要求返回现场完成了时间校准；购票记录与站内故障时钟对照后成为证据，他随后从工作人员通道离开。',
      hints: ['车票的价值不在于乘车。', '票面记录的信息能校准另一项记录。'],
      requiredTruthPoints: ['事故目击者', '警方要求返回现场', '票据时间与站点编号', '校准故障时钟', '作为证据'],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['身份', '时间顺序', '物品用途', '动机', '证据'],
      yesKeywords: ['证据', '时间', '记录', '警方', '目击者', '校准', '站点'],
      noKeywords: ['收藏车票', '退票', '等人', '恶作剧'],
      irrelevantKeywords: ['票价', '列车颜色', '目的地'],
    ),
    TurtleSoupPuzzle(
      id: 'sealed_lunchbox',
      title: '未打开的午餐盒',
      surface: '实验室里，一个密封午餐盒从未被打开，却让研究员及时发现整栋楼出了问题。盒中食物也没有变质。为什么？',
      truth:
          '午餐盒带有会随气压变化凹陷的柔性密封盖。楼宇换气系统故障造成持续负压，研究员发现盒盖异常内凹；同层压力传感器恰在维护，他便用盒盖现象确认并上报，避免人员继续进入。',
      hints: ['异常来自盒子的外观，不来自食物。', '盒子反映了房间里一种看不见的环境变化。'],
      requiredTruthPoints: ['柔性密封盖', '楼内持续负压', '换气系统故障', '传感器维护', '盒盖异常用于确认'],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['物品性质', '环境', '设备故障', '因果', '安全流程'],
      yesKeywords: ['气压', '负压', '盒盖', '密封', '换气', '传感器', '通风'],
      noKeywords: ['食物有毒', '盒里有虫', '爆炸物', '有人打开'],
      irrelevantKeywords: ['食物口味', '午餐时间', '研究员年龄'],
    ),
    TurtleSoupPuzzle(
      id: 'shadowless_exhibit',
      title: '每晚消失的影子',
      surface: '展馆里一座固定雕塑每天夜里同一时刻看起来完全没有影子，工作人员却认为设备一切正常。为什么？',
      truth:
          '雕塑位于文物摄影校准区。闭馆后，环形轨道上的多组柔光灯会按程序依次亮起；到固定校准时刻，来自相反方向且亮度配平的灯同时照射，雕塑各方向的阴影被其他光源填亮。地面又是漫反射浅色材料，监控画面中几乎看不到明确投影。随后系统拍摄无阴影基准图，用于校准第二天的展品扫描设备。这是故意设计的正常流程，雕塑和灯都没有移动或故障。',
      hints: [
        '“没有影子”并不等于现场没有光。',
        '那个固定时刻，多于一个方向的照明同时发生作用。',
        '工作人员需要一张光照均匀的基准画面。',
      ],
      requiredTruthPoints: [
        '多方向柔光灯同时照射',
        '相反方向光线填平阴影',
        '浅色漫反射地面弱化投影',
        '固定时刻拍摄无阴影基准图',
        '用于扫描设备校准',
      ],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['光学', '多设备协同', '时间程序', '环境材料', '职业用途'],
      yesKeywords: ['多光源', '柔光', '相反方向', '补光', '漫反射', '基准图', '校准', '扫描'],
      noKeywords: ['雕塑透明', '灯全部关闭', '雕塑被移走', '监控故障'],
      irrelevantKeywords: ['雕塑作者', '门票价格', '展馆传说'],
    ),
    TurtleSoupPuzzle(
      id: 'virtual_train_record',
      title: '从未到站的列车记录',
      surface: '车站系统每天都记录同一班“列车”准时到站和离站，但它从未真正进入任何站台。为什么？',
      truth:
          '这是夜间上线前的虚拟测试车次。调度中心把一组不对应实体列车的测试车号注入生产系统的隔离通道，用来检查时刻表、广播、站台屏和换乘数据能否按完整流程联动。站台设备接收的是带测试标记的数据，只写入运维日志，不向乘客显示正式到站信息；测试结束后系统记录模拟到站与离站结果。列车不存在，因此不会占用轨道或进入站台，而每日记录是验证系统健康状态所必需的正常流程。',
      hints: [
        '“列车记录”不一定对应一组真实车厢。',
        '多套车站信息设备需要每天走完一次完整流程。',
        '这条记录带有只对运维人员可见的测试标记。',
      ],
      requiredTruthPoints: [
        '不存在实体列车的虚拟测试车次',
        '测试数据进入隔离调度通道',
        '广播与站台屏等系统完成联动检查',
        '测试标记阻止正式乘客信息发布',
        '到离站结果写入运维日志',
      ],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['虚拟实体', '调度系统', '自动化测试', '信息可见性', '运维流程'],
      yesKeywords: ['虚拟车次', '测试车号', '模拟', '调度', '广播', '站台屏', '联动', '运维日志'],
      noKeywords: ['幽灵列车', '列车晚点', '司机绕站', '记录造假'],
      irrelevantKeywords: ['列车颜色', '票价', '乘客目的地'],
    ),
    TurtleSoupPuzzle(
      id: 'scheduled_water_level',
      title: '没有泄漏的下降水位',
      surface: '封闭设施里的水位每天固定时间都会下降，工程师反复检查却确认没有任何泄漏。为什么？',
      truth:
          '设施是水族馆的循环展示系统。每天闭馆后，控制程序会把主展示池的一部分水泵入上方过滤与消毒储槽，使滤材反冲洗并完成紫外循环；因此主池液位按固定幅度下降。转移的水仍留在同一套封闭管路中，没有流失。清洗完成后，储槽水经温度和盐度复核再回流，开馆前主池恢复原水位。液位传感器测量的只是主池，不是整套系统的总水量，这一变化是故意安排的维护流程。',
      hints: [
        '水位下降不代表整套设施的水量减少。',
        '固定时间有设备把水送往另一个暂时看不见的位置。',
        '测量值只代表主池，不代表整个封闭循环。',
      ],
      requiredTruthPoints: [
        '封闭循环展示系统',
        '水被泵入过滤消毒储槽',
        '主池传感器不测系统总水量',
        '夜间反冲洗与紫外循环',
        '处理后水会回流恢复水位',
      ],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['测量范围', '液体转移', '自动设备', '时间流程', '维护目的'],
      yesKeywords: ['循环系统', '水泵', '储槽', '过滤', '消毒', '反冲洗', '回流', '传感器'],
      noKeywords: ['漏水', '蒸发', '有人取水', '传感器故障'],
      irrelevantKeywords: ['鱼的品种', '门票', '水池颜色'],
    ),
    TurtleSoupPuzzle(
      id: 'drifting_museum_display',
      title: '闭馆后移动的展品',
      surface: '每天闭馆后，展厅里一件展品的位置都会发生极小变化，监控确认没有人触碰，工作人员仍说这是正常现象。为什么？',
      truth:
          '展品是一座放在低摩擦精密转台上的机械模型。闭馆后空调进入节能模式，展柜内温度缓慢下降；转台金属支架和一侧较长的传动连杆发生不同程度的热收缩，使已解除驱动锁的台面产生很小角位移。解除锁定是为了避免温度变化把应力传给脆弱模型。清晨恒温恢复后，位置传感器会驱动转台回到基准点。监控中无人触碰属实，变化来自可预测的热胀冷缩与保护机构，并非设备故障。',
      hints: [
        '位置变化与闭馆后的环境控制有关。',
        '展品下方的支撑机构允许非常小的位移。',
        '允许移动是为了释放温度变化产生的机械应力。',
      ],
      requiredTruthPoints: [
        '展品位于低摩擦精密转台',
        '闭馆后温度下降',
        '不同金属部件热收缩产生角位移',
        '保护流程会解除驱动锁释放应力',
        '清晨传感器使转台回到基准点',
      ],
      difficulty: TurtleSoupDifficulty.hard,
      reasoningDimensions: ['温度环境', '材料形变', '机械结构', '保护流程', '测量与复位'],
      yesKeywords: ['转台', '低摩擦', '降温', '热收缩', '连杆', '解除锁定', '应力', '复位'],
      noKeywords: ['有人移动', '地震', '监控剪辑', '灵异', '设备损坏'],
      irrelevantKeywords: ['展品年代', '观众人数', '保安姓名'],
    ),
  ];

  static TurtleSoupPuzzle byId(String id) =>
      puzzles.firstWhere((item) => item.id == id, orElse: () => puzzles.first);

  static TurtleSoupPuzzle random([Random? random]) =>
      puzzles[(random ?? Random()).nextInt(puzzles.length)];

  static TurtleSoupPuzzle randomForParticipants(
    int participantCount, [
    Random? random,
  ]) {
    if (participantCount <= 1) {
      return random == null
          ? TurtleSoupPuzzleRegistry.random()
          : TurtleSoupPuzzleRegistry.random(random);
    }
    final preferred = puzzles
        .where((puzzle) => puzzle.difficulty != TurtleSoupDifficulty.easy)
        .toList(growable: false);
    final source = preferred.isEmpty ? puzzles : preferred;
    return source[(random ?? Random()).nextInt(source.length)];
  }

  static TurtleSoupPuzzle randomForParticipantsExcluding(
    int participantCount,
    String excludedPuzzleId, [
    Random? random,
  ]) {
    final eligible = participantCount <= 1
        ? puzzles
        : puzzles
              .where((puzzle) => puzzle.difficulty != TurtleSoupDifficulty.easy)
              .toList(growable: false);
    final withoutCurrent = eligible
        .where((puzzle) => puzzle.id != excludedPuzzleId)
        .toList(growable: false);
    final source = withoutCurrent.isEmpty ? eligible : withoutCurrent;
    return source[(random ?? Random()).nextInt(source.length)];
  }
}
