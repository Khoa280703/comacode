import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../core/theme.dart';

/// Search result match
class SearchMatch {
  final int index;
  final String match;
  final int start;
  final int end;

  SearchMatch({
    required this.index,
    required this.match,
    required this.start,
    required this.end,
  });
}

/// Search results state
class SearchResults {
  final List<SearchMatch> matches;
  final int currentIndex;

  const SearchResults({
    this.matches = const [],
    this.currentIndex = -1,
  });

  SearchResults copyWith({
    List<SearchMatch>? matches,
    int? currentIndex,
  }) {
    return SearchResults(
      matches: matches ?? this.matches,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  int get count => matches.length;
  bool get hasResults => matches.isNotEmpty;
  SearchMatch? get currentMatch =>
      currentIndex >= 0 && currentIndex < matches.length
          ? matches[currentIndex]
          : null;

  SearchResults next() {
    if (matches.isEmpty) return this;
    final nextIndex = (currentIndex + 1) % matches.length;
    return copyWith(currentIndex: nextIndex);
  }

  SearchResults previous() {
    if (matches.isEmpty) return this;
    final prevIndex = currentIndex <= 0 ? matches.length - 1 : currentIndex - 1;
    return copyWith(currentIndex: prevIndex);
  }
}

/// Search overlay for terminal output
class OutputSearchOverlay extends StatefulWidget {
  final String output;
  final Terminal? terminal;
  final VoidCallback? onClose;

  const OutputSearchOverlay({
    super.key,
    required this.output,
    this.terminal,
    this.onClose,
  });

  @override
  State<OutputSearchOverlay> createState() => _OutputSearchOverlayState();
}

class _OutputSearchOverlayState extends State<OutputSearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  SearchResults _results = const SearchResults();
  bool _caseSensitive = false;
  bool _searching = false;

  // Debounce timer for search
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    setState(() {
      _searching = true;
    });

    final query = _controller.text;
    if (query.isEmpty) {
      setState(() {
        _results = const SearchResults();
        _searching = false;
      });
      _clearTerminalHighlight();
      return;
    }

    // Find matches
    final matches = <SearchMatch>[];
    final pattern = _caseSensitive ? query : query.toLowerCase();
    final searchContent = _caseSensitive
        ? widget.output
        : widget.output.toLowerCase();

    int index = 0;
    int pos = 0;

    while (true) {
      final start = searchContent.indexOf(pattern, pos);
      if (start == -1) break;

      final end = start + query.length;
      matches.add(SearchMatch(
        index: index++,
        match: widget.output.substring(start, end),
        start: start,
        end: end,
      ));
      pos = end;
    }

    setState(() {
      _results = SearchResults(matches: matches);
      if (matches.isNotEmpty) {
        _results = _results.copyWith(currentIndex: 0);
      }
      _searching = false;
    });

    // Highlight first match in terminal
    if (matches.isNotEmpty && widget.terminal != null) {
      _highlightInTerminal(matches.first);
    }
  }

  void _highlightInTerminal(SearchMatch match) {
    final terminal = widget.terminal;
    if (terminal == null) return;

    // xterm.dart doesn't have a search method in current version
    // TODO: Implement custom highlighting when terminal buffer is accessible
  }

  void _clearTerminalHighlight() {
    // Terminal doesn't have clearSearchHighlight method
    // Search results are cleared when new search is performed
  }

  void _nextMatch() {
    setState(() {
      _results = _results.next();
      if (_results.currentMatch != null) {
        _highlightInTerminal(_results.currentMatch!);
      }
    });
  }

  void _previousMatch() {
    setState(() {
      _results = _results.previous();
      if (_results.currentMatch != null) {
        _highlightInTerminal(_results.currentMatch!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CatppuccinMocha.mantle,
        border: Border(
          bottom: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.search, color: CatppuccinMocha.subtext0, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: TextStyle(color: CatppuccinMocha.text),
                      decoration: InputDecoration(
                        hintText: 'Search in output...',
                        hintStyle: TextStyle(color: CatppuccinMocha.overlay1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: CatppuccinMocha.surface1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: CatppuccinMocha.surface1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: CatppuccinMocha.mauve),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear,
                                    color: CatppuccinMocha.overlay1),
                                onPressed: () {
                                  _controller.clear();
                                  _performSearch();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _performSearch(),
                      onChanged: (value) {
                        // Debounced search for better performance
                        _debounce?.cancel();
                        if (value.isEmpty) {
                          _results = const SearchResults();
                          _clearTerminalHighlight();
                          setState(() {});
                        } else {
                          _debounce = Timer(const Duration(milliseconds: 300), () {
                            _performSearch();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Case sensitive toggle
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _caseSensitive = !_caseSensitive;
                        if (_controller.text.isNotEmpty) {
                          _performSearch();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _caseSensitive
                            ? CatppuccinMocha.mauve
                            : CatppuccinMocha.surface0,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _caseSensitive
                              ? CatppuccinMocha.mauve
                              : CatppuccinMocha.surface1,
                        ),
                      ),
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: _caseSensitive
                              ? CatppuccinMocha.crust
                              : CatppuccinMocha.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: CatppuccinMocha.text),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),

            // Results info and navigation
            if (_searching || _results.hasResults || _controller.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    if (_searching)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(CatppuccinMocha.yellow),
                        ),
                      )
                    else if (_results.hasResults)
                      Text(
                        '${_results.currentIndex + 1} of ${_results.count}',
                        style: TextStyle(
                          color: CatppuccinMocha.subtext0,
                          fontSize: 13,
                        ),
                      )
                    else if (_controller.text.isNotEmpty)
                      Text(
                        'No results',
                        style: TextStyle(
                          color: CatppuccinMocha.red,
                          fontSize: 13,
                        ),
                      ),
                    const Spacer(),
                    if (_results.hasResults && _results.count > 1) ...[
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_up,
                          color: CatppuccinMocha.text,
                        ),
                        onPressed: _previousMatch,
                        tooltip: 'Previous',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: CatppuccinMocha.text,
                        ),
                        onPressed: _nextMatch,
                        tooltip: 'Next',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
