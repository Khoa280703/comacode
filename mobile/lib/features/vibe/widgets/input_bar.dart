import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../connection/connection_providers.dart';
import '../models/file_attachment.dart';
import '../services/haptic_service.dart';
import '../vibe_session_providers.dart';
import 'attachment_button.dart';
import 'dictation_button.dart';
import 'quick_keys_toolbar.dart';

/// Input bar with prompt field and send button
class InputBar extends ConsumerStatefulWidget {
  const InputBar({super.key});

  @override
  ConsumerState<InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<InputBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final List<String> _attachedFiles = [];
  AttachmentFormat _attachmentFormat = AttachmentFormat.path;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    // Listen to text changes to update send button state
    _controller.addListener(() {
      if (mounted) {
        setState(() {}); // Rebuild when text changes
      }
    });
    // Auto-focus on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    // Haptic feedback for send
    await HapticService.medium();

    // Build prompt with attachments
    String finalPrompt = text;

    if (_attachedFiles.isNotEmpty && _attachmentFormat == AttachmentFormat.path) {
      // Add path references at the beginning
      final paths = _attachedFiles.map((p) => '@$p').join(' ');
      if (finalPrompt.isNotEmpty) {
        finalPrompt = '$paths $finalPrompt';
      } else {
        finalPrompt = paths;
      }
    }

    // Keep focus for next prompt (keyboard stays open)
    _controller.clear();
    _attachedFiles.clear();
    setState(() {}); // Update attachment button badge

    await ref.read(vibeSessionProvider.notifier).sendPrompt(finalPrompt);
  }

  void _handleFilesAttached(List<String> paths, AttachmentFormat format) {
    HapticService.light();
    setState(() {
      _attachedFiles.clear();
      _attachedFiles.addAll(paths);
      _attachmentFormat = format;
    });

    // If content format, insert content directly (placeholder for now)
    // TODO: Implement file content reading from backend
    if (format == AttachmentFormat.content) {
      for (final path in paths) {
        _controller.text += '\n// TODO: Content of $path will be inserted\n';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(vibeSessionProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final isConnected = connectionState.isConnected;
    final isSending = sessionState.isSending;

    return Column(
      children: [
        // Input field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: CatppuccinMocha.surface0,
            border: Border(
              top: BorderSide(color: CatppuccinMocha.surface1, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Prompt indicator
              Text(
                '\$ ',
                style: TextStyle(
                  color: CatppuccinMocha.green,
                  fontFamily: 'monospace',
                  fontSize: 16,
                ),
              ),
              // Text field
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (isConnected) {
                      _focusNode.requestFocus();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: isConnected,
                    style: TextStyle(
                      color: CatppuccinMocha.text,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your prompt...',
                      hintStyle: TextStyle(
                        color: CatppuccinMocha.overlay1,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendPrompt(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Attachment button
              AttachmentButton(
                attachmentCount: _attachedFiles.length,
                onFilesSelected: _handleFilesAttached,
              ),
              const SizedBox(width: 8),
              // Dictation button
              DictationButton(
                onTextRecognized: (text) {
                  // Append recognized text to input field
                  _controller.value = TextEditingValue(
                    text: _controller.text + text,
                    selection: TextSelection.collapsed(
                      offset: _controller.text.length + text.length,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Send button
              _SendButton(
                isEnabled: isConnected &&
                    !isSending &&
                    _controller.text.trim().isNotEmpty,
                isLoading: isSending,
                onPressed: _sendPrompt,
              ),
            ],
          ),
        ),
        // Quick keys toolbar
        QuickKeysToolbar(
          onKeyPressed: (key) =>
              ref.read(vibeSessionProvider.notifier).sendSpecialKey(key),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isEnabled;
  final bool isLoading;
  final VoidCallback onPressed;

  const _SendButton({
    required this.isEnabled,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isEnabled
          ? CatppuccinMocha.mauve
          : CatppuccinMocha.surface0,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      CatppuccinMocha.crust,
                    ),
                  ),
                )
              : Icon(
                  Icons.send,
                  color: isEnabled
                      ? CatppuccinMocha.crust
                      : CatppuccinMocha.overlay1,
                  size: 18,
                ),
        ),
      ),
    );
  }
}
