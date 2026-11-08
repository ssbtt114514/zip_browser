import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/build_flavor.dart';
import '../core/kernel/kernel_manager.dart';
import 'config_service.dart';

/// 把随安装包内置的 `.zbk` 内核安装到用户目录并选中。
///
/// 内核安装入口已从界面移除：Gecko 风味在首次启动时自动安装内置内核，
/// 其余风味直接使用系统 WebView。资产缺失或损坏时静默回落系统内核，
/// 保证浏览器始终可以启动。
Future<void> seedBundledKernel({
  required KernelManager kernelManager,
  required ConfigService config,
}) async {
  final asset = BuildFlavorInfo.bundledKernelAsset;
  if (asset == null) return;

  try {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (bytes.isEmpty) return;
    final installed = kernelManager.installFromBytes(bytes);
    await config.setSelectedKernelId(installed.kernelId);
  } catch (error) {
    debugPrint('内置内核安装失败，回落系统内核：$error');
  }
}
