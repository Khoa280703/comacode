import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/output_block.dart';
import 'output_parser.dart';

/// Parsed output view with enhanced rendering
class ParsedOutputView extends StatefulWidget {
  final String output;
  final VoidCallback? onFileTap;
  final Function(String)? onQuestionAnswer;

  const ParsedOutputView({
    super.key,
    required this.output,
    this.onFileTap,
    this.onQuestionAnswer,
  });

  @override
  State<ParsedOutputView> createState() => _ParsedOutputViewState();
}

class _ParsedOutputViewState extends State<ParsedOutputView> {
  final List<OutputBlock> _blocks = [];

  @override
  void initState() {
    super.initState();
    _blocks.addAll(OutputParser.parse(widget.output));
  }

  @override
  void didUpdateWidget(ParsedOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.output != widget.output) {
      _blocks.clear();
      _blocks.addAll(OutputParser.parse(widget.output));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        return _buildBlock(_blocks[index]);
      },
    );
  }

  Widget _buildBlock(OutputBlock block) {
    switch (block.type) {
      case BlockType.file:
        return _buildFileBlock(block);
      case BlockType.diff:
        return _buildDiffBlock(block);
      case BlockType.question:
        return _buildQuestionBlock(block);
      case BlockType.plan:
        return _buildPlanBlock(block);
      case BlockType.list:
        return _buildListBlock(block);
      case BlockType.error:
        return _buildErrorBlock(block);
      case BlockType.code:
        return _buildCodeBlock(block);
      case BlockType.tool:
        return _buildToolBlock(block);
      case BlockType.raw:
        return _buildRawBlock(block);
    }
  }

  Widget _buildFileBlock(OutputBlock block) {
    return GestureDetector(
      onTap: () {
        if (widget.onFileTap != null) {
          widget.onFileTap!();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: CatppuccinMocha.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: CatppuccinMocha.blue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file,
              size: 14,
              color: CatppuccinMocha.blue,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                block.content,
                style: TextStyle(
                  color: CatppuccinMocha.blue,
                  fontFamily: 'Courier',
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffBlock(OutputBlock block) {
    final color = block.isDiffAdded
        ? CatppuccinMocha.green
        : block.isDiffRemoved
            ? CatppuccinMocha.red
            : CatppuccinMocha.text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        block.content,
        style: TextStyle(
          color: color,
          fontFamily: 'Courier',
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildQuestionBlock(OutputBlock block) {
    final options = block.questionOptions ?? ['Y', 'n'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CatppuccinMocha.mauve.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CatppuccinMocha.mauve.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 16,
                color: CatppuccinMocha.mauve,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  block.content,
                  style: TextStyle(
                    color: CatppuccinMocha.text,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: options.map((opt) {
              return _QuestionButton(
                option: opt,
                onTap: () => widget.onQuestionAnswer?.call(opt),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanBlock(OutputBlock block) {
    return _CollapsibleBlock(
      block: block,
      header: Row(
        children: [
          Icon(
            block.isCollapsed
                ? Icons.expand_more
                : Icons.expand_less,
            size: 16,
            color: CatppuccinMocha.mauve,
          ),
          const SizedBox(width: 4),
          Text(
            block.content,
            style: TextStyle(
              color: CatppuccinMocha.mauve,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
      children: block.children?.map((b) => _buildBlock(b)).toList(),
    );
  }

  Widget _buildListBlock(OutputBlock block) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: TextStyle(
              color: CatppuccinMocha.overlay2,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              block.content.replaceFirst(RegExp(r'^[\-\*+]\s+'), ''),
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBlock(OutputBlock block) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: CatppuccinMocha.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: CatppuccinMocha.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              block.content,
              style: TextStyle(
                color: CatppuccinMocha.red,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(OutputBlock block) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        block.content,
        style: TextStyle(
          color: CatppuccinMocha.text,
          fontFamily: 'Courier',
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildToolBlock(OutputBlock block) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(CatppuccinMocha.yellow),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            block.content,
            style: TextStyle(
              color: CatppuccinMocha.yellow,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawBlock(OutputBlock block) {
    return Text(
      block.content,
      style: TextStyle(
        color: CatppuccinMocha.text,
        fontSize: 14,
      ),
    );
  }
}

/// Collapsible block widget
class _CollapsibleBlock extends StatefulWidget {
  final OutputBlock block;
  final Widget header;
  final List<Widget>? children;
  // ignore: unused_field
  final ValueChanged<bool>? onToggle;

  const _CollapsibleBlock({
    required this.block,
    required this.header,
    this.children,
    // ignore: unused_element_parameter
    this.onToggle,
  });

  @override
  State<_CollapsibleBlock> createState() => _CollapsibleBlockState();
}

class _CollapsibleBlockState extends State<_CollapsibleBlock> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.block.isCollapsed = !widget.block.isCollapsed;
          widget.onToggle?.call(widget.block.isCollapsed);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.header,
            if (!widget.block.isCollapsed && widget.children != null)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.children!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Question option button
class _QuestionButton extends StatelessWidget {
  final String option;
  final VoidCallback? onTap;

  const _QuestionButton({
    required this.option,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: CatppuccinMocha.mauve,
        foregroundColor: CatppuccinMocha.crust,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(40, 32),
      ),
      child: Text(option),
    );
  }
}
