import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/plugin/ffi_kernel_loader.dart';

/// 用 App 真实的 FFI 加载器加载预编译内核 DLL，端到端验证 ABI 契约：
///   打开库（校验 zb_abi_version）→ 建立宿主回调 → 绑定表面 → load_url
///   → tick 出帧 → 读取帧缓冲确认真的画了东西 → eval_js / 输入事件 / 导航。
///
/// 这是唯一能同时验证「C 内核实现」与「Dart 侧 ABI 绑定」是否彼此吻合的手段：
/// 只编译 C 自检程序，验证不到 Dart 侧的 `Pointer<NativeFunction<...>>` 类型、
/// 回调签名、字符串所有权（zb_free_ptr）是否对得上。
///
/// 仅在 Windows 且预编译 DLL 存在时运行；其它平台自动跳过。
void main() {
  const dllPath =
      'example_plugins/lite_kernel/kernels/windows/zb_lite_kernel.dll';
  final runnable = Platform.isWindows && File(dllPath).existsSync();
  final skipReason = runnable
      ? null
      : '仅 Windows 且存在 $dllPath 时运行（其它平台请先跑 tool/build_lite_kernel.sh）';

  const sampleHtml = '''
<!DOCTYPE html>
<html><head><title>轻量内核集成测试</title></head>
<body>
  <h1>Hello Lite Kernel</h1>
  <p>这是一段用来验证自动换行与点阵渲染的正文文本，English words wrap here.</p>
  <p><a href="https://example.com/next">下一页链接</a></p>
  <ul><li>列表项一</li><li>列表项二</li></ul>
  <hr>
  <blockquote>引用段落</blockquote>
</body></html>
''';

  test('FFI 内核：ABI 版本、导航状态与脚本命令', () async {
    final link = FfiKernelLink.open(
      libraryPath: dllPath,
      configJson: jsonEncode({'tab_id': 'integration_test'}),
      onHostDispatch: (requestId, method, params) {
        // 内核不应在纯离线渲染路径上主动请求宿主能力
      },
    );
    addTearDown(link.dispose);

    // 打开成功本身就证明 zb_abi_version() == kHostFfiAbiVersion
    expect(link.name, isNotNull);
    expect(link.name, isNotEmpty);
    expect(link.version, isNotNull);

    // 直接喂 HTML（宿主对 data: URL 就是这么做的）
    expect(link.loadUrl(sampleHtml), isTrue);
    expect(link.tick(), 0);

    expect(link.title, '轻量内核集成测试');
    expect(link.currentUrl, isNotNull);

    // document.title
    final title = link.evalJs('document.title');
    expect(title, isNotNull);
    final titleJson = jsonDecode(title!) as Map;
    expect(titleJson['ok'], isTrue);
    expect(titleJson['value'], '轻量内核集成测试');

    // document.body.innerText 应包含正文
    final text = jsonDecode(link.evalJs('document.body.innerText')!) as Map;
    expect(text['ok'], isTrue);
    expect(text['value'].toString(), contains('Hello Lite Kernel'));

    // document.links 应包含我们写的链接
    final links = jsonDecode(link.evalJs('document.links')!) as Map;
    expect(links['ok'], isTrue);
    final list = (links['value'] as List).cast<Map>();
    expect(list.any((e) => e['href'].toString().contains('example.com/next')),
        isTrue);

    // 不支持的脚本必须诚实返回 unsupported，而不是假装执行
    final unsupported =
        jsonDecode(link.evalJs('alert(1)')!) as Map;
    expect(unsupported['ok'], isFalse);
    expect(unsupported['error'].toString(), contains('unsupported'));
  }, skip: skipReason);

  test('FFI 内核：绑定表面后 tick 能产出真实帧缓冲', () async {
    final link = FfiKernelLink.open(
      libraryPath: dllPath,
      configJson: jsonEncode({'tab_id': 'render_test'}),
      onHostDispatch: (requestId, method, params) {},
    );
    addTearDown(link.dispose);

    var frames = 0;
    var lastW = 0;
    var lastH = 0;
    var lastStride = 0;
    final distinctColors = <int>{};

    // 与 zb_frame_submit_fn 完全一致的签名：RGBA8888 + stride
    final frameCallback = NativeCallable<FrameSubmitC>.isolateLocal(
      (int textureId, Pointer<Uint8> rgba, int width, int height, int stride) {
        frames++;
        lastW = width;
        lastH = height;
        lastStride = stride;
        if (rgba == nullptr || width <= 0 || height <= 0) return;
        final bytes = rgba.asTypedList(stride * height);
        for (var y = 0; y < height; y += 2) {
          for (var x = 0; x < width; x += 2) {
            final o = y * stride + x * 4;
            if (o + 3 >= bytes.length) continue;
            distinctColors.add(
                (bytes[o] << 16) | (bytes[o + 1] << 8) | bytes[o + 2]);
          }
        }
      },
    );
    addTearDown(frameCallback.close);

    const width = 480;
    const height = 400;
    expect(
      link.attachSurface(
        textureId: 42,
        frameSubmit: frameCallback.nativeFunction,
        width: width,
        height: height,
      ),
      isTrue,
      reason: 'zb_kernel_attach_surface 应返回 0',
    );

    expect(link.loadUrl(sampleHtml), isTrue);
    expect(link.tick(), 0);

    expect(frames, greaterThan(0), reason: '内核应通过 frame_submit 提交至少一帧');
    expect(lastW, width);
    expect(lastH, height);
    expect(lastStride, width * 4,
        reason: 'RGBA8888 每行字节数应为 width*4（否则宿主纹理会错位）');
    expect(distinctColors.length, greaterThan(2),
        reason: '帧缓冲应含背景 + 文字 + 链接等多种颜色，实际只有 ${distinctColors.length} 种');
  }, skip: skipReason);

  test('FFI 内核：滚动与链接点击等输入事件被接受并生效', () async {
    final link = FfiKernelLink.open(
      libraryPath: dllPath,
      configJson: jsonEncode({'tab_id': 'input_test'}),
      onHostDispatch: (requestId, method, params) {},
    );
    addTearDown(link.dispose);

    final frameCallback = NativeCallable<FrameSubmitC>.isolateLocal(
      (int textureId, Pointer<Uint8> rgba, int width, int height, int stride) {},
    );
    addTearDown(frameCallback.close);

    link.attachSurface(
      textureId: 1,
      frameSubmit: frameCallback.nativeFunction,
      width: 360,
      height: 300,
    );
    link.loadUrl(sampleHtml);
    link.tick();

    // 长页面才能滚动：先构造足够多的段落
    final longHtml = StringBuffer('<html><head><title>Long</title></head><body>');
    for (var i = 0; i < 120; i++) {
      longHtml.write('<p>第 $i 段：用于制造可滚动的长文档。</p>');
    }
    longHtml.write('</body></html>');
    link.loadUrl(longHtml.toString());
    link.tick();

    // 走宿主 -> 内核的输入通道（ABI v1 用 dispatch_from_host 传输入）
    expect(link.dispatchFromHost('{"event":"scroll","dx":0,"dy":240}'), isTrue);
    link.tick();

    final scrolled =
        jsonDecode(link.evalJs('window.scrollBy(0, 1)')!) as Map;
    expect(scrolled['ok'], isTrue,
        reason: '输入事件通道应被内核识别，且滚动命令应可用');

    // 未知事件不应让内核崩溃；FfiKernelLink 把返回码 0 归一化为 true
    expect(link.dispatchFromHost('{"event":"unknown"}'), isTrue);

    // 点击链接会触发导航；命中与否取决于坐标，这里只要求不崩溃且状态可读
    link.dispatchFromHost('{"event":"pointer","type":"down","x":20,"y":40}');
    link.dispatchFromHost('{"event":"pointer","type":"up","x":20,"y":40}');
    link.tick();
    expect(link.currentUrl, isNotNull);

    // 键盘事件
    for (final key in ['PageDown', 'Home', 'End', 'Up', 'Down']) {
      expect(link.dispatchFromHost('{"event":"key","key":"$key"}'), isTrue,
          reason: '$key 事件应被内核接受');
    }
    link.tick();
  }, skip: skipReason);

  test('FFI 内核：重复 attach_surface（尺寸变化）后仍能出帧', () async {
    final link = FfiKernelLink.open(
      libraryPath: dllPath,
      configJson: jsonEncode({'tab_id': 'resize_test'}),
      onHostDispatch: (requestId, method, params) {},
    );
    addTearDown(link.dispose);

    var frames = 0;
    var lastW = 0;
    final cb = NativeCallable<FrameSubmitC>.isolateLocal(
      (int textureId, Pointer<Uint8> rgba, int width, int height, int stride) {
        frames++;
        lastW = width;
      },
    );
    addTearDown(cb.close);

    expect(
      link.attachSurface(
          textureId: 1, frameSubmit: cb.nativeFunction, width: 320, height: 240),
      isTrue,
    );
    link.loadUrl(sampleHtml);
    link.tick();
    final firstFrames = frames;
    expect(firstFrames, greaterThan(0));

    // 宿主在视图尺寸变化时会再次 attach_surface
    expect(
      link.attachSurface(
          textureId: 2, frameSubmit: cb.nativeFunction, width: 800, height: 600),
      isTrue,
    );
    link.tick();
    expect(frames, greaterThan(firstFrames), reason: '换尺寸后应继续提交帧');
    expect(lastW, 800, reason: '帧尺寸应跟随新的表面尺寸重新排版');
  }, skip: skipReason);
}
