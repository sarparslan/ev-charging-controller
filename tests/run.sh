#!/usr/bin/env sh
# Build the controller with the RuSTy IEC 61131-3 compiler and run the
# scenario tests. Uses Docker unless `plc` is already on PATH (e.g. in CI).
set -eu
cd "$(dirname "$0")/.."

IMAGE="ghcr.io/plc-lang/rusty:master-x86_64"
STDLIB="${STDLIBLOC:-/opt/rusty/stdlib}"
SOURCES="$(find Types Communication Control Safety tests -name '*.st' | sort)"

build_and_run='
set -eu
mkdir -p build
plc $SOURCES -i "$STDLIB/include/*.st" \
    -L "$STDLIB/x86_64-linux-gnu/lib" -l iec61131std --linker=cc -o build/tests
LD_LIBRARY_PATH="$STDLIB/x86_64-linux-gnu/lib" ./build/tests
'

if command -v plc >/dev/null 2>&1; then
    SOURCES="$SOURCES" STDLIB="$STDLIB" sh -c "$build_and_run"
else
    docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src \
        -e SOURCES="$SOURCES" -e STDLIB="$STDLIB" \
        --entrypoint sh "$IMAGE" -c "$build_and_run"
fi
