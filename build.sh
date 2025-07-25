#!/usr/bin/env bash
#
# Kernel Build (A10 - Hybrid GCC) for Gitpod
# - Dengan cache agar tidak download ulang toolchains/NDK/AnyKernel3
# - Dengan make clean & mrproper untuk build fresh
#
# By Fannndi & ChatGPT

set -euo pipefail

# ============== Konfigurasi Default ==============
KERNEL_NAME="${KERNEL_NAME:-MIUI-A10}"
DEFCONFIG="${DEFCONFIG:-surya_defconfig}"

BUILD_USER="${BUILD_USER:-fannndi}"
BUILD_HOST="${BUILD_HOST:-gitpod}"

ARCH=arm64
SUBARCH=arm64

CLANG_URL="${CLANG_URL:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b.tar.gz}"
CLANG_TAG="${CLANG_TAG:-clang-r416183b}"

GCC64_REPO="${GCC64_REPO:-https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git}"
GCC32_REPO="${GCC32_REPO:-https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git}"
GCC_BRANCH="${GCC_BRANCH:-lineage-17.1}"

NDK_URL="${NDK_URL:-https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip}"
NDK_TAG="${NDK_TAG:-android-ndk-r21e}"

ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/rinnsakaguchi/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-FSociety}"

# Lokasi cache (persisten di Gitpod)
CACHE_ROOT="${CACHE_ROOT:-$HOME/.cache/kernel-build}"
TOOLCHAIN_DIR="$CACHE_ROOT/toolchains"
TARBALL_DIR="$CACHE_ROOT/tarballs"
ANYKERNEL_DIR="$CACHE_ROOT/AnyKernel3"

# Output / workspace
OUT_DIR="${OUT_DIR:-out}"
WORK_DIR="$(pwd)"

# ============== Helper Printing ==============
GREEN='\033[1;32m'; RED='\033[1;31m'; BLUE='\033[1;34m'; NC='\033[0m'
info () { echo -e "${BLUE}[INFO]${NC} $*"; }
ok   () { echo -e "${GREEN}[ OK ]${NC} $*"; }
err  () { echo -e "${RED}[ERR]${NC} $*"; }

# ============== Arg Parsing ==============
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --kernel-name <name>     (default: $KERNEL_NAME)
  --defconfig <defconfig>  (default: $DEFCONFIG)
  --clean                  Bersihkan output (out/, zip, log)
  -h, --help               Tampilkan bantuan

ENV override yg umum:
  BUILD_USER, BUILD_HOST, CLANG_URL, GCC64_REPO, GCC32_REPO, NDK_URL, CACHE_ROOT, OUT_DIR
EOF
}

CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel-name) KERNEL_NAME="$2"; shift 2 ;;
    --defconfig)   DEFCONFIG="$2";   shift 2 ;;
    --clean)       CLEAN=1;          shift ;;
    -h|--help)     usage; exit 0 ;;
    *) err "Argumen tidak dikenal: $1"; usage; exit 1 ;;
  esac
done

# ============== Prepare ==============
mkdir -p "$TOOLCHAIN_DIR" "$TARBALL_DIR" "$OUT_DIR"

BUILD_TIME="$(date '+%d%m%Y-%H%M')"
BUILD_ID="$(date '+%Y%m%d%H%M%S')"
ZIPNAME="${KERNEL_NAME}-Surya-${BUILD_TIME}.zip"
ZIP_PATH="$OUT_DIR/$ZIPNAME"
LOG_PATH="$OUT_DIR/log.txt"
BUILD_START="$(date +%s)"

CLANG_DIR="$TOOLCHAIN_DIR/$CLANG_TAG"
GCC64_DIR="$TOOLCHAIN_DIR/gcc64"
GCC32_DIR="$TOOLCHAIN_DIR/gcc32"
NDK_DIR="$TOOLCHAIN_DIR/$NDK_TAG"

# ============== Functions ==============
download_clang() {
  if [[ -x "$CLANG_DIR/bin/clang" ]]; then
    ok "Clang sudah ada di cache: $CLANG_DIR"
    return
  fi
  info "Mengunduh Clang..."
  mkdir -p "$CLANG_DIR"
  local tgz="$TARBALL_DIR/${CLANG_TAG}.tar.gz"
  if [[ ! -f "$tgz" ]]; then
    wget -q "$CLANG_URL" -O "$tgz"
  fi
  tar -xzf "$tgz" -C "$CLANG_DIR"
  ok "Clang siap."
}

download_gcc() {
  if [[ -x "$GCC64_DIR/bin/aarch64-linux-android-gcc" && -x "$GCC32_DIR/bin/arm-linux-androideabi-gcc" ]]; then
    ok "GCC 4.9 (32/64) sudah ada di cache."
    return
  fi
  info "Cloning GCC 4.9 (cached)..."
  if [[ ! -d "$GCC64_DIR/.git" ]]; then
    git clone --depth=1 -b "$GCC_BRANCH" "$GCC64_REPO" "$GCC64_DIR"
  fi
  if [[ ! -d "$GCC32_DIR/.git" ]]; then
    git clone --depth=1 -b "$GCC_BRANCH" "$GCC32_REPO" "$GCC32_DIR"
  fi
  ok "GCC siap."
}

