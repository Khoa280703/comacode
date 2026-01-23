import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../core/theme.dart';

/// Output view using xterm for terminal display
///
/// ⚠️ AUTO-SCROLL WARNING:
/// Chỉ auto-scroll khi user đang ở bottom. Nếu user scroll lên xem log cũ,
/// KHÔNG tự động scroll khi output mới đến.
///
/// Note: xterm.dart 4.0 has built-in scroll management.
/// This wrapper provides the Catppuccin theme.
class OutputView extends StatelessWidget {
  final Terminal terminal;
  final bool isParsedMode;
  final VoidCallback? onFileTap;

  const OutputView({
    super.key,
    required this.terminal,
    this.isParsedMode = false,
    this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CatppuccinMocha.terminalBackground,
      child: TerminalView(
        terminal,
        textStyle: TerminalStyle(
          fontSize: 14,
          fontFamily: 'Courier',
          height: 1.4,
        ),
        theme: TerminalTheme(
          cursor: CatppuccinMocha.green,
          selection: CatppuccinMocha.surface1,
          foreground: CatppuccinMocha.terminalForeground,
          background: CatppuccinMocha.terminalBackground,
          black: CatppuccinMocha.surface0,
          red: CatppuccinMocha.red,
          green: CatppuccinMocha.green,
          yellow: CatppuccinMocha.yellow,
          blue: CatppuccinMocha.blue,
          magenta: CatppuccinMocha.mauve,
          cyan: CatppuccinMocha.teal,
          white: CatppuccinMocha.text,
          brightBlack: CatppuccinMocha.surface1,
          brightRed: CatppuccinMocha.red,
          brightGreen: CatppuccinMocha.green,
          brightYellow: CatppuccinMocha.yellow,
          brightBlue: CatppuccinMocha.blue,
          brightMagenta: CatppuccinMocha.mauve,
          brightCyan: CatppuccinMocha.teal,
          brightWhite: CatppuccinMocha.text,
          searchHitBackground: CatppuccinMocha.yellow,
          searchHitBackgroundCurrent: CatppuccinMocha.peach,
          searchHitForeground: CatppuccinMocha.base,
        ),
      ),
    );
  }
}
