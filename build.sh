#!/bin/bash
set -eo pipefail

xcodegen generate
pod install

xcodebuild -workspace RaMtv.xcworkspace -scheme RaMtv \
  -configuration Release -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -n 150

rm -rf Payload RaM-tv-unsigned.ipa
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/RaMtv.app Payload/
zip -qry RaM-tv-unsigned.ipa Payload
ls -la RaM-tv-unsigned.ipa
