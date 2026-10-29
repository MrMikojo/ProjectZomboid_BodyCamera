#!/usr/bin/env bash
# Builds BaseCCTV.jar into the mod folder. Needs a JDK 17+ (targets Java 17 bytecode,
# like Death Cam, so it loads on ZombieBuddy 2.x and 3.x).
# The stubs only satisfy the compiler; the real classes come from the game at runtime.
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../Contents/mods/BaseCCTV/42/media/java/client
rm -rf build
mkdir -p build/stubs build/classes "$OUT"
javac --release 17 -d build/stubs $(find stubs -name '*.java')
javac --release 17 -cp build/stubs -d build/classes $(find src -name '*.java')
jar --create --file "$OUT/BaseCCTV.jar" -C build/classes .
rm -rf build
echo "Built $OUT/BaseCCTV.jar"
