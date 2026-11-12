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
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// 读取系统主题所需：DWM 强调色、注册表深色模式偏好。
// advapi32 通过 pragma 引入，避免改动 runner 的 CMake 链接列表。
#include <dwmapi.h>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "dwmapi.lib")

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// 单个原生表面的状态
struct SurfaceState {
  int64_t texture_id = 0;
  int width = 0;
  int height = 0;
  flutter::TextureRegistrar* registrar = nullptr;
  std::mutex frame_mutex;
  std::vector<uint8_t> frame;
  bool has_frame = false;
};

// PixelBufferTexture 回调需要在渲染线程取帧，而帧提交可能发生在别的线程，
// 因此回调期间持有 frame_mutex，待引擎 release_callback 时再解锁。
struct ReleaseInfo {
  FlutterDesktopPixelBuffer buffer;
  SurfaceState* state;
};

std::mutex g_map_mutex;
std::map<int64_t, SurfaceState*> g_surfaces;

const FlutterDesktopPixelBuffer* CopyPixelBufferForState(SurfaceState* state,
                                                         size_t /*width*/,
                                                         size_t /*height*/) {
  state->frame_mutex.lock();
  if (!state->has_frame) {
    state->frame_mutex.unlock();
    return nullptr;
  }
  auto* info = new ReleaseInfo();
  info->state = state;
  info->buffer.buffer = state->frame.data();
  info->buffer.width = static_cast<size_t>(state->width);
  info->buffer.height = static_cast<size_t>(state->height);
  info->buffer.release_context = info;
  info->buffer.release_callback = [](void* context) {
    auto* i = static_cast<ReleaseInfo*>(context);
    i->state->frame_mutex.unlock();
    delete i;
  };
  return &info->buffer;
}

int64_t ReadInt(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0;
  const auto& v = it->second;
  if (std::holds_alternative<int32_t>(v)) return std::get<int32_t>(v);
  if (std::holds_alternative<int64_t>(v)) return std::get<int64_t>(v);
  return 0;
}

// 读取注册表 DWORD（失败返回 false）。
bool ReadRegDword(HKEY root, const wchar_t* subkey, const wchar_t* name,
                  DWORD* out) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, subkey, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  DWORD size = sizeof(DWORD);
  DWORD value = 0;
  const LONG rc =
      RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(&value), &size);
  RegCloseKey(key);
  if (rc != ERROR_SUCCESS || type != REG_DWORD) return false;
  *out = value;
  return true;
}

// 系统强调色：DwmGetColorizationColor 返回 0xAABBGGRR（低字节为 R）。
bool ReadAccentColor(uint32_t* argb) {
  DWORD color = 0;
  BOOL opaque_blend = FALSE;
  if (FAILED(DwmGetColorizationColor(&color, &opaque_blend))) return false;
  if ((color & 0x00FFFFFF) == 0) return false;
  const uint32_t r = color & 0xFF;
  const uint32_t g = (color >> 8) & 0xFF;
  const uint32_t b = (color >> 16) & 0xFF;
  *argb = 0xFF000000u | (r << 16) | (g << 8) | b;
  return true;
}

// 桌面壁纸路径：优先 SPI 返回值，为空时回退主题缓存文件。
bool ReadWallpaperPath(std::wstring* out) {
  constexpr UINT kMaxPath = 1024;
  wchar_t path[kMaxPath] = {0};
  if (SystemParametersInfoW(SPI_GETDESKWALLPAPER, kMaxPath, path, 0) &&
      path[0] != L'\0') {
    *out = path;
    return true;
  }
  wchar_t appdata[MAX_PATH] = {0};
  const DWORD n = GetEnvironmentVariableW(
      L"APPDATA", appdata, static_cast<DWORD>(std::size(appdata)));
  if (n == 0 || n >= std::size(appdata)) return false;
  *out = std::wstring(appdata) +
         L"\\Microsoft\\Windows\\Themes\\TranscodedWallpaper";
  return true;
}

class NativeSurfacePlugin : public flutter::Plugin {
 public:
  explicit NativeSurfacePlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar_->messenger(), "zip_browser/native_surface",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~NativeSurfacePlugin() override {
    // 先注销纹理，等引擎确认释放后再销毁状态，避免回调期间悬垂。
    for (auto& kv : states_) {
      SurfaceState* state = kv.second;
      registrar_->texture_registrar()->UnregisterTexture(
          kv.first, [state]() { delete state; });
    }
    states_.clear();
    textures_.clear();
    std::lock_guard<std::mutex> lock(g_map_mutex);
    g_surfaces.clear();
  }

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    EncodableMap args;
    if (call.arguments() &&
        std::holds_alternative<EncodableMap>(*call.arguments())) {
      args = std::get<EncodableMap>(*call.arguments());
    }

