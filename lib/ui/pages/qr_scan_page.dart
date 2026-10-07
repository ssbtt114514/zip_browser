import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 二维码 / 条码扫描页。识别成功后 pop 返回原始字符串。
///
/// 修复点：
/// * 闪光灯按钮状态实时跟随摄像头（unavailable / on / off），不再"点了没反应"；
/// * 相机启动失败时给出「重试 / 打开系统设置」操作，而不是黑屏卡死；
/// * 识别结果去重（_handled），避免一帧内重复 pop。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      // 摄像头不支持闪光灯：静默，状态仍由 torchState 驱动显示
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫一扫'),
        actions: [
          // 闪光灯状态实时同步：unavailable 时隐藏，on/off 切换图标与高亮
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torch = state.torchState;
              if (torch == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = torch == TorchState.on;
              return IconButton(
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                color: on ? Colors.amber : Colors.white,
                tooltip: on ? '关闭闪光灯' : '打开闪光灯',
                onPressed: _toggleTorch,
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              final denied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography,
                        color: Colors.white54, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      denied ? '未获得相机权限' : '无法启动相机',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      denied
                          ? '请在系统设置中允许 Zip Browser 使用相机'
                          : '请检查摄像头是否被其它应用占用',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                      onPressed: () => _controller.start(),
                    ),
                  ],
                ),
              );
            },
          ),
          // 取景框
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            child: Text(
              '将二维码放入框内即可自动识别',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
