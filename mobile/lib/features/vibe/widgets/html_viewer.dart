import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../../core/theme.dart';

/// Safe HTML viewer with Catppuccin styling
/// Blocks dangerous tags (script, iframe, object, embed, form, style, meta)
class SafeHtmlViewer extends StatelessWidget {
  final String htmlContent;

  const SafeHtmlViewer({
    super.key,
    required this.htmlContent,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Html(
        data: htmlContent,
        style: {
          // Base styling
          'body': Style(
            color: CatppuccinMocha.text,
            fontSize: FontSize(14),
            lineHeight: LineHeight(1.6),
          ),
          // Headers
          'h1': Style(color: CatppuccinMocha.mauve, fontSize: FontSize(28)),
          'h2': Style(color: CatppuccinMocha.flamingo, fontSize: FontSize(24)),
          'h3': Style(color: CatppuccinMocha.lavender, fontSize: FontSize(20)),
          'h4': Style(color: CatppuccinMocha.blue, fontSize: FontSize(18)),
          'h5': Style(color: CatppuccinMocha.sapphire, fontSize: FontSize(16)),
          'h6': Style(color: CatppuccinMocha.sky, fontSize: FontSize(14)),
          // Links
          'a': Style(
            color: CatppuccinMocha.blue,
            textDecoration: TextDecoration.underline,
          ),
          // Code
          'code': Style(
            color: CatppuccinMocha.green,
            backgroundColor: CatppuccinMocha.surface0,
            fontFamily: 'monospace',
          ),
          'pre': Style(
            backgroundColor: CatppuccinMocha.mantle,
            padding: HtmlPaddings.all(12),
          ),
          // Blockquote
          'blockquote': Style(
            color: CatppuccinMocha.subtext0,
            fontStyle: FontStyle.italic,
            border: Border(left: BorderSide(color: CatppuccinMocha.mauve, width: 4)),
            padding: HtmlPaddings.only(left: 16),
          ),
        },
        onLinkTap: (url, attributes, element) {
          if (url != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Link: $url')),
            );
          }
        },
        extensions: [
          // Block dangerous tags - render as empty
          TagExtension(
            tagsToExtend: {'script', 'iframe', 'object', 'embed', 'form', 'style', 'meta', 'base', 'link'},
            builder: (extensionContext) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
