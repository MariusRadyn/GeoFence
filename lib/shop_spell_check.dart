import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:simple_spell_checker/simple_spell_checker.dart';
import 'package:simple_spell_checker_en_lan/simple_spell_checker_en_lan.dart';

/// Spell-check helper for shop catalog text fields.
class ShopSpellIssue {
  final String field;
  final String word;
  final List<String> suggestions;

  const ShopSpellIssue({
    required this.field,
    required this.word,
    this.suggestions = const [],
  });
}

class _SpellToken {
  final String word;
  final bool isValid;

  const _SpellToken(this.word, this.isValid);
}

/// Text controller that underlines misspelled words while typing.
class ShopSpellCheckerController extends TextEditingController {
  ShopSpellCheckerController({
    super.text,
    SimpleSpellChecker? checker,
  }) : _checker = checker ?? ShopSpellCheck.checker;

  final SimpleSpellChecker _checker;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final valueText = text;
    if (valueText.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final composingRegionOutOfRange =
        !value.isComposingRangeValid || !withComposing;

    if (composingRegionOutOfRange) {
      return TextSpan(style: style, children: _checkedSpans(valueText, style));
    }

    final composingStyle =
        style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
            const TextStyle(decoration: TextDecoration.underline);
    return TextSpan(
      style: style,
      children: <TextSpan>[
        ..._checkedSpans(value.composing.textBefore(valueText), style),
        ..._checkedSpans(
          value.composing.textInside(valueText),
          composingStyle,
        ),
        ..._checkedSpans(value.composing.textAfter(valueText), style),
      ],
    );
  }

  List<TextSpan> _checkedSpans(String chunk, TextStyle? style) {
    if (chunk.isEmpty) return const [];
    final spans = _checker.check(
      chunk,
      commonStyle: style,
      wrongStyle: TextStyle(
        color: style?.color ?? Colors.white,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.wavy,
        decorationColor: Colors.redAccent,
        decorationThickness: 1.75,
      ),
    );
    if (spans == null || spans.isEmpty) {
      return [TextSpan(text: chunk, style: style)];
    }
    return spans;
  }
}

class ShopSpellCheck {
  ShopSpellCheck._();

  static bool _initialized = false;
  static final SimpleSpellChecker _checker = _createChecker();

  static SimpleSpellChecker get checker {
    ensureInitialized();
    return _checker;
  }

  static const Set<String> _ignoreWords = {
    'iot',
    'wifi',
    'bluetooth',
    'geofence',
    'shelly',
    'tasmota',
    'sonoff',
    'zar',
    'lcd',
    'mqtt',
    'lora',
    'limitless',
    'payfast',
    'sugarcane',
    'rechargeable',
    'keypad',
  };

  static const Map<String, String> _commonTypos = {
    'desined': 'designed',
    'autmatically': 'automatically',
    'recharable': 'rechargeable',
    'attandance': 'attendance',
    'instalation': 'installation',
    'buring': 'burning',
    'connectcs': 'connects',
    'comming': 'coming',
    'descritpion': 'description',
    'disount': 'discount',
    'availble': 'available',
    'moniter': 'monitor',
    'vehical': 'vehicle',
  };

  static void ensureInitialized() {
    if (_initialized) return;
    SimpleSpellCheckerEnRegister.registerLan();
    _initialized = true;
  }

  static SimpleSpellChecker _createChecker() {
    ensureInitialized();
    return SimpleSpellChecker(
      language: 'en',
      whiteList: _ignoreWords.toList(),
      caseSensitive: false,
    );
  }

  static Future<List<ShopSpellIssue>> checkFields({
    required String name,
    required String description,
    required String category,
  }) async {
    return [
      ..._issuesFromText('Item name', name),
      ..._issuesFromText('Description', description),
      ..._issuesFromText('Category', category),
    ];
  }

  static List<ShopSpellIssue> _issuesFromText(String field, String text) {
    if (text.trim().isEmpty) return [];

    final issues = <ShopSpellIssue>[];
    final seen = <String>{};

    final tokens = _checker.checkBuilder<_SpellToken>(
      text,
      builder: (word, isValid) => _SpellToken(word, isValid),
    );

    if (tokens != null) {
      for (final token in tokens) {
        if (token.isValid) continue;
        final word = token.word.trim();
        if (word.isEmpty || _shouldIgnore(word)) continue;
        final key = '${field.toLowerCase()}::${word.toLowerCase()}';
        if (seen.contains(key)) continue;
        seen.add(key);
        issues.add(
          ShopSpellIssue(
            field: field,
            word: word,
            suggestions: _suggestionsFor(word),
          ),
        );
      }
    }

    for (final issue in _fallbackCheck(field, text)) {
      final key = '${issue.field.toLowerCase()}::${issue.word.toLowerCase()}';
      if (seen.contains(key)) continue;
      seen.add(key);
      issues.add(issue);
    }

    return issues;
  }

  static List<String> _suggestionsFor(String word) {
    final mapped = _commonTypos[word.toLowerCase()];
    if (mapped != null) return [mapped];
    return const [];
  }

  static List<ShopSpellIssue> _fallbackCheck(String field, String text) {
    final issues = <ShopSpellIssue>[];
    for (final match in RegExp(r"[A-Za-z']{3,}").allMatches(text)) {
      final word = match.group(0)!;
      if (_shouldIgnore(word)) continue;
      final suggestion = _commonTypos[word.toLowerCase()];
      if (suggestion == null) continue;
      issues.add(
        ShopSpellIssue(
          field: field,
          word: word,
          suggestions: [suggestion],
        ),
      );
    }
    return issues;
  }

  static bool _shouldIgnore(String word) {
    final trimmed = word.trim();
    if (trimmed.length < 3) return true;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return true;
    if (trimmed == trimmed.toUpperCase() && trimmed.length <= 5) return true;
    if (_ignoreWords.contains(trimmed.toLowerCase())) return true;
    return false;
  }

  static Future<bool> confirmIfNeeded(
    BuildContext context,
    List<ShopSpellIssue> issues,
  ) async {
    if (issues.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorAppTitle,
        title: const Text(
          'Possible spelling issues',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Review these words before saving:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ...issues.map((issue) {
                final suggestionText = issue.suggestions.isEmpty
                    ? ''
                    : '\nTry: ${issue.suggestions.take(3).join(', ')}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${issue.field}: "${issue.word}"$suggestionText',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fix spelling'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );

    return result == true;
  }
}
