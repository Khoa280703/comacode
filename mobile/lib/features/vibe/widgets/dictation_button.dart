import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../services/speech_service_provider.dart';

/// Dictation button for voice input in Vibe Coding
///
/// Phase 02: Dictation Integration
/// - Pulse animation when recording
/// - Vietnamese language support
/// - Real-time text display
class DictationButton extends ConsumerStatefulWidget {
  final ValueChanged<String> onTextRecognized;

  const DictationButton({
    super.key,
    required this.onTextRecognized,
  });

  @override
  ConsumerState<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends ConsumerState<DictationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Pulse animation for recording state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize speech service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(speechServiceProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleDictation() async {
    final notifier = ref.read(speechServiceProvider.notifier);
    final state = ref.read(speechServiceProvider);

    if (state.isListening) {
      await notifier.stopListening();
    } else {
      await notifier.startListening(
        onResult: widget.onTextRecognized,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final speechState = ref.watch(speechServiceProvider);

    return GestureDetector(
      onTap: speechState.isInitialized ? _toggleDictation : null,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: speechState.isListening ? _pulseAnimation.value : 1.0,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: speechState.isListening
                    ? CatppuccinMocha.red
                    : CatppuccinMocha.surface0,
                shape: BoxShape.circle,
                border: Border.all(
                  color: speechState.isListening
                      ? CatppuccinMocha.red
                      : CatppuccinMocha.surface1,
                  width: 1,
                ),
              ),
              child: speechState.isInitialized
                  ? Icon(
                      Icons.mic,
                      color: speechState.isListening
                          ? CatppuccinMocha.crust
                          : CatppuccinMocha.text,
                      size: 20,
                    )
                  : SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          CatppuccinMocha.overlay1,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Dictation status overlay when recording
///
/// Shows recognized text in real-time
class DictationOverlay extends StatelessWidget {
  final String recognizedText;
  final VoidCallback onStop;
  final VoidCallback onSend;

  const DictationOverlay({
    super.key,
    required this.recognizedText,
    required this.onStop,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        border: Border(
          top: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: CatppuccinMocha.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Listening...',
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onStop,
                child: Text(
                  'Stop',
                  style: TextStyle(color: CatppuccinMocha.red),
                ),
              ),
            ],
          ),
          if (recognizedText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              recognizedText,
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onSend,
                  icon: Icon(Icons.send, size: 16, color: CatppuccinMocha.mauve),
                  label: Text(
                    'Send',
                    style: TextStyle(color: CatppuccinMocha.mauve),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
