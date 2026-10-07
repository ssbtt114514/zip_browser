package com.zipbrowser.zip_browser

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Zip Browser 主 Activity。
 *
 * 额外职责：给系统 WebView（webview_flutter_android）的文件选择器兜底——
 * 网页 <input type="file" accept="image / *" capture="camera"> 会触发
 * WebChromeClient.onShowFileChooser，webview_flutter 默认只弹文件选择器、
 * 不会调用相机；这里注册 zip_browser/file_chooser 通道，由 Dart 侧
 * （AndroidSystemKernel.setOnShowFileSelector）调用，按需拉起系统相机
 * （ACTION_IMAGE_CAPTURE + FileProvider 临时文件）或相册/文件选择器，
 * 把 content URI 列表交回 WebView 的 ValueCallback。
 *
 * 注意：本工程 FlutterActivity 继承 android.app.Activity（无
 * registerForActivityResult），因此使用传统 startActivityForResult。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "zip_browser/file_chooser"
    private var pendingResult: MethodChannel.Result? = null
    private var cameraUri: Uri? = null

    private val requestCamera = 1001
    private val requestGallery = 1002

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (pendingResult != null) {
                            result.error("busy", "已有文件选择正在进行", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val capture = call.argument<Boolean>("capture") == true
                        val multiple = call.argument<Boolean>("multiple") == true
                        @Suppress("UNCHECKED_CAST")
                        val accept = call.argument<List<String>>("accept") ?: emptyList()
                        if (capture && acceptOnlyImages(accept)) {
                            launchCamera()
                        } else {
                            launchGallery(multiple, accept)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val reply = pendingResult
        if (reply == null) return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK) {
            cameraUri = null
            reply.success(emptyList<String>())
            return
        }

        when (requestCode) {
            requestCamera -> {
                val uri = cameraUri
                cameraUri = null
                reply.success(if (uri != null) listOf(uri.toString()) else emptyList<String>())
            }
            requestGallery -> {
                val uris = if (data?.clipData != null) {
                    (0 until data.clipData!!.itemCount)
                        .map { data.clipData!!.getItemAt(it).uri.toString() }
                } else if (data?.data != null) {
                    listOf(data.data.toString())
                } else {
                    emptyList()
                }
                reply.success(uris)
            }
            else -> reply.success(emptyList<String>())
        }
    }

    /** accept 全部是图片类型（且不是通配符 * / * 才走相机，避免误拉起拍照 */
    private fun acceptOnlyImages(accept: List<String>): Boolean =
        accept.isNotEmpty() && !accept.contains("*/*") &&
            accept.all { it.startsWith("image/") }

    private fun launchCamera() {
        try {
            val dir = getExternalFilesDir(null) ?: filesDir
            val file = File(dir, "zb_capture_${System.currentTimeMillis()}.jpg")
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            cameraUri = uri
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivityForResult(intent, requestCamera)
            } else {
                // 设备无相机应用：回退相册（pendingResult 保持）
                cameraUri = null
                launchGallery(false, listOf("image/*"))
            }
        } catch (e: Exception) {
            val reply = pendingResult
            pendingResult = null
            reply?.error("camera_error", e.message, null)
        }
    }

    private fun launchGallery(multiple: Boolean, accept: List<String>) {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = if (accept.isEmpty()) "*/*" else accept.first()
            if (multiple) putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        startActivityForResult(intent, requestGallery)
    }
}
