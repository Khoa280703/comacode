import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'features/connection/home_page.dart';
import 'bridge/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Static library (.a) is linked via -force_load, symbols are in main process
  await RustLib.init();

  runApp(
    const ProviderScope(
      child: ComacodeApp(),
    ),
  );
}

class ComacodeApp extends StatelessWidget {
  const ComacodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comacode',
      debugShowCheckedModeBanner: false,
      theme: CatppuccinMocha.lightTheme,
      darkTheme: CatppuccinMocha.darkTheme,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
