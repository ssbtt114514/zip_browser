package com.zipbrowser.zip_browser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// 注册原生表面插件，使插件携带的 FFI 内核可在 Android 上显示画面。
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(NativeSurfacePlugin())
    }
}
