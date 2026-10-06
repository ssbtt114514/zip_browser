// Zip Browser —— 原生表面插件（Android，实验性骨架）
//
// Android 默认使用系统 WebView，通常无需本插件。
// 仅当需要在 Android 上运行插件携带的 FFI 内核时使用：
//   1. 在 MainActivity.configureFlutterEngine 中注册本插件
//   2. createSurface 注册一个 SurfaceTexture，得到 Flutter textureId
//   3. 将 Surface(SurfaceTexture) 通过 JNI 交给内核，内核使用 EGL
//      直接向该 Surface 绘制（帧路径不经过 Dart）
//
// 包名请按 flutter create 生成的实际 applicationId 调整。

package com.example.zip_browser

import android.graphics.SurfaceTexture
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class NativeSurfacePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val channelName = "zip_browser/native_surface"

    private lateinit var channel: MethodChannel
    private lateinit var textures: TextureRegistry
    private val surfaces = HashMap<Long, Surface>()
    private val entries = HashMap<Long, TextureRegistry.SurfaceTextureEntry>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, channelName)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createSurface" -> {
                val width = (call.argument<Int>("width") ?: 960)
                val height = (call.argument<Int>("height") ?: 600)

                val entry = textures.createSurfaceTexture()
                val surfaceTexture: SurfaceTexture = entry.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(width, height)
                val surface = Surface(surfaceTexture)

                val textureId = entry.id()
                surfaces[textureId] = surface
                entries[textureId] = entry

                // TODO(内核集成): 通过 JNI 把 surface（或其 ANativeWindow 指针）
                // 交给插件内核；内核 EGL 绘制后调用
                // entry.surfaceTexture().__notifyFrameAvailable() 或由
                // SurfaceTexture 自动上屏。
                result.success(
                    mapOf(
                        "textureId" to textureId,
                        // Android 无 C 函数地址回传，使用 JNI 桥
                        "submit_frame_address" to 0L
                    )
                )
            }
            "destroySurface" -> {
                val textureId = (call.argument<Number>("textureId") ?: 0).toLong()
                surfaces.remove(textureId)?.release()
                entries.remove(textureId)?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        surfaces.values.forEach { it.release() }
        entries.values.forEach { it.release() }
        surfaces.clear()
        entries.clear()
    }
}
