import 'package:flutter_test/flutter_test.dart';
import 'package:xianlu_toolbox/core/utils/geo.dart';

void main() {
  test('两点距离计算与格式化', () {
    final distance = distanceMeters(23.129163, 113.264512, 23.130163, 113.264512);
    expect(distance, greaterThan(100));
    expect(distance, lessThan(120));
    expect(formatDistance(1234), '1.23 km');
    expect(formatDistance(80), '80 m');
  });
}
