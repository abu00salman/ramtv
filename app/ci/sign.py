import os, re, sys

ks = "android/app/ramtv.keystore"
if not os.path.exists(ks):
    print("No fixed keystore present; leaving default signing")
    sys.exit(0)

kts = "android/app/build.gradle.kts"
groovy = "android/app/build.gradle"

if os.path.exists(kts):
    s = open(kts, encoding="utf-8").read()
    block = (
        'signingConfigs {\n'
        '        create("ramtv") {\n'
        '            storeFile = file("ramtv.keystore")\n'
        '            storePassword = "android"\n'
        '            keyAlias = "androiddebugkey"\n'
        '            keyPassword = "android"\n'
        '        }\n'
        '    }\n'
    )
    if 'create("ramtv")' not in s:
        s, n = re.subn(r'(\n[ \t]*)(buildTypes\s*\{)', lambda m: m.group(1) + block.replace("\n", m.group(1)) + m.group(1) + m.group(2), s, count=1)
        print("inserted signingConfigs:", n)
    s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("ramtv")')
    open(kts, "w", encoding="utf-8").write(s)
    print("patched", kts)
elif os.path.exists(groovy):
    s = open(groovy, encoding="utf-8").read()
    block = (
        "signingConfigs {\n"
        "        ramtv {\n"
        "            storeFile file('ramtv.keystore')\n"
        "            storePassword 'android'\n"
        "            keyAlias 'androiddebugkey'\n"
        "            keyPassword 'android'\n"
        "        }\n"
        "    }\n"
    )
    if "ramtv {" not in s:
        s, n = re.subn(r'(\n[ \t]*)(buildTypes\s*\{)', lambda m: m.group(1) + block.replace("\n", m.group(1)) + m.group(1) + m.group(2), s, count=1)
        print("inserted signingConfigs:", n)
    s = s.replace("signingConfigs.debug", "signingConfigs.ramtv")
    open(groovy, "w", encoding="utf-8").write(s)
    print("patched", groovy)
else:
    print("No gradle file found")
    sys.exit(1)
