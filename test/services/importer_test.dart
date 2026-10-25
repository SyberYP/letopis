import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/services/importer.dart';

void main() {
  test('diary export: date, title with category, body', () {
    const text = '27 Сентября 2026 Воскресенье 01:44\n'
        'Возвращаюсь (Мысли)\n'
        'Первая строка.\nВторая.\n'
        '-------------------------\n'
        '23 Сентября 2026 Среда 00:28\n'
        '(Любовь)\n'
        'Текст\n'
        '-------------------------\n';
    final p = parseImport(text);
    expect(p.format, 'diary');
    expect(p.entries.length, 2);
    final a = p.entries[0];
    expect(a.created, DateTime(2026, 9, 27, 1, 44));
    expect(a.title, 'Возвращаюсь');
    expect(a.tags, ['мысли']);
    expect(a.body, 'Первая строка.\nВторая.');
    expect(p.entries[1].title, '');
    expect(p.entries[1].tags, ['любовь']);
    expect(p.first, DateTime(2026, 9, 23, 0, 28));
  });

  test('mydiary export', () {
    const sep = '---------------------------------------------';
    final p = parseImport('2025/05/03 Сегодня хорошо.\n$sep\n2025/05/02 Вчера.\n$sep\n');
    expect(p.format, 'mydiary');
    expect(p.entries.map((e) => e.body), ['Сегодня хорошо.', 'Вчера.']);
    expect(p.entries.first.created, DateTime(2025, 5, 3, 12));
  });

  test('markdown file uses the date in its name', () {
    final p = parseImport('# Заметка\nтекст', fileName: '2024-03-08-1015-заметка.md');
    expect(p.format, 'markdown');
    expect(p.entries.single.created, DateTime(2024, 3, 8, 10, 15));
  });

  test('duplicate key is stable', () {
    final a = parseImport('1 Января 2020 Среда 10:00\nT (Мысли)\nb\n-------------------------\n');
    final b = parseImport('1 Января 2020 Среда 10:00\nT (Мысли)\nb\n-------------------------\n');
    expect(duplicateKey(a.entries.single), duplicateKey(b.entries.single));
  });

  // The author's real export, when present locally (never committed into the app).
  final real = File('../источники/дневник/allentries.txt');
  test('real export parses completely', () {
    final p = parseImport(real.readAsStringSync());
    expect(p.format, 'diary');
    expect(p.entries.length, greaterThan(1500));
    expect(p.entries.where((e) => e.tags.isEmpty), isEmpty);
    // ignore: avoid_print
    print('real export: ${p.entries.length} entries, ${p.first} – ${p.last}');
  }, skip: !real.existsSync());
}
