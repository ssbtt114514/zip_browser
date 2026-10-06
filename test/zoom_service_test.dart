import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zip_browser/services/zoom_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认倍率为 100%，标签格式为百分比', () async {
    final z = await ZoomService.create();
    expect(z.defaultZoom, 1.0);
    expect(ZoomService.label(1.0), '100%');
    expect(ZoomService.label(1.25), '125%');
    expect(ZoomService.label(0.8), '80%');
  });

  test('originOf 正确处理各种地址', () {
    expect(ZoomService.originOf(''), isNull);
    expect(ZoomService.originOf('about:home'), isNull);
    expect(ZoomService.originOf('data:text/html,hi'), isNull);
    expect(ZoomService.originOf('blob:https://a.com/x'), isNull);
    expect(ZoomService.originOf('https://a.com/path?q=1'), 'https://a.com');
    expect(ZoomService.originOf('http://a.com:8080/x'), 'http://a.com:8080');
  });

  test('按站点记忆缩放，同站点不同路径共享倍率', () async {
    final z = await ZoomService.create();
    await z.setForUrl('https://example.com/a', 1.5);
    expect(z.forUrl('https://example.com/b'), 1.5);
    expect(z.forUrl('https://other.com/'), 1.0);
    expect(z.siteZooms['https://example.com'], 1.5);
  });

  test('恢复到默认倍率时清除站点记录', () async {
    final z = await ZoomService.create();
    await z.setForUrl('https://example.com/', 2.0);
    expect(z.siteZooms.containsKey('https://example.com'), isTrue);
    await z.setForUrl('https://example.com/', 1.0);
    expect(z.siteZooms.containsKey('https://example.com'), isFalse);
  });

  test('倍率被钳制在合法区间', () async {
    final z = await ZoomService.create();
    await z.setForUrl('https://a.com/', 99);
    expect(z.forUrl('https://a.com/'), ZoomService.maxZoom);
    await z.setForUrl('https://a.com/', 0.001);
    expect(z.forUrl('https://a.com/'), ZoomService.minZoom);
  });

  test('档位上下调整并在边界收敛', () async {
    final z = await ZoomService.create();
    expect(z.stepUp(1.0), greaterThan(1.0));
    expect(z.stepDown(1.0), lessThan(1.0));
    expect(z.stepDown(0.25), ZoomService.minZoom);
    expect(z.stepUp(5.0), ZoomService.maxZoom);
    // 连续上调最终停在最大值
    var v = 1.0;
    for (var i = 0; i < 40; i++) {
      v = z.stepUp(v);
    }
    expect(v, ZoomService.maxZoom);
  });

  test('关闭按站点记忆后回退到默认倍率', () async {
    final z = await ZoomService.create();
    await z.setForUrl('https://example.com/', 2.0);
    await z.setDefaultZoom(1.1);
    await z.setPerSiteEnabled(false);
    expect(z.forUrl('https://example.com/'), 1.1);
  });

  test('注入脚本：100% 清除内联样式，其它倍率写入 zoom', () {
    expect(ZoomService.scriptFor(1.0), contains('removeProperty'));
    expect(ZoomService.scriptFor(1.5), contains("'1.5'"));
    // 极端值同样被钳制
    expect(ZoomService.scriptFor(100), contains("'${ZoomService.maxZoom}'"));
  });

  test('持久化：重新创建服务后仍保留站点倍率', () async {
    final first = await ZoomService.create();
    await first.setForUrl('https://persist.com/', 1.75);

    final second = await ZoomService.create();
    expect(second.forUrl('https://persist.com/'), 1.75);
  });
}