    if (call.method_name() == "createSurface") {
      CreateSurface(args, std::move(result));
    } else if (call.method_name() == "destroySurface") {
      DestroySurface(ReadInt(args, "textureId"));
      result->Success();
    } else if (call.method_name() == "readSystemTheme") {
      ReadSystemTheme(std::move(result));
    } else {
      result->NotImplemented();
    }
  }

 private:
  // 读取 Windows 系统主题：强调色 / 深色偏好 / 壁纸路径。
  // 任一项读取失败时对应字段返回 null，由 Dart 侧决定降级策略。
  void ReadSystemTheme(std::unique_ptr<flutter::MethodResult<EncodableValue>>
                           result) {
    EncodableMap theme;

    uint32_t accent = 0;
    if (ReadAccentColor(&accent)) {
      theme[EncodableValue("accentColor")] =
          EncodableValue(static_cast<int64_t>(accent));
    } else {
      theme[EncodableValue("accentColor")] = EncodableValue();
    }

    DWORD apps_use_light = 1;
    const bool has_theme = ReadRegDword(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", &apps_use_light);
    theme[EncodableValue("darkMode")] =
        EncodableValue(has_theme ? (apps_use_light == 0) : false);

    std::wstring wallpaper;
    if (ReadWallpaperPath(&wallpaper)) {
      theme[EncodableValue("wallpaperPath")] =
          EncodableValue(Utf8FromWide(wallpaper));
    } else {
      theme[EncodableValue("wallpaperPath")] = EncodableValue();
    }

    result->Success(EncodableValue(theme));
  }

  static std::string Utf8FromWide(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    const int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                         static_cast<int>(wide.size()),
                                         nullptr, 0, nullptr, nullptr);
    if (size <= 0) return std::string();
    std::string out(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                        static_cast<int>(wide.size()), out.data(), size,
                        nullptr, nullptr);
    return out;
  }

  void CreateSurface(const EncodableMap& args,
                     std::unique_ptr<flutter::MethodResult<EncodableValue>>
                         result) {
    const int width = static_cast<int>(ReadInt(args, "width"));
    const int height = static_cast<int>(ReadInt(args, "height"));
    if (width <= 0 || height <= 0) {
      result->Error("bad_args", "width/height 非法");
      return;
    }

    auto* state = new SurfaceState();
    state->width = width;
    state->height = height;
    state->registrar = registrar_->texture_registrar();
    state->frame.assign(static_cast<size_t>(width) * height * 4, 0);

    // PixelBufferTexture 的回调不带 user_data，用 lambda 捕获 state。
    auto texture = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([state](size_t w, size_t h) {
          return CopyPixelBufferForState(state, w, h);
        }));
    const int64_t id =
        registrar_->texture_registrar()->RegisterTexture(texture.get());
    state->texture_id = id;

    textures_[id] = std::move(texture);
    states_[id] = state;
    {
      std::lock_guard<std::mutex> lock(g_map_mutex);
      g_surfaces[id] = state;
    }

    // Dart 端用 invokeMethod<int> 接收，直接回传纹理 id。
    result->Success(EncodableValue(id));
  }

  void DestroySurface(int64_t id) {
    auto it = states_.find(id);
    if (it == states_.end()) return;
    SurfaceState* state = it->second;
    states_.erase(it);
    {
      std::lock_guard<std::mutex> lock(g_map_mutex);
      g_surfaces.erase(id);
    }
    // 注销完成后才销毁状态。
    registrar_->texture_registrar()->UnregisterTexture(
        id, [state]() { delete state; });
    textures_.erase(id);
  }

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::map<int64_t, std::unique_ptr<flutter::TextureVariant>> textures_;
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
    if (it == g_surfaces.end()) {
      return;
    }
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
  // PluginRegistrarManager 负责让 registrar 包装对象与底层 ref 同生命周期。
  flutter::PluginRegistrarWindows* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(
      std::make_unique<NativeSurfacePlugin>(windows_registrar));
}
