#!/bin/bash -e

# Set variable defaults
: "${BUILD_OS:=linux}"
: "${BUILD_ARCHITECTURE:=x64}"
: "${BUILD_CONFIG:=release}"
: "${PREMAKE_FILE:=premake5.lua}"
: "${GCC_VERSION:=10}"
: "${LUAJIT_CC:=gcc-${GCC_VERSION}}"

# Find premake binary location
if [ "$(uname)" == "Darwin" ]; then
    PREMAKE5=utils/premake5-macos
else
    PREMAKE5=utils/premake5
fi

if [ "$(uname)" == "Darwin" ]; then
    : "${GCC_PREFIX:=}"
    : "${AR:=ar}"
    : "${CC:=gcc}"
    : "${CXX:=g++}"
fi

# Number of cores
if [[ -z "$NUM_CORES" ]]; then
    if [ "$(uname)" == "Darwin" ]; then
        NUM_CORES=$(sysctl -n hw.ncpu)
    else
        NUM_CORES=$(grep -c ^processor /proc/cpuinfo)
    fi
fi

# Read script arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --os=*)     BUILD_OS="${1#*=}"              ;;
        --arch=*)   BUILD_ARCHITECTURE="${1#*=}"    ;;
        --config=*) BUILD_CONFIG="${1#*=}"          ;;
        --cores=*)  NUM_CORES="${1#*=}"             ;;
        --file=*)   PREMAKE_FILE="${1#*=}"          ;;
        *)
            echo "Error: Invalid argument: $1" >&2
            exit 1
    esac
    shift
done

# Display script arguments
echo "Build configuration:"
echo "  BUILD_ARCHITECTURE = $BUILD_ARCHITECTURE"
echo "  BUILD_CONFIG = $BUILD_CONFIG"

# Verify script arguments
case $BUILD_CONFIG in
    debug|release) ;;
    *)
        echo "Error: Invalid build configuration" >&2
        exit 1
esac

case $BUILD_ARCHITECTURE in
    32|x86)
        CONFIG=${BUILD_CONFIG}_x86
        : "${AR:=x86_64-linux-gnu-gcc-ar-${GCC_VERSION}}"
        : "${CC:=x86_64-linux-gnu-gcc-${GCC_VERSION}}"
        : "${CXX:=x86_64-linux-gnu-g++-${GCC_VERSION}}"
        LUAJIT_CC="${LUAJIT_CC} -m32"
    ;;
    64|x64)
        CONFIG=${BUILD_CONFIG}_x64
        : "${AR:=x86_64-linux-gnu-gcc-ar-${GCC_VERSION}}"
        : "${CC:=x86_64-linux-gnu-gcc-${GCC_VERSION}}"
        : "${CXX:=x86_64-linux-gnu-g++-${GCC_VERSION}}"
    ;;
    arm)
        CONFIG=${BUILD_CONFIG}_${BUILD_ARCHITECTURE}
        : "${GCC_PREFIX:=arm-linux-gnueabihf-}"
        : "${AR:=arm-linux-gnueabihf-ar}"
        : "${CC:=arm-linux-gnueabihf-gcc-${GCC_VERSION}}"
        : "${CXX:=arm-linux-gnueabihf-g++-${GCC_VERSION}}"
        LUAJIT_HOST_CC="x86_64-linux-gnu-${LUAJIT_CC} -m32"
    ;;
    arm64)
        CONFIG=${BUILD_CONFIG}_${BUILD_ARCHITECTURE}
        : "${GCC_PREFIX:=aarch64-linux-gnu-}"
        : "${AR:=aarch64-linux-gnu-gcc-ar-${GCC_VERSION}}"
        : "${CC:=aarch64-linux-gnu-gcc-${GCC_VERSION}}"
        : "${CXX:=aarch64-linux-gnu-g++-${GCC_VERSION}}"
    ;;
    *)
        echo "Error: Invalid build architecture" >&2
        exit 1
esac

export LUAJIT_CC LUAJIT_HOST_CC

echo "  OS = $BUILD_OS"
echo "  CONFIG = $CONFIG"
echo "  AR = $AR"
echo "  CC = $CC"
echo "  CXX = $CXX"
echo "  NUM_CORES = $NUM_CORES"
if [[ -n "$LUAJIT_CC" ]]; then
    echo "  LUAJIT_CC = $LUAJIT_CC"
fi
if [[ -n "$LUAJIT_HOST_CC" ]]; then
    echo "  LUAJIT_HOST_CC = $LUAJIT_HOST_CC"
fi

# Clean old build files
rm -Rf Build/
rm -Rf Bin/

# Generate Makefiles
if [[ -n "$GCC_PREFIX" ]]; then
    $PREMAKE5 --gccprefix="$GCC_PREFIX" --os="$BUILD_OS" --file="$PREMAKE_FILE" gmake
else
    $PREMAKE5 --os="$BUILD_OS" --file="$PREMAKE_FILE" gmake
fi

# Build!
make -C Build/ -j "${NUM_CORES}" AR="${AR}" CC="${CC}" CXX="${CXX}" config="${CONFIG}"
