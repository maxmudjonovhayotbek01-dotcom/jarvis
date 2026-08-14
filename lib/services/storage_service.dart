import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/reminder.dart';

class StorageService {
  static const _fileName = 'reminders.json';
  List<Reminder> _cache = [];

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<Reminder>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.when.compareTo(b.when));
    } catch (_) {
      _cache = [];
    }
    return _cache;
  }

  Future<List<Reminder>> getReminders() async {
    if (_cache.isEmpty) return load();
    return _cache;
  }

  Future<void> save(List<Reminder> reminders) async {
    _cache = [...reminders]..sort((a, b) => a.when.compareTo(b.when));
    final f = await _file();
    await f.writeAsString(
      jsonEncode(_cache.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(Reminder reminder) async {
    final list = await getReminders();
    list.add(reminder);
    await save(list);
  }

  Future<void> remove(String id) async {
    final list = await getReminders();
    list.removeWhere((e) => e.id == id);
    await save(list);
  }

  Future<void> setDone(String id, bool done) async {
    final list = await getReminders();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(done: done);
      await save(list);
    }
  }
}
