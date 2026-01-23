import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../models/file_attachment.dart';
import 'file_attachment_picker.dart';

/// Attachment button for file picker in Vibe Coding
///
/// Phase 02: File Attachment
/// Shows badge when files are attached
class AttachmentButton extends ConsumerWidget {
  final int attachmentCount;
  final Function(List<String> paths, AttachmentFormat format) onFilesSelected;

  const AttachmentButton({
    super.key,
    this.attachmentCount = 0,
    required this.onFilesSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => showFileAttachmentPicker(
        context,
        onFilesSelected: onFilesSelected,
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: attachmentCount > 0
              ? CatppuccinMocha.blue.withValues(alpha: 0.2)
              : CatppuccinMocha.surface0,
          shape: BoxShape.circle,
          border: Border.all(
            color: attachmentCount > 0
                ? CatppuccinMocha.blue
                : CatppuccinMocha.surface1,
            width: 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.attach_file,
              color: attachmentCount > 0
                  ? CatppuccinMocha.blue
                  : CatppuccinMocha.text,
              size: 20,
            ),
            if (attachmentCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: CatppuccinMocha.blue,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  child: Center(
                    child: Text(
                      attachmentCount > 9 ? '9+' : '$attachmentCount',
                      style: TextStyle(
                        color: CatppuccinMocha.crust,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
