import 'package:intl/intl.dart';

class ParsedReminder {
  final String task;
  final String? place;
  final DateTime when;
  final String sourceText;

  ParsedReminder({
    required this.task,
    this.place,
    required this.when,
    required this.sourceText,
  });
}

class ParserService {
  static const _weekdays = {
    'dushanba': DateTime.monday,
    'seshanba': DateTime.tuesday,
    'chorshanba': DateTime.wednesday,
    'payshanba': DateTime.thursday,
    'juma': DateTime.friday,
    'shanba': DateTime.saturday,
    'yakshanba': DateTime.sunday,
  };

  // Pronoun/suffix false-positives that end with -ga/-ka/-qa/-da
  static const _excludedPlaceWords = {
    'boshqa', 'nega', 'menga', 'senga', 'unga', 'bizga', 'sizga', 'ularga',
    'shunga', 'bunga', 'qayerga', 'qachonda', 'nechada', 'shunda', 'bunda',
    'beriga', 'nariga', 'endi', 'qancha', 'muncha', 'shuncha', 'buncha',
    'yana', 'hamma', 'barcha', 'yil', 'oy', 'daqiqa', 'hafta', 'dona',
  };

  ParsedReminder parse(String text, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final dayBase = DateTime(n.year, n.month, n.day);
    final lower = text.toLowerCase();

    // ---------- Day ----------
    var day = dayBase;
    if (lower.contains('ertaga')) {
      day = dayBase.add(const Duration(days: 1));
    } else if (lower.contains('indin')) {
      day = dayBase.add(const Duration(days: 2));
    } else {
      for (final e in _weekdays.entries) {
        if (lower.contains(e.key)) {
          var diff = (e.value - dayBase.weekday) % 7;
          if (diff == 0) diff = 7;
          day = dayBase.add(Duration(days: diff));
          break;
        }
      }
    }

    // ---------- Time ----------
    var hour = -1;
    var minute = 0;

    // "yarim kechada" -> 00:00
    if (lower.contains('yarim kecha')) {
      hour = 0;
      minute = 0;
    }

    // "soat 9:30" / "9:30"
    var m = RegExp(r'(?:soat\s*)?(\d{1,2})\s*[:.]\s*(\d{2})').firstMatch(lower);
    if (m != null) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2)!);
    } else if (hour < 0) {
      // "yarim 6" -> 5:30 ; "chorak 6" -> 5:15
      m = RegExp(r'(yarim|chorak)\s+(\d{1,2})').firstMatch(lower);
      if (m != null) {
        final base = int.parse(m.group(2)!);
        if (m.group(1) == 'yarim') {
          hour = base - 1;
          minute = 30;
        } else {
          hour = base - 1;
          minute = 15;
        }
      } else {
        // "soat 6 yarim" -> 6:30 ; "soat 9 da" -> 9:00
        m = RegExp(r'soat\s*(\d{1,2})\s*(yarim|chorak)?').firstMatch(lower);
        if (m != null) {
          hour = int.parse(m.group(1)!);
          final mod = m.group(2);
          if (mod == 'yarim') {
            minute = 30;
          } else if (mod == 'chorak') {
            minute = 15;
          }
        } else {
          // bare "9 da"
          m = RegExp(r'\b(\d{1,2})\s*da\b').firstMatch(lower);
          if (m != null) {
            final h = int.parse(m.group(1)!);
            if (h >= 1 && h <= 24) hour = h;
          }
        }
      }
    }

    // ---------- Period ----------
    String? period;
    if (lower.contains('kechqurun') ||
        lower.contains('kechki') ||
        lower.contains('kechga') ||
        lower.contains('oqshom')) {
      period = 'kechki';
    } else if (lower.contains('tushda') ||
        lower.contains('tushlik') ||
        lower.contains('kunduzi') ||
        lower.contains('peshin')) {
      period = 'tushda';
    } else if (lower.contains('ertalab') || lower.contains('tongda')) {
      period = 'ertalab';
    } else if (lower.contains('kechasi') || lower.contains('tunda')) {
      period = 'tunda';
    }

    if (hour < 0) {
      switch (period) {
        case 'ertalab':
          hour = 8;
        case 'tushda':
          hour = 13;
        case 'kechki':
          hour = 18;
        case 'tunda':
          hour = 22;
        default:
          hour = 9;
      }
      minute = 0;
    } else {
      if (period == 'kechki' && hour >= 1 && hour < 12) hour += 12;
      if (period == 'tushda' && hour >= 1 && hour < 8) hour += 12;
      if (period == 'ertalab' && hour > 12) hour -= 12;
    }

    if (hour >= 24) hour = hour % 24;

    final when = DateTime(day.year, day.month, day.day, hour, minute);
    DateTime fixed;
    if (when.isBefore(n) && !lower.contains('bugun')) {
      fixed = when.add(const Duration(days: 1));
    } else {
      fixed = when;
    }

    // ---------- Place & task ----------
    final words = lower
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();

    final dayWords = {'bugun', 'bugungi', 'ertaga', 'indin', 'indinga', 'kuni', 'kunda', 'ertalabki'};
    for (final e in _weekdays.keys) {
      dayWords.add(e);
    }

    String? place;
    final remaining = <String>[];
    for (var w in words) {
      if (w.contains('soat')) continue;
      if (RegExp(r'^\d+$').hasMatch(w)) continue;
      if (w.contains(':')) continue;
      if (dayWords.contains(w)) continue;
      if (_periodWords.contains(w)) continue;
      if (w == 'da' || w == 'dan' || w == 'ga' || w == 'ka' || w == 'qa') continue;
      if (_excludedPlaceWords.contains(w)) continue;

      var p = w;
      var suffix = '';
      if (p.endsWith('ga')) {
        suffix = 'ga';
        p = p.substring(0, p.length - 2);
      } else if (p.endsWith('ka')) {
        suffix = 'ka';
        p = p.substring(0, p.length - 2);
      } else if (p.endsWith('qa')) {
        suffix = 'qa';
        p = p.substring(0, p.length - 2);
      } else if (p.endsWith('da')) {
        suffix = 'da';
        p = p.substring(0, p.length - 2);
      }

      if (suffix.isNotEmpty && p.isNotEmpty && !_excludedPlaceWords.contains(p)) {
        place ??= p;
      } else {
        remaining.add(w);
      }
    }

    var task = remaining.join(' ');
    if (place != null) {
      final placeWithSuffix = '${place}ga';
      task = task.isEmpty ? 'Boring $placeWithSuffix' : '$placeWithSuffix $task';
    }
    if (task.trim().isEmpty) task = 'Eslatma';

    return ParsedReminder(task: task.trim(), place: place, when: fixed, sourceText: text);
  }

  static const _periodWords = {
    'ertalab', 'tongda', 'tong', 'tushda', 'tushlik', 'kunduzi', 'peshin',
    'kechqurun', 'kechki', 'kechga', 'oqshom', 'kechasi', 'tunda',
    'yarim', 'chorak',
  };

  static String formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final day = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    String dayLabel;
    if (day == today) {
      dayLabel = 'Bugun';
    } else if (day == today.add(const Duration(days: 1))) {
      dayLabel = 'Ertaga';
    } else {
      const names = [
        '', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'
      ];
      dayLabel = names[dt.weekday];
      if (dt.year != now.year || dt.month != now.month) {
        dayLabel = DateFormat('d MMMM', 'uz_UZ').format(dt);
      }
    }
    final time = DateFormat('HH:mm').format(dt);
    return '$dayLabel, soat $time';
  }
}
