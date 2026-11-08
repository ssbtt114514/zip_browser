import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/config_service.dart';
import '../../services/ocr_service.dart';

/// 文字识别（OCR）页：选择图片 → 取出文字 → 可复制展示。
///
/// Android 走内置 ML Kit 离线识别；其余平台走用户配置的
/// OpenAI 兼容多模态接口（见 [OcrService] 的能力边界说明）。
class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  String? _imagePath;
  String? _result;
  String? _error;
  bool _busy = false;

  static String _engineNote() {
    if (OcrService.localOcrAvailable) {
      return '当前平台：内置离线识别（ML Kit 中文脚本），图片不上传。';
    }
    return '当前平台：通过「设置 → AI 解读」配置的多模态接口识别'
        '（图片会发送给你配置的 AI 服务）。';
  }

  Future<void> _pickAndRecognize() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: false);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _imagePath = path;
      _result = null;
      _error = null;
      _busy = true;
    });
    try {
      final text = await OcrService.recognizeImageFile(
        path,
        context.read<ConfigService>(),
      );
      if (!mounted) return;
      setState(() {
        _result = text.isEmpty ? '图片中没有识别到文字' : text;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _copy() async {
    final text = _result;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文字识别')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.document_scanner_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_engineNote(),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.file(
                  File(_imagePath!),
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndRecognize,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined, size: 18),
            label: Text(_busy ? '正在识别…' : '选择图片并识别'),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          if (_result != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(_result!,
                    style: const TextStyle(fontSize: 14, height: 1.6)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('复制全部'),
            ),
          ],
        ],
      ),
    );
  }
}
