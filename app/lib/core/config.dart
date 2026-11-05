/// 底图来源。一个来源可包含多层瓦片（如影像 + 注记）。
class MapSource {
  const MapSource({
    required this.label,
    required this.attribution,
    this.urls = const [],
    this.subdomains = const [],
    this.maxZoom = 18,
  });

  final String label;
  final String attribution;

  /// 空列表表示不加载底图，只显示线路与杆塔。
  final List<String> urls;
  final List<String> subdomains;
  final double maxZoom;
}

/// 全局配置。
class AppConfig {
  AppConfig._();

  static const String appName = '线路工具箱';

  /// OpenStreetMap 公共瓦片（无需 key）。
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// 天地图 key。构建时可用 `--dart-define=TIANDITU_KEY=xxx` 覆盖。
  static const String tiandituKey = String.fromEnvironment(
    'TIANDITU_KEY',
    defaultValue: '47a4007320d35d3a500f8b27ed3570d1',
  );

  static const List<String> tiandituSubdomains = ['0', '1', '2', '3', '4', '5', '6', '7'];

  static const String tiandituImageUrl =
      'https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey';

  static const String tiandituVectorUrl =
      'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey';

  /// 天地图影像注记（地名、道路），与影像层叠加显示。
  static const String tiandituImageLabelUrl =
      'https://t{s}.tianditu.gov.cn/cia_w/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=cia&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey';

  /// 天地图矢量注记，与矢量层叠加显示。
  static const String tiandituVectorLabelUrl =
      'https://t{s}.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey';

  static const String esriImageUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/'
      'MapServer/tile/{z}/{y}/{x}';

  static const String cartoDarkUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const String cartoLightUrl =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
  static const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];

  /// 底图列表，顺序即菜单顺序（默认第一项）。
  static const List<MapSource> mapSources = [
    MapSource(
      label: '天地图影像 + 注记',
      attribution: '天地图',
      urls: [tiandituImageUrl, tiandituImageLabelUrl],
      subdomains: tiandituSubdomains,
    ),
    MapSource(
      label: '天地图矢量 + 注记',
      attribution: '天地图',
      urls: [tiandituVectorUrl, tiandituVectorLabelUrl],
      subdomains: tiandituSubdomains,
    ),
    MapSource(
      label: 'ESRI 卫星影像',
      attribution: 'Esri',
      urls: [esriImageUrl],
      maxZoom: 18,
    ),
    MapSource(
      label: 'Carto 深色',
      attribution: 'CARTO',
      urls: [cartoDarkUrl],
      subdomains: cartoSubdomains,
      maxZoom: 19,
    ),
    MapSource(
      label: 'Carto 浅色',
      attribution: 'CARTO',
      urls: [cartoLightUrl],
      subdomains: cartoSubdomains,
      maxZoom: 19,
    ),
    MapSource(
      label: 'OSM 标准',
      attribution: 'OpenStreetMap',
      urls: [osmTileUrl],
      maxZoom: 19,
    ),
    MapSource(label: '无底图（仅线路）', attribution: ''),
  ];

  static const String userAgentPackageName = 'com.ckh.xianlu_toolbox';

  /// 照片自动匹配杆塔的默认距离阈值（米）。
  static const double defaultMatchThreshold = 100;

  /// 默认底图下标：无 key 时退到 OSM。
  static int get defaultSourceIndex {
    if (tiandituKey.isEmpty) {
      return mapSources.indexWhere((source) => source.label == 'OSM 标准');
    }
    return 0;
  }
}
