import os, re, sys, shutil, plistlib

platform = sys.argv[1]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


if platform == "android":
    p = "android/app/src/main/AndroidManifest.xml"
    s = read(p)
    if "android.permission.INTERNET" not in s:
        s = s.replace(
            "<application",
            '<uses-permission android:name="android.permission.INTERNET"/>\n'
            '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
            '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
            "    <application",
            1,
        )
    s = re.sub(r'android:label="[^"]*"', 'android:label="RaM tv"', s, count=1)
    s = s.replace(
        "<application",
        '<application android:usesCleartextTraffic="true" android:banner="@drawable/banner"',
        1,
    )
    s = re.sub(
        r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
        r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        s,
        count=1,
    )
    write(p, s)

    os.makedirs("android/app/src/main/res/drawable", exist_ok=True)
    shutil.copy("assets/banner.png", "android/app/src/main/res/drawable/banner.png")

    write(
        "android/app/proguard-rules.pro",
        "-keep class com.alexmercerind.** { *; }\n-keep class media.kit.** { *; }\n-dontwarn **\n",
    )

    for g, old, new in [
        (
            "android/app/build.gradle.kts",
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = signingConfigs.getByName("debug")\n            isMinifyEnabled = false\n            isShrinkResources = false',
        ),
        (
            "android/app/build.gradle",
            "signingConfig signingConfigs.debug",
            "signingConfig signingConfigs.debug\n            minifyEnabled false\n            shrinkResources false",
        ),
    ]:
        if os.path.exists(g):
            t = read(g)
            if old in t and "isMinifyEnabled" not in t and "minifyEnabled" not in t:
                write(g, t.replace(old, new, 1))

elif platform == "macos":
    p = "macos/Runner/Configs/AppInfo.xcconfig"
    if os.path.exists(p):
        s = read(p)
        s = re.sub(r"PRODUCT_NAME\s*=.*", "PRODUCT_NAME = RaMtv", s)
        write(p, s)

    for ent in ["macos/Runner/DebugProfile.entitlements", "macos/Runner/Release.entitlements"]:
        with open(ent, "rb") as f:
            d = plistlib.load(f)
        d["com.apple.security.network.client"] = True
        with open(ent, "wb") as f:
            plistlib.dump(d, f)

    ip = "macos/Runner/Info.plist"
    with open(ip, "rb") as f:
        d = plistlib.load(f)
    d["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
    d["CFBundleDisplayName"] = "RaM tv"
    with open(ip, "wb") as f:
        plistlib.dump(d, f)

    pb = "macos/Runner.xcodeproj/project.pbxproj"
    s = read(pb)
    s = re.sub(r"MACOSX_DEPLOYMENT_TARGET = [0-9.]+;", "MACOSX_DEPLOYMENT_TARGET = 11.0;", s)
    write(pb, s)

    pf = "macos/Podfile"
    if os.path.exists(pf):
        s = read(pf)
        s = re.sub(r"platform :osx, '[0-9.]+'", "platform :osx, '11.0'", s)
        write(pf, s)

elif platform == "windows":
    p = "windows/runner/main.cpp"
    if os.path.exists(p):
        s = read(p)
        s = s.replace('L"ramtv"', 'L"RaM tv"')
        write(p, s)

print("patched", platform)
