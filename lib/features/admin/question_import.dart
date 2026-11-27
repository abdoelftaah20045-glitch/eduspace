import 'dart:convert';

/// One question read from an import file, before it is saved.
class ParsedQuestion {
  ParsedQuestion({
    required this.type,
    required this.body,
    required this.options,
    required this.correct,
    this.points = 1,
    this.explanation,
  });

  String type;
  String body;
  List<String> options;
  Set<int> correct;
  double points;
  String? explanation;

  /// Why this question cannot be saved, or null when it is fine.
  String? get problem {
    if (body.trim().isEmpty) return 'empty';
    if (type == 'essay') return null;
    if (options.length < 2 && type != 'fill_blank') return 'options';
    if (correct.isEmpty) return 'answer';
    return null;
  }

  List<Map<String, dynamic>> toOptionMaps() => [
        for (var i = 0; i < options.length; i++)
          {
            'body': options[i],
            'is_correct': correct.contains(i),
            'sort_order': i,
          },
      ];
}

const _kTypes = ['mcq', 'true_false', 'multi', 'fill_blank', 'essay'];

String _normType(String? t, int correctCount, List<String> options) {
  final v = (t ?? '').trim().toLowerCase().replaceAll(' ', '_');
  if (_kTypes.contains(v)) return v;
  if (v == 'tf' || v == 'truefalse' || v == 'true/false') return 'true_false';
  if (v == 'multiple' || v == 'multi_select') return 'multi';
  if (v == 'text' || v == 'written') return 'essay';
  if (options.length == 2 &&
      options.map((o) => o.toLowerCase()).toSet().containsAll(['true', 'false'])) {
    return 'true_false';
  }
  return correctCount > 1 ? 'multi' : 'mcq';
}

/// Turns an answer cell ("B", "2", "B,C", option text) into option indexes.
Set<int> _parseAnswer(dynamic a, List<String> options) {
  final out = <int>{};
  final items = a is List
      ? a
      : a.toString().split(RegExp(r'[,;|]')).map((e) => e.trim()).toList();
  for (final raw in items) {
    if (raw is int) {
      if (raw >= 1 && raw <= options.length) out.add(raw - 1);
      continue;
    }
    final t = raw.toString().trim();
    if (t.isEmpty) continue;
    final n = int.tryParse(t);
    if (n != null) {
      if (n >= 1 && n <= options.length) out.add(n - 1);
      continue;
    }
    if (t.length == 1) {
      final i = t.toUpperCase().codeUnitAt(0) - 65;
      if (i >= 0 && i < options.length) {
        out.add(i);
        continue;
      }
    }
    final idx = options.indexWhere((o) => o.trim().toLowerCase() == t.toLowerCase());
    if (idx >= 0) out.add(idx);
  }
  return out;
}

List<ParsedQuestion> parseQuestionsJson(String text) {
  final data = jsonDecode(text);
  final list = data is List ? data : (data is Map ? (data['questions'] as List? ?? const []) : const []);
  final out = <ParsedQuestion>[];
  for (final item in list) {
    if (item is! Map) continue;
    final body = (item['question'] ?? item['body'] ?? item['text'] ?? '').toString();
    final opts = <String>[];
    final correct = <int>{};
    final rawOpts = item['options'] ?? item['choices'] ?? const [];
    if (rawOpts is List) {
      for (var i = 0; i < rawOpts.length; i++) {
        final o = rawOpts[i];
        if (o is Map) {
          opts.add((o['body'] ?? o['text'] ?? '').toString());
          if (o['is_correct'] == true || o['correct'] == true) correct.add(i);
        } else {
          opts.add(o.toString());
        }
      }
    }
    final ans = item['answer'] ?? item['correct'] ?? item['answers'];
    if (ans != null) correct.addAll(_parseAnswer(ans, opts));
    out.add(ParsedQuestion(
      type: _normType(item['type']?.toString(), correct.length, opts),
      body: body,
      options: opts,
      correct: correct,
      points: (item['points'] as num?)?.toDouble() ?? 1,
      explanation: item['explanation']?.toString(),
    ));
  }
  return out;
}

