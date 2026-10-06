// Zip Browser —— 原生表面插件（Windows）
//
// 职责：
//   1. 响应 Dart 端 createSurface / destroySurface，注册 Flutter 像素缓冲纹理
//   2. 导出 zb_surface_submit_frame，供插件 FFI 内核直接提交 RGBA 帧
//      （帧路径不经过 Dart）
//
// 编译方式见同目录 CMakeLists.txt 与 docs/PLUGIN_KERNEL_GUIDE.md

#include "zb_native_surface_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

namespace {

struct SurfaceState {
  int64_t texture_id = 0;
  int width = 0;
  int height = 0;
  std::mutex frame_mutex;
  std::vector<uint8_t> frame;
  bool has_frame = false;
  flutter::TextureRegistrar* registrar = nullptr;
};

// PixelBufferTexture 释放信息
struct ReleaseInfo {
  FlutterDesktopPixelBuffer pb;
  SurfaceState* state;
};

std::mutex g_map_mutex;
std::map<int64_t, SurfaceState*> g_surfaces;

// PixelBufferTexture 帧回调（引擎请求帧）
const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t /*width*/,
                                                 size_t /*height*/,
                                                 void* user_data) {
  auto* state = static_cast<SurfaceState*>(user_data);
  state->frame_mutex.lock();
  if (!state->has_frame) {
    state->frame_mutex.unlock();
    return nullptr;
  }
  auto* info = new ReleaseInfo();
  info->state = state;
  info->pb.buffer = state->frame.data();
  info->pb.width = static_cast<size_t>(state->width);
  info->pb.height = static_cast<size_t>(state->height);
  info->pb.release_callback = [](void* context) {
    auto* i = static_cast<ReleaseInfo*>(context);
    i->state->frame_mutex.unlock();
    delete i;
  };
  info->pb.release_context = info;
  return &info->pb;
}

int64_t ReadInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  const auto& v = it->second;
  if (std::holds_alternative<int32_t>(v)) return std::get<int32_t>(v);
  if (std::holds_alternative<int64_t>(v)) return std::get<int64_t>(v);
  return 0;
}

class NativeSurfacePlugin {
 public:
  explicit NativeSurfacePlugin(flutter::TextureRegistrar* textures)
      : textures_(textures) {}

  ~NativeSurfacePlugin() {
    std::lock_guard<std::mutex> lock(g_map_mutex);
    for (auto& kv : states_) delete kv.second;
  }

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    flutter::EncodableMap args;
    if (call.arguments() &&
        std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
      args = std::get<flutter::EncodableMap>(*call.arguments());
    }

    if (call.method_name() == "createSurface") {
      const int width = static_cast<int>(ReadInt(args, "width"));
      const int height = static_cast<int>(ReadInt(args, "height"));
      if (width <= 0 || height <= 0) {
        result->Error("bad_args", "width/height 非法");
        return;
      }

      auto* state = new SurfaceState();
      state->width = width;
      state->height = height;
      state->frame.assign(static_cast<size_t>(width) * height * 4, 0);
      state->registrar = textures_;

      auto texture = std::make_unique<flutter::PixelBufferTexture>(
          &CopyPixelBuffer, state);
      const int64_t id = textures_->RegisterTexture(texture.get());
      state->texture_id = id;

      textures_map_[id] = std::move(texture);
      states_[id] = state;
      {
        std::lock_guard<std::mutex> lock(g_map_mutex);
        g_surfaces[id] = state;
      }

      flutter::EncodableMap reply;
      reply[flutter::EncodableValue("textureId")] =
          flutter::EncodableValue(id);
      const auto submit_addr =
          reinterpret_cast<int64_t>(&zb_surface_submit_frame);
      reply[flutter::EncodableValue("submit_frame_address")] =
          flutter::EncodableValue(submit_addr);
      result->Success(flutter::EncodableValue(reply));
    } else if (call.method_name() == "destroySurface") {
      const int64_t id = ReadInt(args, "textureId");
      textures_->UnregisterTexture(id);
      {
        std::lock_guard<std::mutex> lock(g_map_mutex);
        g_surfaces.erase(id);
      }
      auto it = states_.find(id);
      if (it != states_.end()) {
        delete it->second;
        states_.erase(it);
      }
      textures_map_.erase(id);
      result->Success();
    } else {
      result->NotImplemented();
    }
  }

 private:
  flutter::TextureRegistrar* textures_;
  std::map<int64_t, std::unique_ptr<flutter::PixelBufferTexture>> textures_map_;
  std::map<int64_t, SurfaceState*> states_;
};

}  // namespace

// 插件 FFI 内核的帧提交入口（导出）
extern "C" __declspec(dllexport) void zb_surface_submit_frame(
    int64_t texture_id, const uint8_t* rgba, int32_t width, int32_t height,
    int32_t stride) {
  SurfaceState* state = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_map_mutex);
    auto it = g_surfaces.find(texture_id);
    if (it == g_surfaces.end()) return;
    state = it->second;
  }

  {
    std::lock_guard<std::mutex> frame_lock(state->frame_mutex);
    state->frame.resize(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
      std::memcpy(state->frame.data() + static_cast<size_t>(y) * width * 4,
                  rgba + static_cast<size_t>(y) * stride,
                  static_cast<size_t>(width) * 4);
    }
    state->has_frame = true;
  }
  state->registrar->MarkTextureFrameAvailable(texture_id);
}

void ZipBrowserNativeSurfacePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto windows_registrar =
      std::make_unique<flutter::PluginRegistrarWindows>(registrar);

  auto* plugin =
      new NativeSurfacePlugin(windows_registrar->texture_registrar());

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          windows_registrar->messenger(), "zip_browser/native_surface",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [plugin](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) {
        plugin->HandleMethodCall(call, std::move(result));
      });

  // channel / plugin 生命周期与进程一致，故意不释放（标准插件做法）
  channel.release();
}
