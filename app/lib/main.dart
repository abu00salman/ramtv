import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'store.dart';
import 'ui/screens.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await store.init();
  runApp(const RamTvApp());
}

class RamTvApp extends StatelessWidget {
  const RamTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: kBrand, brightness: Brightness.dark).copyWith(primary: kBrand),
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
      home: const RootScreen(),
    );
  }
}
