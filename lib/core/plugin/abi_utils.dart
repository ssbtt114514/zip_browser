import 'dart:ffi';

/// 当前设备的 Android ABI 目录名（与 jniLibs 约定一致）
String? currentAndroidAbiFolder() {
  final abi = Abi.current();
  if (abi == Abi.androidArm64) return 'arm64-v8a';
  if (abi == Abi.androidArm) return 'armeabi-v7a';
  if (abi == Abi.androidX64) return 'x86_64';
  if (abi == Abi.androidIA32) return 'x86';
  return null;
}
