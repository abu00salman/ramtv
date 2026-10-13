import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'store.dart';
import 'device_profile.dart';
import 'perf.dart';
import 'theme.dart';
import 'ui/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Perf.startFrameMonitor();
  MediaKit.ensureInitialized();
  await DeviceProfile.initialize();
  await store.init();
  themeController.load(store.prefs);
  runApp(const RamTvApp());
}

class RamTvApp extends StatefulWidget {
  const RamTvApp({super.key});

  @override
  State<RamTvApp> createState() => _RamTvAppState();
}

class _RamTvAppState extends State<RamTvApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    if (themeController.mode == AppThemeMode.auto && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final palette = themeController.resolve(brightness);
    Pal.current = palette;
    final theme = buildTheme(palette);
    return MaterialApp(
      title: 'RaM tv',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: palette.dark ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        var scale = 1.0;
        if (DeviceProfile.isTelevision) {
          // Scale text with the screen height (540dp = 1x) so 1080p TVs at any density stay readable.
          scale = (media.size.height / 540 * 1.1).clamp(1.15, 1.6).toDouble();
        }
        if (themeController.simple) scale *= 1.2;
        if (scale == 1.0) return child!;
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      home: const RootScreen(),
    );
  }
}
