import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config.dart';
import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';
import '../../core/utils/geo.dart';
import '../flaw/flaw_list_page.dart';
import '../line/line_list_page.dart';
import '../photo/photo_page.dart';
import '../quiz/quiz_page.dart';
import '../tower/tower_edit_page.dart';

/// 线路地图。[line] 为空时展示全部线路与杆塔（应用首页）。
class MapPage extends StatefulWidget {
  const MapPage({super.key, this.line});

  final Line? line;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const List<Color> _lineColors = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFC62828),
  ];

  /// 低于该缩放级别只画小圆点（轻量），达到后才绘制文字标注。
  static const double _labelZoom = 14;

  /// 视口外扩比例，避免标注在边缘突然弹出。
  static const double _boundsPadding = 0.25;

  final MapController _mapController = MapController();
  List<Line> _lines = [];
  List<Tower> _towers = [];
  Map<int, Line> _lineById = {};
  Map<int, Color> _colorByLineId = {};
  bool _loading = true;
  bool _measureMode = false;
  List<LatLng> _measurePoints = [];
  int _sourceIndex = AppConfig.defaultSourceIndex;
  int _tileErrors = 0;
  bool _tileErrorNotified = false;

  // 渲染缓存：只有数据、缩放级别或视口变化时才重建，拖动时不再重复计算。
  List<Tower> _locatedTowers = [];
  List<Polyline> _linePolylines = [];
  List<Marker> _towerMarkers = [];
  double _zoom = 4.5;
  LatLngBounds? _visibleBounds;
  bool _mapReady = false;

  // 实时定位。
  StreamSubscription<Position>? _positionSub;
  Position? _position;
  bool _followLocation = false;
  bool _locationBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<Line> lines;
    List<Tower> towers;
    if (widget.line != null) {
      lines = [widget.line!];
      towers = await Repo.towers(widget.line!.id);
    } else {
      lines = await Repo.lines();
      towers = await Repo.towers();
    }
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _towers = towers;
      _loading = false;
      _lineById = {
        for (final line in lines)
          if (line.id != null) line.id!: line,
      };
      _colorByLineId = {
        for (var i = 0; i < lines.length; i++)
          if (lines[i].id != null)
            lines[i].id!: _lineColors[i % _lineColors.length],
      };
      _rebuildRenderCache();
    });
  }

  /// 数据变化后重建折线与标注缓存（进入页面 / 编辑返回时各一次）。
  void _rebuildRenderCache() {
    _locatedTowers = _towers.where((t) => t.hasCoordinate).toList();

    final polylines = <Polyline>[];
    final towersByLine = <int, List<LatLng>>{};
    for (final tower in _locatedTowers) {
      towersByLine
          .putIfAbsent(tower.lineId, () => [])
          .add(LatLng(tower.lat, tower.lng));
    }
    for (final line in _lines) {
      final points = towersByLine[line.id];
      if (points == null || points.length < 2) continue;
      polylines.add(
        Polyline(
          points: points,
          strokeWidth: 3.5,
          color: _colorByLineId[line.id] ?? _lineColors.first,
        ),
      );
    }
    _linePolylines = polylines;

    if (!_mapReady) {
      _zoom = _initialZoom;
      _visibleBounds = null;
    }
    _rebuildMarkers();
  }

  /// 按当前缩放级别重建杆塔标注：
  /// 小比例尺画圆点（几百基也不卡），大比例尺只对视口内的杆塔画文字标注。
  void _rebuildMarkers() {
    final towers = _locatedTowers;
    if (towers.isEmpty) {
      _towerMarkers = [];
      return;
    }

    if (_zoom < _labelZoom) {
      _towerMarkers = [
        for (final tower in towers)
          Marker(
            point: LatLng(tower.lat, tower.lng),
            width: 18,
            height: 18,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showTowerSheet(tower),
              child: Center(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorByLineId[tower.lineId] ?? _lineColors.first,
                    border: Border.all(color: Colors.white, width: 1.6),
                  ),
                ),
              ),
            ),
          ),
      ];
      return;
    }

    final bounds = _visibleBounds;
    final visible = bounds == null
        ? towers
        : towers
            .where(
              (tower) => _padded(bounds).contains(LatLng(tower.lat, tower.lng)),
            )
            .toList();
    _towerMarkers = [
      for (final tower in visible)
        Marker(
          point: LatLng(tower.lat, tower.lng),
          width: 150,
          height: 16,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showTowerSheet(tower),
            child: Center(
              child: Text(
                _towerLabel(tower),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(blurRadius: 4, color: Colors.black87),
                    Shadow(blurRadius: 2, color: Colors.black),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  static LatLngBounds _padded(LatLngBounds bounds) {
    final dLat = (bounds.north - bounds.south) * _boundsPadding;
    final dLng = (bounds.east - bounds.west) * _boundsPadding;
    return LatLngBounds(
      LatLng(bounds.south - dLat, bounds.west - dLng),
      LatLng(bounds.north + dLat, bounds.east + dLng),
    );
  }

  /// 地图视野变化：跨过标注阈值或在标注模式下平移时才重建标注。
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    var changed = false;
    if (hasGesture && _followLocation) {
      _followLocation = false;
      changed = true;
    }
    final wasLabelMode = _zoom >= _labelZoom;
    final isLabelMode = camera.zoom >= _labelZoom;
    _zoom = camera.zoom;
    _visibleBounds = camera.visibleBounds;
    if (wasLabelMode != isLabelMode || isLabelMode) {
      _rebuildMarkers();
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  LatLng get _initialCenter {
    final located = _locatedTowers;
    if (located.isEmpty) return const LatLng(30.5, 110.0);
    return LatLng(located.first.lat, located.first.lng);
  }

  double get _initialZoom => _locatedTowers.isEmpty ? 4.5 : 13;

  double get _measureLength {
    var total = 0.0;
    for (var i = 1; i < _measurePoints.length; i++) {
      total += distanceMeters(
        _measurePoints[i - 1].latitude,
        _measurePoints[i - 1].longitude,
        _measurePoints[i].latitude,
        _measurePoints[i].longitude,
      );
    }
    return total;
  }

  /// 线路显示名，如「220kV白树牵线」。
  String _lineLabel(Line line) {
    final voltage = line.voltage.trim();
    if (voltage.isEmpty) return line.name;
    final hasUnit = voltage.toLowerCase().contains('kv');
    return '${hasUnit ? voltage : '${voltage}kV'}${line.name}';
  }

  /// 杆塔显示名，如「220kV白树牵线#1」。
  String _towerLabel(Tower tower) {
    final no = tower.towerNo.trim();
    final prefix = RegExp(r'^[0-9]').hasMatch(no) ? '#' : '';
    final line = _lineById[tower.lineId];
    return '${line == null ? '' : _lineLabel(line)}$prefix$no';
  }

  void _fitTowers() {
    final located = _locatedTowers;
    if (located.length < 2) return;
    final points = located.map((t) => LatLng(t.lat, t.lng)).toList();
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
        maxZoom: widget.line == null ? 14 : 16,
      ),
    );
  }

  // ---------- 实时定位 ----------

  Future<void> _onLocationButton() async {
    if (_positionSub == null) {
      await _enableLocation();
      return;
    }
    final position = _position;
    if (position != null && _mapReady) {
      setState(() => _followLocation = true);
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _zoom < 15 ? 16 : _zoom,
      );
    }
  }

  Future<void> _enableLocation() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('定位服务未开启，请在系统设置中打开 GPS');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _toast('未授予定位权限');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _toast('定位权限被拒绝，请在系统设置中为本应用开启定位');
        await Geolocator.openAppSettings();
        return;
      }

      // 先取一次当前位置快速上图，不等流式更新。
      try {
        final quick = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        _onPosition(quick, center: true);
      } catch (_) {
        // 超时无所谓，等位置流推送。
      }

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen(
        _onPosition,
        onError: (Object error) => _toast('定位更新失败：$error'),
      );
      if (mounted) setState(() => _followLocation = true);
      _toast('已开启实时定位，长按定位按钮可关闭');
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  void _onPosition(Position position, {bool center = false}) {
    if (!mounted) return;
    setState(() => _position = position);
    if ((center || _followLocation) && _mapReady) {
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _zoom < 15 ? 16 : _zoom,
      );
    }
  }

  void _stopLocation() {
    _positionSub?.cancel();
    _positionSub = null;
    setState(() {
      _position = null;
      _followLocation = false;
    });
    _toast('已关闭实时定位');
  }

  // ---------- 其余交互 ----------

  Future<void> _search() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('查找杆塔'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入杆塔号或线路名称，支持部分匹配',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('查找'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.trim().isEmpty) return;
    final keyword = query.trim().toLowerCase();
    Tower? found;
    for (final tower in _locatedTowers) {
      final label = _towerLabel(tower).toLowerCase();
      if (label.contains(keyword)) {
        found = tower;
        break;
      }
    }
    if (found == null) {
      _toast('未找到杆塔“${query.trim()}”');
      return;
    }
    _mapController.move(LatLng(found.lat, found.lng), 17);
    _showTowerSheet(found);
  }

  void _showTowerSheet(Tower tower) {
    final line = _lineById[tower.lineId];
    final lineTowers = _towers.where((t) => t.lineId == tower.lineId).toList();
    final index = lineTowers.indexOf(tower);
    final previous = index > 0 ? lineTowers[index - 1] : null;
    final distance = previous != null &&
            previous.hasCoordinate &&
            tower.hasCoordinate
        ? distanceMeters(previous.lat, previous.lng, tower.lat, tower.lng)
        : null;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _towerLabel(tower),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (line != null)
                Text(
                  '线路：${line.name}'
                  '${line.voltage.isEmpty ? '' : ' · ${line.voltage}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Text(
                '坐标：${formatLngLat(tower.lng)}, ${formatLngLat(tower.lat)}',
              ),
              if (tower.elevation > 0)
                Text('高程：${tower.elevation.toStringAsFixed(1)} m'),
              if (tower.towerType.isNotEmpty) Text('塔型：${tower.towerType}'),
              if (distance != null)
                Text('与上一基间距：${formatDistance(distance)}'),
              if (tower.remark.isNotEmpty) Text('备注：${tower.remark}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (line != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _editTower(tower, line);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑'),
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _mapController.move(LatLng(tower.lat, tower.lng), 18);
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('定位'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTower(Tower tower, Line line) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TowerEditPage(line: line, tower: tower),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  void _toggleMeasure() {
    setState(() {
      _measureMode = !_measureMode;
      if (!_measureMode) {
        _measurePoints = [];
      }
    });
    if (_measureMode) {
      _toast('已开启测距：长按地图添加测点');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 底图瓦片连续加载失败时自动切换到 OSM。
  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    _tileErrors++;
    if (_tileErrors < 3 || _tileErrorNotified) return;
    _tileErrorNotified = true;
    final osmIndex =
        AppConfig.mapSources.indexWhere((source) => source.label == 'OSM 标准');
    if (_sourceIndex != osmIndex && osmIndex >= 0) {
      setState(() {
        _sourceIndex = osmIndex;
        _tileErrors = 0;
      });
      _toast('底图加载失败，已切换到 OSM 标准底图');
    } else {
      _toast('底图加载失败，请检查手机网络或切换其他底图');
    }
  }

  Future<void> _openPage(String route) async {
    Widget page;
    switch (route) {
      case 'ledger':
        page = const LineListPage();
      case 'photo':
        page = const PhotoPage();
      case 'flaw':
        page = const FlawListPage();
      case 'quiz':
        page = const QuizPage();
      default:
        return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  PopupMenuButton<int> _buildSourceMenu() {
    return PopupMenuButton<int>(
      tooltip: '切换底图',
      icon: const Icon(Icons.layers_outlined),
      initialValue: _sourceIndex,
      onSelected: (value) => setState(() {
        _sourceIndex = value;
        _tileErrors = 0;
        _tileErrorNotified = false;
      }),
      itemBuilder: (_) => [
        for (var i = 0; i < AppConfig.mapSources.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: i == _sourceIndex
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
                Text(AppConfig.mapSources[i].label),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildTileLayers() {
    final source = AppConfig.mapSources[_sourceIndex];
    return [
      for (var i = 0; i < source.urls.length; i++)
        TileLayer(
          key: ValueKey('$_sourceIndex-$i'),
          urlTemplate: source.urls[i],
          subdomains: source.subdomains,
          userAgentPackageName: AppConfig.userAgentPackageName,
          maxZoom: source.maxZoom,
          errorTileCallback: i == 0 ? _onTileError : null,
        ),
    ];
  }

  PopupMenuButton<String> _buildMainMenu() {
    return PopupMenuButton<String>(
      tooltip: '更多功能',
      icon: const Icon(Icons.menu),
      onSelected: _openPage,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'ledger',
          child: _MenuItem(icon: Icons.list_alt, text: '线路台账'),
        ),
        PopupMenuItem(
          value: 'photo',
          child: _MenuItem(icon: Icons.photo_library_outlined, text: '照片归档'),
        ),
        PopupMenuItem(
          value: 'flaw',
          child: _MenuItem(icon: Icons.report_gmailerrorred_outlined, text: '缺陷记录'),
        ),
        PopupMenuItem(
          value: 'quiz',
          child: _MenuItem(icon: Icons.quiz_outlined, text: '刷题练习'),
        ),
      ],
    );
  }

  /// 定位蓝点与精度圈图层。
  List<Widget> _buildLocationLayers() {
    final position = _position;
    if (position == null) return const [];
    final point = LatLng(position.latitude, position.longitude);
    return [
      if (position.accuracy > 0)
        CircleLayer(
          circles: [
            CircleMarker(
              point: point,
              radius: position.accuracy,
              useRadiusInMeter: true,
              color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
              borderColor: const Color(0xFF1E88E5).withValues(alpha: 0.4),
              borderStrokeWidth: 1,
            ),
          ],
        ),
      MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 24,
            height: 24,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E88E5),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(blurRadius: 6, color: Colors.black38),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final located = _locatedTowers;
    final source = AppConfig.mapSources[_sourceIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.line?.name ?? '线路地图'),
        actions: [
          IconButton(
            tooltip: '查找杆塔',
            onPressed: _search,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: _measureMode ? '关闭测距' : '测距',
            onPressed: _toggleMeasure,
            icon: Icon(_measureMode ? Icons.straighten : Icons.straighten_outlined),
          ),
          IconButton(
            tooltip: '适应全部杆塔',
            onPressed: _fitTowers,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          _buildSourceMenu(),
          if (widget.line == null) _buildMainMenu(),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : GestureDetector(
              onLongPress: _positionSub != null ? _stopLocation : null,
              child: FloatingActionButton(
                onPressed: _locationBusy ? null : _onLocationButton,
                child: _locationBusy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        _positionSub == null
                            ? Icons.my_location
                            : _followLocation
                                ? Icons.gps_fixed
                                : Icons.gps_not_fixed,
                      ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Container(color: const Color(0xFF263238)),
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialCenter,
                    initialZoom: _initialZoom,
                    onMapReady: () {
                      _mapReady = true;
                      _zoom = _mapController.camera.zoom;
                      _visibleBounds = _mapController.camera.visibleBounds;
                      _fitTowers();
                      setState(_rebuildMarkers);
                    },
                    onPositionChanged: _onPositionChanged,
                    onLongPress: (tapPosition, point) {
                      if (!_measureMode) return;
                      setState(() => _measurePoints.add(point));
                    },
                  ),
                  children: [
                    ..._buildTileLayers(),
                    if (_linePolylines.isNotEmpty)
                      PolylineLayer(polylines: _linePolylines),
                    if (_towerMarkers.isNotEmpty)
                      MarkerLayer(markers: _towerMarkers),
                    ..._buildLocationLayers(),
                    if (_measurePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _measurePoints,
                            strokeWidth: 3,
                            color: const Color(0xFFE65100),
                            pattern: StrokePattern.dashed(segments: const [10, 6]),
                          ),
                        ],
                      ),
                    if (_measurePoints.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (var i = 0; i < _measurePoints.length; i++)
                            Marker(
                              point: _measurePoints[i],
                              width: 24,
                              height: 24,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE65100),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (source.attribution.isNotEmpty)
                      SimpleAttributionWidget(source: Text(source.attribution)),
                  ],
                ),
                if (located.isEmpty)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _lines.isEmpty
                              ? '暂无线路数据。点右上角菜单 →「线路台账」导入 Excel 或 KML。'
                              : '线路暂无有效杆塔坐标，请先在台帐中补充经纬度。',
                        ),
                      ),
                    ),
                  ),
                if (_zoom < _labelZoom && located.isNotEmpty)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          '放大地图查看杆塔名称',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                if (_measureMode)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      child: Card(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '测距：${formatDistance(_measureLength)}'
                                  '（${_measurePoints.length} 个测点）\n'
                                  '长按地图添加测点，点右上角尺子退出',
                                ),
                              ),
                              TextButton(
                                onPressed: _measurePoints.isEmpty
                                    ? null
                                    : () => setState(() => _measurePoints = []),
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(text),
      ],
    );
  }
}