download_ndk() {
  if [[ -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-ld.bfd" ]]; then
    ok "NDK sudah ada di cache."
    return
  fi
  info "Mengunduh NDK r21e..."
  local zip="$TARBALL_DIR/${NDK_TAG}.zip"
  if [[ ! -f "$zip" ]]; then
    wget -q "$NDK_URL" -O "$zip"
  fi
  unzip -q "$zip" -d "$TOOLCHAIN_DIR"
  mv "$TOOLCHAIN_DIR/$NDK_TAG" "$NDK_DIR" 2>/dev/null || true
  ok "NDK siap."
}

clone_anykernel() {
  if [[ -d "$ANYKERNEL_DIR/.git" ]]; then
    info "Update AnyKernel3 (cached)..."
    git -C "$ANYKERNEL_DIR" fetch origin "$ANYKERNEL_BRANCH" --depth=1
    git -C "$ANYKERNEL_DIR" checkout -f FETCH_HEAD
  else
    info "Clone AnyKernel3 (cached)..."
    git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
  fi
}

export_paths() {
  export PATH="$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
  export BUILD_USER BUILD_HOST ARCH SUBARCH
  export CROSS_COMPILE=aarch64-linux-android-
  export CROSS_COMPILE_ARM32=arm-linux-androideabi-
  export CLANG_TRIPLE=aarch64-linux-gnu-
  export LD="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-ld.bfd"
  export LLVM=1 LLVM_IAS=1
}

verify_tools() {
  info "Verifikasi toolchain..."
  clang --version | head -n1
  aarch64-linux-android-gcc --version | head -n1
  "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-ld.bfd" --version | head -n1 || true
  ok "Toolchain OK."
}

clean_output() {
  info "Membersihkan output lama..."
  make mrproper || true
  rm -rf "$OUT_DIR"/* AnyKernel3 *.zip || true
  mkdir -p "$OUT_DIR"
}

make_defconfig() {
  info "Menjalankan make clean..."
  make O="$OUT_DIR" clean || true
  info "Menjalankan defconfig: $DEFCONFIG"
  make O="$OUT_DIR" ARCH=arm64 \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    CC=clang HOSTCC=clang HOSTCXX=clang++ \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    LD="$LD" \
    LLVM=1 LLVM_IAS=1 \
    "$DEFCONFIG"
}

compile_kernel() {
  info "Compile kernel..."
  local JOBS
  JOBS=$(nproc --all)
  export MAKEFLAGS="-j$(( JOBS > 2 ? JOBS-1 : 2 )) -Oline"
  set +e
  make O="$OUT_DIR" ARCH=arm64 CC=clang HOSTCC=clang HOSTCXX=clang++ \
    LLVM=1 LLVM_IAS=1 Image.gz-dtb 2>&1 | tee "$LOG_PATH"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then
    tail -n 50 "$LOG_PATH"
    err "Compile gagal."
    exit 1
  fi
  ok "Compile selesai."
}

build_dtb() {
  info "Membuat dtb.img..."
  find "$OUT_DIR/arch/arm64/boot/dts" -type f -name "*.dtb" -print0 | sort -z | xargs -0 cat > "$OUT_DIR/dtb.img"
  ls -lh "$OUT_DIR/dtb.img"
}

build_dtbo() {
  info "Membuat dtbo.img..."
  local DTBO_LIST
  DTBO_LIST=$(find "$OUT_DIR/arch/arm64/boot/dts" -type f -name "*.dtbo")
  if [[ -z "$DTBO_LIST" ]]; then
    err "Tidak ada *.dtbo ditemukan"
    return 0
  fi
  python3 tools/makedtboimg.py create "$OUT_DIR/dtbo.img" $DTBO_LIST
  ls -lh "$OUT_DIR/dtbo.img"
}

package_anykernel() {
  info "Packaging AnyKernel3..."
  rm -rf AnyKernel3 && mkdir -p AnyKernel3
  rsync -a --delete "$ANYKERNEL_DIR/" AnyKernel3/
  cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" AnyKernel3/
  [[ -f "$OUT_DIR/dtb.img" ]]  && cp "$OUT_DIR/dtb.img"  AnyKernel3/
  [[ -f "$OUT_DIR/dtbo.img" ]] && cp "$OUT_DIR/dtbo.img" AnyKernel3/
  ( cd AnyKernel3 && zip -r9 "../${ZIP_PATH}" . -x '*.git*' README.md *placeholder )
  ok "Zip: ${ZIP_PATH}"
}

show_summary() {
  local END
  END="$(date +%s)"
  local DUR=$((END - BUILD_START))
  echo
  ok "Selesai! Zip: ${ZIP_PATH}"
  info "Waktu build: ${DUR}s"
  info "Artifacts:"
  ls -lh "$LOG_PATH" \
    "$OUT_DIR/.config" \
    "$OUT_DIR/dtb.img" 2>/dev/null || true
  ls -lh "$OUT_DIR/dtbo.img" 2>/dev/null || true
  ls -lh "$ZIP_PATH" 2>/dev/null || true
}

# ============== Main ==============
if [[ $CLEAN -eq 1 ]]; then
  clean_output
  exit 0
fi

info "== Kernel Build (Hybrid) - Gitpod =="
info "Kernel Name : $KERNEL_NAME"
info "Defconfig   : $DEFCONFIG"
info "Cache Dir   : $CACHE_ROOT"
info "OUT Dir     : $OUT_DIR"

download_clang
download_gcc
download_ndk
clone_anykernel
export_paths
verify_tools
clean_output
make_defconfig
compile_kernel
build_dtb
build_dtbo
package_anykernel
show_summary
