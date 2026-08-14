import 'package:flutter_test/flutter_test.dart';

import 'package:yordamchi/services/parser_service.dart';

void main() {
  final parser = ParserService();

  test('bugun soat 9 da ishga boraman', () {
    final now = DateTime(2026, 8, 13, 12, 0);
    final p = parser.parse('bugun soat 9 da ishga boraman', now: now);
    expect(p.when, DateTime(2026, 8, 13, 9, 0));
    expect(p.task, 'ishga boraman');
    expect(p.place, 'ish');
  });

  test('ertaga kechki soat 18:30 da shifokorga boraman', () {
    final now = DateTime(2026, 8, 13, 12, 0);
    final p = parser.parse('ertaga kechki soat 18:30 da shifokorga boraman', now: now);
    expect(p.when, DateTime(2026, 8, 14, 18, 30));
    expect(p.task, contains('shifokorga'));
  });

  test('dushanba kuni soat 10 da maktabga boraman', () {
    final now = DateTime(2026, 8, 13, 12, 0); // Thursday
    final p = parser.parse('dushanba kuni soat 10 da maktabga boraman', now: now);
    expect(p.when.weekday, DateTime.monday);
    expect(p.when.hour, 10);
  });

  test('kechki soat 7 da sport zalga boraman -> 19:00', () {
    final now = DateTime(2026, 8, 13, 12, 0);
    final p = parser.parse('kechki soat 7 da sport zalga boraman', now: now);
    expect(p.when.hour, 19);
    expect(p.place, 'zal');
  });

  test('ertaga tushda uchrashuvim bor -> 13:00 default', () {
    final now = DateTime(2026, 8, 13, 12, 0);
    final p = parser.parse('ertaga tushda uchrashuvim bor', now: now);
    expect(p.when, DateTime(2026, 8, 14, 13, 0));
  });
}
