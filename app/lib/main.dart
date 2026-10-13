import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'store.dart';
import 'device_profile.dart';
import 'ui/screens.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await DeviceProfile.initialize();
  await store.init();
  runApp(const RamTvApp());
}

class RamTvApp extends StatelessWidget {
  const RamTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlexArabic',
      brightness: Brightness.dark,
      colorScheme:
          ColorScheme.fromSeed(seedColor: kBrand, brightness: Brightness.dark)
              .copyWith(primary: kBrand),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
    );
    return MaterialApp(
      title: 'RaM tv',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      builder: (context, child) {
        final tv = DeviceProfile.isTelevision;
        if (!tv) return child!;
        // Scale text with the screen height (540dp = 1x) so 1080p TVs at any density stay readable.
        final h = MediaQuery.of(context).size.height;
        final scale = (h / 540 * 1.1).clamp(1.15, 1.6).toDouble();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      home: const RootScreen(),
    );
  }
}
