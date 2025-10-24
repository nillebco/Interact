#!/usr/bin/env bash
# Simple helper to build and run InteractApp from the CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_DIR="${REPO_ROOT}/.build/DerivedData"
PROJECT_PATH="${REPO_ROOT}/Interact.xcodeproj"
SCHEME_NAME="Interact"
PRODUCT_NAME="Interact"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found on PATH." >&2
  exit 1
fi

BUILD_CONFIGURATION="Debug"
if [[ "${1:-}" == "--release" ]]; then
  BUILD_CONFIGURATION="Release"
  shift
fi

APP_BUNDLE_PATH="${DERIVED_DATA_DIR}/Build/Products/${BUILD_CONFIGURATION}/${PRODUCT_NAME}.app"
APP_EXECUTABLE_PATH="${APP_BUNDLE_PATH}/Contents/MacOS/${PRODUCT_NAME}"

echo "Building ${PRODUCT_NAME} (${BUILD_CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -sdk macosx \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -x "${APP_EXECUTABLE_PATH}" ]]; then
  echo "error: build succeeded but executable not found at ${APP_EXECUTABLE_PATH}" >&2
  exit 1
fi

echo "Launching ${PRODUCT_NAME}..."
exec "${APP_EXECUTABLE_PATH}" "$@"
