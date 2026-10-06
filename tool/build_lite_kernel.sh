#!/bin/sh
# ============================================================
#  编译 zb_lite_kernel（Linux / Android）—— "轻量文本内核"
#
#  用法：
#    sh tool/build_lite_kernel.sh linux
#    sh tool/build_lite_kernel.sh android-arm64-v8a
#    sh tool/build_lite_kernel.sh android-armeabi-v7a
#    sh tool/build_lite_kernel.sh android-x86_64
#    sh tool/build_lite_kernel.sh all          # 依次构建上面四个目标
#    sh tool/build_lite_kernel.sh selftest     # 用本机 gcc/clang 编译并运行自检
#
#  产物（与 example_plugins/lite_kernel/manifest.json 的 kernel.libraries 对应）：
#    linux               -> example_plugins/lite_kernel/kernels/linux/x86_64/libzb_lite_kernel.so
#    android-arm64-v8a   -> example_plugins/lite_kernel/kernels/android/arm64-v8a/libzb_lite_kernel.so
#    android-armeabi-v7a -> example_plugins/lite_kernel/kernels/android/armeabi-v7a/libzb_lite_kernel.so
#    android-x86_64      -> example_plugins/lite_kernel/kernels/android/x86_64/libzb_lite_kernel.so
#
#  Android 需要 NDK，可通过 ANDROID_NDK / ANDROID_NDK_HOME 指定，
#  否则自动探测 $ANDROID_SDK_ROOT/ndk/*、$HOME/Android/Sdk/ndk/*、/usr/local/lib/android/sdk/ndk/*。
#  注意 NDK 的 --target 前缀规则（见 docs/KERNEL_ABI.md）：
#    arm64-v8a   -> aarch64-linux-android24
#    armeabi-v7a -> armv7a-linux-androideabi24
#    x86_64      -> x86_64-linux-android24
# ============================================================
set -e

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/native_kernels/zb_lite_kernel/src"
TEST="$ROOT/native_kernels/zb_lite_kernel/tests/zb_lite_kernel_selftest.c"
INC_ABI="$ROOT/native_plugins/zb_native_surface/include"
INC_SELF="$ROOT/native_kernels/zb_lite_kernel/include"
OUT_BASE="$ROOT/example_plugins/lite_kernel/kernels"

SOURCES="$SRC/zb_lite_util.c $SRC/zb_lite_json.c $SRC/zb_lite_doc.c \
$SRC/zb_lite_layout.c $SRC/zb_lite_render.c $SRC/zb_lite_kernel.c"

CFLAGS_COMMON="-std=c99 -O2 -Wall -Wextra -fPIC -fvisibility=hidden -I$INC_SELF -I$INC_ABI"

find_ndk() {
    if [ -n "$ANDROID_NDK" ] && [ -d "$ANDROID_NDK" ]; then
        echo "$ANDROID_NDK"
        return 0
    fi
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        echo "$ANDROID_NDK_HOME"
        return 0
    fi
    for base in "$ANDROID_SDK_ROOT" "$ANDROID_HOME" "$HOME/Android/Sdk" \
                "/usr/local/lib/android/sdk" "/opt/android-sdk"; do
        [ -n "$base" ] || continue
        if [ -d "$base/ndk" ]; then
            latest=$(ls -1 "$base/ndk" 2>/dev/null | sort -V | tail -1)
            if [ -n "$latest" ] && [ -d "$base/ndk/$latest" ]; then
                echo "$base/ndk/$latest"
                return 0
            fi
        fi
    done
    return 1
}

build_linux() {
    CC=${CC:-cc}
    if ! command -v "$CC" >/dev/null 2>&1; then
        echo "[ERROR] 未找到 C 编译器：$CC（可用 CC=gcc 指定）"
        return 1
    fi
    mkdir -p "$OUT_BASE/linux/x86_64"
    # shellcheck disable=SC2086
    "$CC" -shared $CFLAGS_COMMON $SOURCES -o "$OUT_BASE/linux/x86_64/libzb_lite_kernel.so"
    echo "构建完成：$OUT_BASE/linux/x86_64/libzb_lite_kernel.so"
}

build_android() {
    ABI="$1"
    case "$ABI" in
        arm64-v8a)   TRIPLE="aarch64-linux-android" ;;
        armeabi-v7a) TRIPLE="armv7a-linux-androideabi" ;;
        x86_64)      TRIPLE="x86_64-linux-android" ;;
        *) echo "[ERROR] 未知 Android ABI：$ABI"; return 1 ;;
    esac

    NDK=$(find_ndk) || {
        echo "[ERROR] 未找到 Android NDK，请设置 ANDROID_NDK 或 ANDROID_NDK_HOME。"
        return 1
    }
    case "$(uname -s)" in
        Darwin) HOST_TAG=darwin-x86_64 ;;
        *)      HOST_TAG=linux-x86_64 ;;
    esac
    CC_NDK="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/${TRIPLE}24-clang"
    if [ ! -x "$CC_NDK" ]; then
        echo "[ERROR] 未找到 NDK clang：$CC_NDK"
        return 1
    fi
    mkdir -p "$OUT_BASE/android/$ABI"
    # shellcheck disable=SC2086
    "$CC_NDK" -shared -target "${TRIPLE}24" $CFLAGS_COMMON $SOURCES \
        -o "$OUT_BASE/android/$ABI/libzb_lite_kernel.so"
    echo "构建完成：$OUT_BASE/android/$ABI/libzb_lite_kernel.so"
}

run_selftest() {
    CC=${CC:-}
    if [ -z "$CC" ]; then
        for cand in cc gcc clang; do
            if command -v "$cand" >/dev/null 2>&1; then CC=$cand; break; fi
        done
    fi
    [ -n "$CC" ] || { echo "[ERROR] 未找到 C 编译器，无法运行自检。"; return 1; }
    BIN_DIR="$ROOT/build/zb_lite_kernel_selftest"
    mkdir -p "$BIN_DIR"
    # shellcheck disable=SC2086
    "$CC" -std=c99 -O1 -g -Wall -Wextra -I"$INC_SELF" -I"$INC_ABI" \
        $SOURCES "$TEST" -o "$BIN_DIR/zb_lite_kernel_selftest"
    "$BIN_DIR/zb_lite_kernel_selftest"
}

TARGET=${1:-linux}
case "$TARGET" in
    linux) build_linux ;;
    android-arm64-v8a) build_android arm64-v8a ;;
    android-armeabi-v7a) build_android armeabi-v7a ;;
    android-x86_64) build_android x86_64 ;;
    selftest) run_selftest ;;
    all)
        build_linux
        build_android arm64-v8a
        build_android armeabi-v7a
        build_android x86_64
        ;;
    *)
        echo "用法：sh tool/build_lite_kernel.sh {linux|android-arm64-v8a|android-armeabi-v7a|android-x86_64|all|selftest}"
        exit 1
        ;;
esac
