import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'features/connection/connection_provider.dart';
import 'features/connection/home_page.dart';

void main() {
  runApp(const ComacodeApp());
}

class ComacodeApp extends StatelessWidget {
  const ComacodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConnectionProvider(),
      child: MaterialApp(
        title: 'Comacode',
        debugShowCheckedModeBanner: false,
        theme: CatppuccinMocha.lightTheme,
        darkTheme: CatppuccinMocha.darkTheme,
        themeMode: ThemeMode.dark,
        home: const HomePage(),
      ),
    );
  }
}
