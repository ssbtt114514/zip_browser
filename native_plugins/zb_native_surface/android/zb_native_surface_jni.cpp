// Zip Browser —— 原生表面插件（Android）
//
// 把插件 FFI 内核产生的软件 RGBA 帧，经 EGL 绘制到由 Flutter
// TextureRegistry 创建的 SurfaceTexture（android.view.Surface），最终作为
// Flutter 纹理上屏。
//
// 对外两类接口：
//   1. JNI：NativeSurfacePlugin.nativeCreate / nativeDestroy（平台线程）
//   2. 导出 C 函数 zb_surface_submit_frame：内核经 dart:ffi 取得后直接调用，
//      帧路径不经过 Dart（运行在 Dart FFI 线程，内部 lazy 初始化 EGL）
//
// 编译见同目录 CMakeLists.txt。

#include <jni.h>

#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include <cstdint>
#include <cstring>
#include <map>
#include <mutex>
#include <vector>

static JavaVM* g_vm = nullptr;

struct Renderer {
  int64_t textureId = 0;
  jobject surface = nullptr;  // android.view.Surface 全局引用
  int w = 0, h = 0;

  ANativeWindow* window = nullptr;
  EGLDisplay dpy = EGL_NO_DISPLAY;
  EGLConfig cfg = nullptr;
  EGLContext ctx = EGL_NO_CONTEXT;
  EGLSurface esurf = EGL_NO_SURFACE;
  GLuint program = 0;
  GLuint tex = 0;
  GLuint vbo = 0;
  GLint aPos = -1, aUv = -1, uTex = -1;
  bool initialized = false;
};

static std::mutex g_mtx;
static std::map<int64_t, Renderer*> g_renderers;

static const char* kVS =
    "attribute vec2 a_pos; attribute vec2 a_uv; varying vec2 v_uv;"
    "void main(){ v_uv=a_uv; gl_Position=vec4(a_pos,0.0,1.0); }";
static const char* kFS =
    "precision mediump float; varying vec2 v_uv; uniform sampler2D s_tex;"
    "void main(){ gl_FragColor=texture2D(s_tex,v_uv); }";

static GLuint compileShader(GLenum type, const char* src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, nullptr);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glDeleteShader(s);
    return 0;
  }
  return s;
}

