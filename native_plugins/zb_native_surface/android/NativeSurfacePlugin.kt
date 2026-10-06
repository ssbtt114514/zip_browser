// Zip Browser —— 原生表面插件（Android）
//
// 仅当需要在 Android 上运行插件携带的 FFI 内核时使用。由 MainActivity
// 在 configureFlutterEngine 中注册。
//
// createSurface：
//   1. 通过 TextureRegistry 创建 SurfaceTexture，得到 Flutter textureId
//   2. 用其构造 android.view.Surface，交给 native（zb_native_surface_jni）
//   3. 返回 textureId
// 内核经 dart:ffi 调用导出的 zb_surface_submit_frame 提交 RGBA 帧，
// native 内部用 EGL 绘制到该 Surface。

package com.zipbrowser.zip_browser

import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class NativeSurfacePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val channelName = "zip_browser/native_surface"

    private lateinit var channel: MethodChannel
    private lateinit var textures: TextureRegistry
    private val entries = HashMap<Long, TextureRegistry.SurfaceTextureEntry>()
    private val surfaces = HashMap<Long, Surface>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, channelName)
        channel.setMethodCallHandler(this)
        System.loadLibrary("zb_native_surface")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createSurface" -> {
                val width = call.argument<Int>("width") ?: 960
                val height = call.argument<Int>("height") ?: 600

                val entry = textures.createSurfaceTexture()
                val st = entry.surfaceTexture()
                st.setDefaultBufferSize(width, height)
                val surface = Surface(st)

                val id = entry.id()
                entries[id] = entry
                surfaces[id] = surface
                nativeCreate(id, surface, width, height)
                // Dart 端 invokeMethod<int> 接收，直接回传纹理 id
                result.success(id)
            }
            "destroySurface" -> {
                val id = (call.argument<Number>("textureId") ?: 0).toLong()
                nativeDestroy(id)
                surfaces.remove(id)?.release()
                entries.remove(id)?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private external fun nativeCreate(
        textureId: Long, surface: Surface, width: Int, height: Int)
    private external fun nativeDestroy(textureId: Long)

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        surfaces.values.forEach { it.release() }
        entries.values.forEach { it.release() }
        surfaces.clear()
        entries.clear()
    }
}
