/// Validated mapping between model token ids and the exact token strings in
/// `tokens.txt`. This keeps display labels separate from any Unicode parsing.
class TokenTable {
  factory TokenTable.fromLines(Iterable<String> lines, {int expectedBlankId = 250}) {
    final Map<int, String> byId = <int, String>{};
    for (final String rawLine in lines) {
      final String line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final int separator = line.lastIndexOf(RegExp(r'\s'));
      if (separator <= 0 || separator == line.length - 1) {
        throw FormatException('Invalid token line: "$line"');
      }
      final String token = line.substring(0, separator).trim();
      final int? id = int.tryParse(line.substring(separator).trim());
      if (token.isEmpty || id == null || id < 0) {
        throw FormatException('Invalid token/id pair: "$line"');
      }
      if (byId.containsKey(id)) {
        throw FormatException('Duplicate token id $id.');
      }
      byId[id] = token;
    }
    if (byId.isEmpty) throw const FormatException('tokens.txt is empty.');
    final int maxId = byId.keys.reduce((int a, int b) => a > b ? a : b);
    if (byId.length != maxId + 1) {
      throw FormatException('Token ids are not contiguous: count ${byId.length}, max $maxId.');
    }
    if (expectedBlankId < 0 || expectedBlankId >= byId.length) {
      throw FormatException('Blank id $expectedBlankId is outside the token table.');
    }
    final List<String> ordered = List<String>.filled(byId.length, '');
    byId.forEach((int id, String token) => ordered[id] = token);
    final Map<String, List<int>> reverse = <String, List<int>>{};
    for (int id = 0; id < ordered.length; id++) {
      (reverse[ordered[id]] ??= <int>[]).add(id);
    }
    return TokenTable._withReverse(
      List<String>.unmodifiable(ordered),
      expectedBlankId,
      reverse,
    );
  }

  TokenTable._withReverse(this.tokens, this.blankId, Map<String, List<int>> reverse)
      : tokenToIds = Map<String, List<int>>.unmodifiable(
          reverse.map((String key, List<int> value) =>
              MapEntry<String, List<int>>(key, List<int>.unmodifiable(value))),
        );

  final List<String> tokens;
  final int blankId;
  final Map<String, List<int>> tokenToIds;

  int get classCount => tokens.length;

  /// Tokenizes a canonical phoneme string using the longest exact vocabulary
  /// label at each position. CTC blank is never a target phoneme. A null result
  /// means the reference contains symbols that this vocabulary cannot encode;
  /// callers must then use an explicitly-labelled fallback instead of guessing.
  List<String>? tokenizeExpectedPhonemes(String phonemes) {
    final String input = phonemes.replaceAll(
      RegExp(r'[\s\u200B-\u200F\u202A-\u202E]'),
      '',
    );
    if (input.isEmpty) return const <String>[];

    // A greedy longest-prefix split can silently choose the wrong segmentation
    // when one token is a prefix of another. Dynamic programming counts valid
    // segmentations (capped at two); only a unique segmentation is accepted.
    final List<String> labels = <String>{
      for (int i = 0; i < tokens.length; i++)
        if (i != blankId && tokens[i].isNotEmpty) tokens[i],
    }.toList(growable: false);
    final List<int> ways = List<int>.filled(input.length + 1, 0);
    final List<String?> chosen = List<String?>.filled(input.length + 1, null);
    ways[input.length] = 1;

    for (int offset = input.length - 1; offset >= 0; offset--) {
      for (final String label in labels) {
        if (!input.startsWith(label, offset)) continue;
        final int end = offset + label.length;
        final int suffixWays = ways[end];
        if (suffixWays == 0) continue;
        if (ways[offset] == 0 && suffixWays == 1) {
          chosen[offset] = label;
        } else {
          chosen[offset] = null;
        }
        ways[offset] = (ways[offset] + suffixWays).clamp(0, 2).toInt();
      }
    }

    if (ways[0] != 1) return null;
    final List<String> result = <String>[];
    int offset = 0;
    while (offset < input.length) {
      final String? token = chosen[offset];
      if (token == null || token.isEmpty) return null;
      result.add(token);
      offset += token.length;
    }
    return List<String>.unmodifiable(result);
  }

  String labelFor(int id) {
    if (id < 0 || id >= tokens.length) return '<unknown:$id>';
    return tokens[id];
  }

  List<int> idsFor(String token) => tokenToIds[token] ?? const <int>[];

  bool get blankIsPlausiblyNamed {
    final String label = labelFor(blankId).toLowerCase();
    return label.contains('blk') || label.contains('blank') || label == '-';
  }
}
