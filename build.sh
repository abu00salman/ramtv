#!/bin/bash
set -o pipefail

if [ -n "${TMDB_KEY:-}" ]; then
  printf 'let builtInTMDBKey = "%s"\n' "$TMDB_KEY" > RaMtv/BuiltInKey.swift
fi

xcodegen generate
pod install

set +e
xcodebuild -workspace RaMtv.xcworkspace -scheme RaMtv \
  -configuration Release -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > build.log 2>&1
status=$?
set -e

if [ $status -ne 0 ]; then
  echo "=================== COMPILER ERRORS ==================="
  grep -E "error:" build.log | sort -u | head -40
  echo "======================================================="
  exit $status
fi
tail -n 5 build.log

rm -rf Payload RaM-tv-unsigned.ipa
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/RaMtv.app Payload/
zip -qry RaM-tv-unsigned.ipa Payload
ls -la RaM-tv-unsigned.ipa
