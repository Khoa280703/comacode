import 'package:flutter/material.dart';

/// Catppuccin Mocha theme for flutter_highlight
///
/// Based on Catppuccin Mocha palette
const catppuccinMochaTheme = {
  'root': TextStyle(
    backgroundColor: Color(0xFF1e1e2e),  // base
    color: Color(0xFFcdd6f4),  // text
  ),
  'keyword': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'built_in': TextStyle(color: Color(0xFFf38ba8)),  // red
  'type': TextStyle(color: Color(0xFFf9e2af)),  // yellow
  'literal': TextStyle(color: Color(0xFFfab387)),  // peach
  'number': TextStyle(color: Color(0xFFfab387)),  // peach
  'operator': TextStyle(color: Color(0xFF89dceb)),  // sky
  'punctuation': TextStyle(color: Color(0xFF9399b2)),  // overlay2
  'string': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'subst': TextStyle(color: Color(0xFFcdd6f4)),  // text
  'symbol': TextStyle(color: Color(0xFFf5c2e7)),  // pink
  'class': TextStyle(color: Color(0xFFf9e2af)),  // yellow
  'function': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'title': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'title.class': TextStyle(color: Color(0xFFf9e2af)),  // yellow
  'title.function': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'params': TextStyle(color: Color(0xFFcdd6f4)),  // text
  'comment': TextStyle(
    color: Color(0xFF6c7086),  // overlay0
    fontStyle: FontStyle.italic,
  ),
  'doctag': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'meta': TextStyle(color: Color(0xFFf9e2af)),  // yellow
  'meta-keyword': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'meta-string': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'section': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'tag': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'name': TextStyle(color: Color(0xFF89dceb)),  // sky
  'attr': TextStyle(color: Color(0xFFf9e2af)),  // yellow
  'attribute': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'variable': TextStyle(color: Color(0xFFf38ba8)),  // red
  'bullet': TextStyle(color: Color(0xFFfab387)),  // peach
  'code': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
  'formula': TextStyle(color: Color(0xFFa6e3a1)),  // green
  'link': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'quote': TextStyle(color: Color(0xFF6c7086)),  // overlay0
  'selector-tag': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'selector-id': TextStyle(color: Color(0xFF89b4fa)),  // blue
  'selector-class': TextStyle(color: Color(0xFF94e2d5)),  // teal
  'selector-attr': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'selector-pseudo': TextStyle(color: Color(0xFF94e2d5)),  // teal
  'template-tag': TextStyle(color: Color(0xFFcba6f7)),  // mauve
  'template-variable': TextStyle(color: Color(0xFFf38ba8)),  // red
  'addition': TextStyle(
    color: Color(0xFFa6e3a1),  // green
    backgroundColor: Color(0xFF1e1e2e),
  ),
  'deletion': TextStyle(
    color: Color(0xFFf38ba8),  // red
    backgroundColor: Color(0xFF1e1e2e),
  ),
};
