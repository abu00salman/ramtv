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
    for tag, name in [
        ("uses-permission", "android.permission.INTERNET"),
        ("uses-feature", "android.hardware.touchscreen"),
        ("uses-feature", "android.software.leanback"),
    ]:
        if name not in s:
            required = ' android:required="false"' if tag == "uses-feature" else ""
            s = s.replace("<application", f'<{tag} android:name="{name}"{required}/>\n    <application', 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="RaM tv"', s, count=1)
    # Keep HTTP compatibility for user-provided IPTV servers; never disable TLS verification.
    for key, value in [("usesCleartextTraffic", "true"), ("banner", "@drawable/banner"), ("allowBackup", "false")]:
        if re.search(rf'android:{key}="[^"]*"', s):
            s = re.sub(rf'android:{key}="[^"]*"', f'android:{key}="{value}"', s, count=1)
        else:
            s = s.replace("<application", f'<application android:{key}="{value}"', 1)
    if "android.intent.category.LEANBACK_LAUNCHER" not in s:
        s = re.sub(
        r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
        r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        s,
        count=1,
        )
    # Picture-in-picture: the activity must opt in before it can enter PiP.
    if "supportsPictureInPicture" not in s:
        s = re.sub(r"<activity\b", '<activity android:supportsPictureInPicture="true"', s, count=1)
    write(p, s)

    # Generated scaffolds are disposable; keep the TV bridge in this source script.
    import glob
    for activity in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
        kotlin = read(activity)
        if "ramtv/pip" in kotlin:
            continue
        package = re.search(r"^package\s+([\w.]+)", kotlin, re.MULTILINE)
        if package:
            write(activity, f"""package {package.group(1)}

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    private var playing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ramtv/device")
            .setMethodCallHandler {{ call, result ->
                if (call.method == "isTelevision") {{
                    val manager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    result.success(manager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                }} else {{
                    result.notImplemented()
                }}
            }}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ramtv/pip")
            .setMethodCallHandler {{ call, result ->
                if (call.method == "setPlaying") {{
                    playing = call.arguments as? Boolean ?: false
                    result.success(null)
                }} else {{
                    result.notImplemented()
                }}
            }}
    }}

    // Home (or any exit from the app) while a stream plays moves it into a PiP window.
    override fun onUserLeaveHint() {{
        super.onUserLeaveHint()
        if (playing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
            )
        }}
    }}
}}
""")

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
