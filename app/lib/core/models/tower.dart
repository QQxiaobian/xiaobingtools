class Tower {
  final int? id;
  final int lineId;
  final String towerNo;
  final double lng;
  final double lat;
  final double elevation;
  final String towerType;
  final int seq;
  final String remark;

  const Tower({
    this.id,
    required this.lineId,
    required this.towerNo,
    required this.lng,
    required this.lat,
    this.elevation = 0,
    this.towerType = '',
    this.seq = 0,
    this.remark = '',
  });

  factory Tower.fromMap(Map<String, Object?> map) => Tower(
        id: map['id'] as int?,
        lineId: (map['line_id'] as int?) ?? 0,
        towerNo: (map['tower_no'] as String?) ?? '',
        lng: _double(map['lng']),
        lat: _double(map['lat']),
        elevation: _double(map['elevation']),
        towerType: (map['tower_type'] as String?) ?? '',
        seq: (map['seq'] as int?) ?? 0,
        remark: (map['remark'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'line_id': lineId,
        'tower_no': towerNo,
        'lng': lng,
        'lat': lat,
        'elevation': elevation,
        'tower_type': towerType,
        'seq': seq,
        'remark': remark,
      };

  Tower copyWith({
    int? id,
    int? lineId,
    String? towerNo,
    double? lng,
    double? lat,
    double? elevation,
    String? towerType,
    int? seq,
    String? remark,
  }) {
    return Tower(
      id: id ?? this.id,
      lineId: lineId ?? this.lineId,
      towerNo: towerNo ?? this.towerNo,
      lng: lng ?? this.lng,
      lat: lat ?? this.lat,
      elevation: elevation ?? this.elevation,
      towerType: towerType ?? this.towerType,
      seq: seq ?? this.seq,
      remark: remark ?? this.remark,
    );
  }

  bool get hasCoordinate => lat != 0 || lng != 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