// 在调用线程（Dart FFI 线程）lazy 初始化 EGL / 程序 / 纹理
static bool ensureInitialized(Renderer* r, JNIEnv* env) {
  if (r->initialized) return true;

  r->window = ANativeWindow_fromSurface(env, r->surface);
  if (r->window == nullptr) return false;

  r->dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (r->dpy == EGL_NO_DISPLAY) return false;
  if (!eglInitialize(r->dpy, nullptr, nullptr)) return false;

  const EGLint cfgAttr[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
      EGL_ALPHA_SIZE, 8, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
      EGL_NONE};
  EGLint n = 0;
  if (!eglChooseConfig(r->dpy, cfgAttr, &r->cfg, 1, &n) || n < 1) return false;

  const EGLint ctxAttr[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  r->ctx = eglCreateContext(r->dpy, r->cfg, EGL_NO_CONTEXT, ctxAttr);
  if (r->ctx == EGL_NO_CONTEXT) return false;

  r->esurf = eglCreateWindowSurface(r->dpy, r->cfg, r->window, nullptr);
  if (r->esurf == EGL_NO_SURFACE) return false;

  eglMakeCurrent(r->dpy, r->esurf, r->esurf, r->ctx);

  // 程序
  GLuint vs = compileShader(GL_VERTEX_SHADER, kVS);
  GLuint fs = compileShader(GL_FRAGMENT_SHADER, kFS);
  r->program = glCreateProgram();
  glAttachShader(r->program, vs);
  glAttachShader(r->program, fs);
  glLinkProgram(r->program);
  glDeleteShader(vs);
  glDeleteShader(fs);
  r->aPos = glGetAttribLocation(r->program, "a_pos");
  r->aUv = glGetAttribLocation(r->program, "a_uv");
  r->uTex = glGetUniformLocation(r->program, "s_tex");

  // 全屏 quad（TRIANGLE_STRIP），位置 + uv 交错。
  // 图像数据第 0 行为顶部；纹理坐标 v=0 采样到第 0 行，故顶部顶点 uv.v=0。
  const float verts[] = {
      // x    y    u    v
      -1.f,  1.f, 0.f, 0.f,  // 左上
       1.f,  1.f, 1.f, 0.f,  // 右上
      -1.f, -1.f, 0.f, 1.f,  // 左下
       1.f, -1.f, 1.f, 1.f,  // 右下
  };
  glGenBuffers(1, &r->vbo);
  glBindBuffer(GL_ARRAY_BUFFER, r->vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);

  glGenTextures(1, &r->tex);
  glBindTexture(GL_TEXTURE_2D, r->tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  r->initialized = true;
  return true;
}

// 释放当前线程对 EGL 的绑定，便于其它线程销毁资源
static void releaseCurrent(Renderer* r) {
  eglMakeCurrent(r->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
}

extern "C" __attribute__((visibility("default"))) void
zb_surface_submit_frame(int64_t texture_id, const uint8_t* rgba, int32_t w,
                        int32_t h, int32_t stride) {
  Renderer* r = nullptr;
  {
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_renderers.find(texture_id);
    if (it == g_renderers.end()) return;
    r = it->second;
  }

  JNIEnv* env = nullptr;
  bool attached = false;
  if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) attached = true;
  }
  if (env == nullptr) return;

  if (!ensureInitialized(r, env)) {
    if (attached) g_vm->DetachCurrentThread();
    return;
  }

  eglMakeCurrent(r->dpy, r->esurf, r->esurf, r->ctx);

  // 处理 stride：非紧凑时逐行拷贝
  std::vector<uint8_t> tight;
  const uint8_t* src = rgba;
  if (stride != w * 4) {
    tight.resize(static_cast<size_t>(w) * h * 4);
    for (int y = 0; y < h; ++y) {
      std::memcpy(tight.data() + static_cast<size_t>(y) * w * 4,
                  rgba + static_cast<size_t>(y) * stride,
                  static_cast<size_t>(w) * 4);
    }
    src = tight.data();
  }

  glBindTexture(GL_TEXTURE_2D, r->tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, src);

  glViewport(0, 0, w, h);
  glUseProgram(r->program);
  glBindBuffer(GL_ARRAY_BUFFER, r->vbo);
  glEnableVertexAttribArray(r->aPos);
  glVertexAttribPointer(r->aPos, 2, GL_FLOAT, GL_FALSE, 16,
                        reinterpret_cast<void*>(0));
  glEnableVertexAttribArray(r->aUv);
  glVertexAttribPointer(r->aUv, 2, GL_FLOAT, GL_FALSE, 16,
                        reinterpret_cast<void*>(8));
  glActiveTexture(GL_TEXTURE0);
  glUniform1i(r->uTex, 0);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glDisableVertexAttribArray(r->aPos);
  glDisableVertexAttribArray(r->aUv);

  eglSwapBuffers(r->dpy, r->esurf);
  releaseCurrent(r);

  if (attached) g_vm->DetachCurrentThread();
}

// —— JNI 接口 ——
// 包名 com.zipbrowser.zip_browser -> JNI 编码 com_zipbrowser_zip_1browser
extern "C" JNIEXPORT void JNICALL
Java_com_zipbrowser_zip_1browser_NativeSurfacePlugin_nativeCreate(
    JNIEnv* env, jclass, jlong texture_id, jobject surface, jint w, jint h) {
  auto* r = new Renderer();
  r->textureId = texture_id;
  r->surface = env->NewGlobalRef(surface);
  r->w = w;
  r->h = h;
  std::lock_guard<std::mutex> lk(g_mtx);
  g_renderers[texture_id] = r;
}

extern "C" JNIEXPORT void JNICALL
Java_com_zipbrowser_zip_1browser_NativeSurfacePlugin_nativeDestroy(
    JNIEnv* env, jclass, jlong texture_id) {
  Renderer* r = nullptr;
  {
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_renderers.find(texture_id);
    if (it == g_renderers.end()) return;
    r = it->second;
    g_renderers.erase(it);
  }
  // submit 结束后已释放 current，可在本线程安全销毁 EGL 资源
  if (r->initialized) {
    glDeleteTextures(1, &r->tex);
    glDeleteBuffers(1, &r->vbo);
    glDeleteProgram(r->program);
    eglDestroySurface(r->dpy, r->esurf);
    eglDestroyContext(r->dpy, r->ctx);
    eglTerminate(r->dpy);
    if (r->window) ANativeWindow_release(r->window);
  }
  if (r->surface) env->DeleteGlobalRef(r->surface);
  delete r;
}

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
  g_vm = vm;
  return JNI_VERSION_1_6;
}