List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final t = text.replaceFirst('\uFEFF', '');
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',' || c == ';' || c == '\t') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else if (c != '\r') {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

/// CSV columns: question, A, B, C, D (any number of options), answer,
/// points, type, explanation. Header row is matched by name.
List<ParsedQuestion> parseQuestionsCsv(String text) {
  final rows = _csvRows(text);
  if (rows.length < 2) return [];
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> names) => head.indexWhere(names.contains);
  final qi = col(['question', 'body', 'text', 'السؤال']);
  final ai = col(['answer', 'correct', 'الإجابة', 'الاجابة']);
  final pi = col(['points', 'score', 'الدرجة']);
  final ti = col(['type', 'النوع']);
  final ei = col(['explanation', 'الشرح']);
  final optCols = <int>[];
  for (var i = 0; i < head.length; i++) {
    final h = head[i];
    if (RegExp(r'^(option\s*\d+|choice\s*\d+|[a-h]|اختيار\s*\d+)$').hasMatch(h)) {
      optCols.add(i);
    }
  }
  if (qi < 0) return [];
  final out = <ParsedQuestion>[];
  for (final r in rows.skip(1)) {
    String at(int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
    final opts = [for (final i in optCols) if (at(i).isNotEmpty) at(i)];
    final correct = ai >= 0 ? _parseAnswer(at(ai), opts) : <int>{};
    out.add(ParsedQuestion(
      type: _normType(at(ti), correct.length, opts),
      body: at(qi),
      options: opts,
      correct: correct,
      points: double.tryParse(at(pi)) ?? 1,
      explanation: at(ei).isEmpty ? null : at(ei),
    ));
  }
  return out;
}

/// Plain text (paste from Word, save as .txt). Blocks split by a blank line:
///   1. Question text
///   A) option
///   B) option *        <- a trailing * marks the correct option
///   Answer: B          <- or an Answer line
List<ParsedQuestion> parseQuestionsText(String text) {
  final blocks = text
      .replaceAll('\r', '')
      .split(RegExp(r'\n\s*\n'))
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty);
  final out = <ParsedQuestion>[];
  final optRe = RegExp(r'^\(?([A-Ha-h]|\d{1,2})[\).:\-]\s+(.*)$');
  final ansRe = RegExp(r'^(answer|ans|الإجابة|الاجابة)\s*[:：]\s*(.*)$',
      caseSensitive: false);
  for (final b in blocks) {
    final lines = b.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final qLines = <String>[];
    final opts = <String>[];
    final correct = <int>{};
    String? answer;
    for (final l in lines) {
      final am = ansRe.firstMatch(l);
      if (am != null) {
        answer = am.group(2);
        continue;
      }
      final om = optRe.firstMatch(l);
      if (om != null && qLines.isNotEmpty) {
        var o = om.group(2)!.trim();
        if (o.endsWith('*')) {
          o = o.substring(0, o.length - 1).trim();
          correct.add(opts.length);
        }
        opts.add(o);
      } else if (opts.isEmpty) {
        qLines.add(l.replaceFirst(RegExp(r'^\d+[\).:\-]\s*'), ''));
      }
    }
    if (answer != null) correct.addAll(_parseAnswer(answer, opts));
    out.add(ParsedQuestion(
      type: _normType(null, correct.length, opts),
      body: qLines.join(' '),
      options: opts,
      correct: correct,
    ));
  }
  return out;
}

List<ParsedQuestion> parseQuestionsFile(String name, String text) {
  final n = name.toLowerCase();
  final t = text.trimLeft();
  if (n.endsWith('.json') || t.startsWith('[') || t.startsWith('{')) {
    return parseQuestionsJson(text);
  }
  if (n.endsWith('.csv') || n.endsWith('.tsv')) return parseQuestionsCsv(text);
  return parseQuestionsText(text);
}

/// Public wrappers used by the bulk exam import.
Set<int> parseAnswerCells(dynamic a, List<String> options) =>
    _parseAnswer(a, options);
String normQuestionType(String? t, int correctCount, List<String> options) =>
    _normType(t, correctCount, options);
