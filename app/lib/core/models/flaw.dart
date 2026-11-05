/// 缺陷等级按南网设备缺陷定级思路设置，可在 [levels] 中扩展。
class Flaw {
  static const List<String> levels = ['一般', '严重', '危急'];
  static const List<String> parts = [
    '导线',
    '地线',
    '绝缘子',
    '金具',
    '杆塔本体',
    '基础',
    '接地装置',
    '通道环境',
    '其他',
  ];

  final int? id;
  final int lineId;
  final String lineName;
  final int? towerId;
  final String towerNo;
  final String part;
  final String level;
  final String description;
  final String photoPath;
  final String createdAt;

  const Flaw({
    this.id,
    required this.lineId,
    required this.lineName,
    this.towerId,
    this.towerNo = '',
    this.part = '',
    this.level = '一般',
    this.description = '',
    this.photoPath = '',
    required this.createdAt,
  });

  factory Flaw.fromMap(Map<String, Object?> map) => Flaw(
        id: map['id'] as int?,
        lineId: (map['line_id'] as int?) ?? 0,
        lineName: (map['line_name'] as String?) ?? '',
        towerId: map['tower_id'] as int?,
        towerNo: (map['tower_no'] as String?) ?? '',
        part: (map['part'] as String?) ?? '',
        level: (map['level'] as String?) ?? '一般',
        description: (map['description'] as String?) ?? '',
        photoPath: (map['photo_path'] as String?) ?? '',
        createdAt: (map['created_at'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'line_id': lineId,
        'line_name': lineName,
        'tower_id': towerId,
        'tower_no': towerNo,
        'part': part,
        'level': level,
        'description': description,
        'photo_path': photoPath,
        'created_at': createdAt,
      };

  Flaw copyWith({
    int? id,
    int? lineId,
    String? lineName,
    int? towerId,
    String? towerNo,
    String? part,
    String? level,
    String? description,
    String? photoPath,
    String? createdAt,
  }) {
    return Flaw(
      id: id ?? this.id,
      lineId: lineId ?? this.lineId,
      lineName: lineName ?? this.lineName,
      towerId: towerId ?? this.towerId,
      towerNo: towerNo ?? this.towerNo,
      part: part ?? this.part,
      level: level ?? this.level,
      description: description ?? this.description,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
