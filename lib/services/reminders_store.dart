import 'package:flutter/foundation.dart';

import '../models/reminder.dart';
import 'storage_service.dart';

class RemindersStore extends ChangeNotifier {
  static final RemindersStore instance = RemindersStore._();
  RemindersStore._();

  final StorageService _storage = StorageService();
  List<Reminder> _reminders = [];
  bool _loaded = false;

  List<Reminder> get reminders => List.unmodifiable(_reminders);
  bool get loaded => _loaded;

  Future<void> load() async {
    _reminders = await _storage.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Reminder r) async {
    _reminders.add(r);
    _reminders.sort((a, b) => a.when.compareTo(b.when));
    await _storage.save(_reminders);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _reminders.removeWhere((e) => e.id == id);
    await _storage.save(_reminders);
    notifyListeners();
  }

  Future<void> setDone(String id, bool done) async {
    final i = _reminders.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _reminders[i] = _reminders[i].copyWith(done: done);
    await _storage.save(_reminders);
    notifyListeners();
  }
}
