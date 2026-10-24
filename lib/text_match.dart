// One rule for comparing names everywhere in the app, so "PRINCESS",
// "princess", "  Princess   Uwase " and "Clémentine"/"clementine" all
// match the way a person would expect.

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// Lower case, accents removed, apostrophes/hyphens/dots treated as
/// spaces, runs of spaces collapsed. "  Jean-Paul  O'NEIL " -> "jean paul o neil".
String foldText(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_accents[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r"['’`.\-_,]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when every word typed appears in the name, in any order and as
/// the start of a word: "princess", "PRIN", "uwase princess" all match
/// "Princess Uwase"; "cess" doesn't (too loose to be useful).
bool nameMatches(String name, String query) {
  final words = foldText(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final nameWords = foldText(name).split(' ');
  return words.every((w) => nameWords.any((n) => n.startsWith(w)));
}

/// True when two names are the same person's name, ignoring capitals,
/// accents, spacing and punctuation.
bool sameName(String a, String b) => foldText(a) == foldText(b);
