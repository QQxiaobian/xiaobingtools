class Line {
  final int? id;
  final String name;
  final String voltage;
  final String team;
  final String startTower;
  final String endTower;
  final String remark;

  const Line({
    this.id,
    required this.name,
    this.voltage = '',
    this.team = '',
    this.startTower = '',
    this.endTower = '',
    this.remark = '',
  });

  factory Line.fromMap(Map<String, Object?> map) => Line(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        voltage: (map['voltage'] as String?) ?? '',
        team: (map['team'] as String?) ?? '',
        startTower: (map['start_tower'] as String?) ?? '',
        endTower: (map['end_tower'] as String?) ?? '',
        remark: (map['remark'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'voltage': voltage,
        'team': team,
        'start_tower': startTower,
        'end_tower': endTower,
        'remark': remark,
      };

  Line copyWith({
    int? id,
    String? name,
    String? voltage,
    String? team,
    String? startTower,
    String? endTower,
    String? remark,
  }) {
    return Line(
      id: id ?? this.id,
      name: name ?? this.name,
      voltage: voltage ?? this.voltage,
      team: team ?? this.team,
      startTower: startTower ?? this.startTower,
      endTower: endTower ?? this.endTower,
      remark: remark ?? this.remark,
    );
  }
}
