import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme.dart';

/// Catppuccin Mocha themed markdown stylesheet
MarkdownStyleSheet catppuccinMarkdownTheme(BuildContext context) {
  return MarkdownStyleSheet(
    // Headers
    h1: TextStyle(color: CatppuccinMocha.mauve, fontSize: 28, fontWeight: FontWeight.bold),
    h2: TextStyle(color: CatppuccinMocha.flamingo, fontSize: 24, fontWeight: FontWeight.bold),
    h3: TextStyle(color: CatppuccinMocha.lavender, fontSize: 20, fontWeight: FontWeight.w600),
    h4: TextStyle(color: CatppuccinMocha.blue, fontSize: 18, fontWeight: FontWeight.w600),
    h5: TextStyle(color: CatppuccinMocha.sapphire, fontSize: 16, fontWeight: FontWeight.w600),
    h6: TextStyle(color: CatppuccinMocha.sky, fontSize: 14, fontWeight: FontWeight.w600),

    // Body text
    p: TextStyle(color: CatppuccinMocha.text, fontSize: 14, height: 1.6),

    // Links
    a: TextStyle(color: CatppuccinMocha.blue, decoration: TextDecoration.underline),

    // Code
    code: TextStyle(
      color: CatppuccinMocha.green,
      backgroundColor: CatppuccinMocha.surface0,
      fontFamily: 'monospace',
      fontSize: 13,
    ),
    codeblockDecoration: BoxDecoration(
      color: CatppuccinMocha.mantle,
      borderRadius: BorderRadius.circular(8),
    ),
    codeblockPadding: const EdgeInsets.all(12),

    // Lists
    listBullet: TextStyle(color: CatppuccinMocha.mauve),

    // Blockquote
    blockquote: TextStyle(color: CatppuccinMocha.subtext0, fontStyle: FontStyle.italic),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: CatppuccinMocha.mauve, width: 4)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 16),

    // Horizontal rule
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: CatppuccinMocha.surface1, width: 1)),
    ),

    // Table
    tableHead: TextStyle(color: CatppuccinMocha.text, fontWeight: FontWeight.bold),
    tableBody: TextStyle(color: CatppuccinMocha.subtext1),
    tableBorder: TableBorder.all(color: CatppuccinMocha.surface1),
  );
}
