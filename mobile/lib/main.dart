import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'features/connection/home_page.dart';

void main() {
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
