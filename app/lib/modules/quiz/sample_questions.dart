import '../../core/models/quiz.dart';

/// 内置示例题库（电力安全规程节选），便于首次使用体验。
List<Question> sampleQuestions(int bankId) {
  const chapter = '安全规程';
  final data = <(String, String, List<String>, String, String)>[
    (
      Question.typeSingle,
      '高压设备上工作需要全部停电或部分停电时，应填用（ ）。',
      ['第一种工作票', '第二种工作票', '带电作业工作票', '口头命令'],
      'A',
      '全部停电或部分停电的高压设备工作应填用第一种工作票。',
    ),
    (
      Question.typeSingle,
      '登杆塔作业前，应首先检查（ ）。',
      ['杆根、基础和拉线', '导线弧垂', '绝缘子串', '金具'],
      'A',
      '登塔前先检查杆根、基础、拉线是否牢固，确认后方可攀登。',
    ),
    (
      Question.typeSingle,
      '在带电线路杆塔上工作，作业人员与220kV带电导线的最小安全距离为（ ）。',
      ['1.5米', '3.0米', '4.0米', '5.0米'],
      'B',
      '220kV 最小安全距离为 3.0 米。',
    ),
    (
      Question.typeSingle,
      '安全带使用时应（ ），并挂在牢固的构件上。',
      ['低挂高用', '高挂低用', '平挂平用', '随意悬挂'],
      'B',
      '安全带应高挂低用，减小坠落冲击距离。',
    ),
    (
      Question.typeMulti,
      '下列属于“三违”行为的有（ ）。',
      ['违章指挥', '违章作业', '违反劳动纪律', '违反操作规程以外的行为不属于三违'],
      'ABC',
      '三违：违章指挥、违章作业、违反劳动纪律。',
    ),
    (
      Question.typeMulti,
      '停电作业的技术措施包括（ ）。',
      ['停电', '验电', '装设接地线', '悬挂标示牌和装设遮栏'],
      'ABCD',
      '保证安全的技术措施：停电、验电、装设接地线、悬挂标示牌和装设遮栏。',
    ),
    (
      Question.typeJudge,
      '雷雨天气禁止在杆塔上进行检修作业。',
      [],
      'A',
      '雷雨、大风等恶劣天气应停止高空和户外检修作业。',
    ),
    (
      Question.typeJudge,
      '验电时可以使用低于线路电压等级的验电器。',
      [],
      'B',
      '验电器电压等级必须与被验设备电压等级相符。',
    ),
    (
      Question.typeJudge,
      '新参加电气工作的人员，经过安全知识教育后即可单独上岗作业。',
      [],
      'B',
      '新人员须经培训考试合格，并在有经验人员带领下工作，不得单独作业。',
    ),
    (
      Question.typeJudge,
      '杆塔上作业时，工具和材料应用绳索传递，禁止上下抛掷。',
      [],
      'A',
      '上下传递工具材料应使用绳索，严禁抛掷，防止高空坠物伤人。',
    ),
  ];
  return [
    for (var i = 0; i < data.length; i++)
      Question(
        bankId: bankId,
        type: data[i].$1,
        chapter: chapter,
        stem: data[i].$2,
        options: data[i].$1 == Question.typeJudge
            ? const ['正确', '错误']
            : data[i].$3,
        answer: data[i].$4,
        analysis: data[i].$5,
        seq: i + 1,
      ),
  ];
}
