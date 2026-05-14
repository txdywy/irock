#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT="$SCRIPT_DIR/irock-macOS.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build/unsigned"
DERIVED_DATA="$BUILD_DIR/DerivedData"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme irockMacApp \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug/irockMacApp.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected app bundle not found: $APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$BUILD_DIR/irockMacApp.app"
APP_BUNDLE="$BUILD_DIR/irockMacApp.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/irockMacApp"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

brew_prefix() {
  brew --prefix "$1" 2>/dev/null
}

NGTCP2_PREFIX=${NGTCP2_PREFIX:-$(brew_prefix libngtcp2)}
NGHTTP3_PREFIX=${NGHTTP3_PREFIX:-$(brew_prefix libnghttp3)}
OPENSSL_PREFIX=${OPENSSL_PREFIX:-$(brew_prefix openssl@3)}

NGTCP2_DYLIB="$NGTCP2_PREFIX/lib/libngtcp2.16.dylib"
NGTCP2_CRYPTO_DYLIB="$NGTCP2_PREFIX/lib/libngtcp2_crypto_ossl.0.dylib"
NGHTTP3_DYLIB="$NGHTTP3_PREFIX/lib/libnghttp3.9.dylib"
SSL_DYLIB="$OPENSSL_PREFIX/lib/libssl.3.dylib"
CRYPTO_DYLIB="$OPENSSL_PREFIX/lib/libcrypto.3.dylib"

copy_dylib() {
  dylib="$1"
  if [ ! -f "$dylib" ]; then
    echo "Required dylib not found: $dylib" >&2
    exit 1
  fi
  cp -f "$dylib" "$FRAMEWORKS_DIR/$(basename "$dylib")"
  chmod u+w "$FRAMEWORKS_DIR/$(basename "$dylib")"
  install_name_tool -id "@rpath/$(basename "$dylib")" "$FRAMEWORKS_DIR/$(basename "$dylib")"
}

patch_binary_reference() {
  binary="$1"
  dylib="$2"
  install_name_tool -change "$dylib" "@rpath/$(basename "$dylib")" "$binary" 2>/dev/null || true
  real_dylib=$(realpath "$dylib")
  install_name_tool -change "$real_dylib" "@rpath/$(basename "$dylib")" "$binary" 2>/dev/null || true
}

copy_dylib "$NGTCP2_DYLIB"
copy_dylib "$NGTCP2_CRYPTO_DYLIB"
copy_dylib "$NGHTTP3_DYLIB"
copy_dylib "$SSL_DYLIB"
copy_dylib "$CRYPTO_DYLIB"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_EXECUTABLE" 2>/dev/null || true

for binary in "$APP_EXECUTABLE" "$FRAMEWORKS_DIR"/*.dylib; do
  patch_binary_reference "$binary" "$NGTCP2_DYLIB"
  patch_binary_reference "$binary" "$NGTCP2_CRYPTO_DYLIB"
  patch_binary_reference "$binary" "$NGHTTP3_DYLIB"
  patch_binary_reference "$binary" "$SSL_DYLIB"
  patch_binary_reference "$binary" "$CRYPTO_DYLIB"
done

codesign --force --deep --sign - "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
