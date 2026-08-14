import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/parser_service.dart';
import '../services/reminders_store.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'live_chat_screen.dart';

enum _Segment { bugun, ertaga, barchasi }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _parser = ParserService();
  final _textController = TextEditingController();
  final _announced = <String>{};

  bool _loading = true;
  _Segment _segment = _Segment.bugun;

  Timer? _ticker;

  List<Reminder> get _reminders => RemindersStore.instance.reminders;

  @override
  void initState() {
    super.initState();
    RemindersStore.instance.addListener(_onStoreChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    RemindersStore.instance.removeListener(_onStoreChanged);
    _ticker?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
    await TtsService.instance.init();
    await RemindersStore.instance.load();
    if (mounted) {
      setState(() => _loading = false);
    }
    _rescheduleAll();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _checkDue());
  }

  Future<void> _rescheduleAll() async {
    for (final r in _reminders) {
      if (!r.done && r.when.isAfter(DateTime.now())) {
        await NotificationService.instance.schedule(r);
      }
    }
  }

  void _checkDue() {
    final reminders = _reminders;
    if (reminders.isEmpty) return;
    final now = DateTime.now();
    for (final r in List.of(reminders)) {
      if (r.done || _announced.contains(r.id)) continue;
      final diff = r.when.difference(now).inSeconds;
      if (diff.abs() <= 60) {
        _announced.add(r.id);
        _speakAndNotify(r);
      }
    }
  }

  Future<void> _speakAndNotify(Reminder r) async {
    final time = DateFormat('HH:mm').format(r.when);
    final body = r.place != null
        ? 'Joy: ${r.place} — soat $time'
        : 'Soat $time';
    await NotificationService.instance.showNow('Eslatma: ${r.task}', body);
    await TtsService.instance.speak('Eslatma, ${r.task}!');
  }

  // ---------------- Parsing & saving ----------------

  Future<void> _processText(String raw) async {
    final parsed = _parser.parse(raw);
    if (mounted) await _showConfirmDialog(parsed);
  }

  Future<void> _showConfirmDialog(ParsedReminder parsed) async {
    final result = await showDialog<_ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConfirmDialog(parsed: parsed),
    );
    if (result == null || !mounted) return;

    final reminder = Reminder(
      id: '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}',
      task: result.task,
      place: result.place,
      when: result.when,
      createdAt: DateTime.now(),
      sourceText: result.sourceText,
      notes: result.notes,
    );

    await RemindersStore.instance.add(reminder);
    await NotificationService.instance.schedule(reminder);

    _showSnack(
        'Eslatma qo\'shildi: ${ParserService.formatDateTime(reminder.when)}');
  }

  Future<void> _addFromTextField() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await _processText(text);
  }

  Future<void> _openLiveChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LiveConversationScreen(
          onMessage: _onLiveMessage,
        ),
      ),
    );
  }

  void _onLiveMessage(String role, String text) {
    // Tirik suhbat tarixi chat ekranida saqlanadi; bu yerda kerak emas.
  }

  // ---------------- Reminder actions ----------------

  Future<void> _toggleDone(Reminder r) async {
    final done = !r.done;
    await RemindersStore.instance.setDone(r.id, done);
    if (done) {
      _announced.remove(r.id);
      await NotificationService.instance.cancel(r);
    } else {
      await NotificationService.instance.schedule(r.copyWith(done: false));
    }
  }

  Future<void> _deleteReminder(Reminder r) async {
    _announced.remove(r.id);
    await RemindersStore.instance.remove(r.id);
    await NotificationService.instance.cancel(r);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jarvis'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 6),
              child: Text(
                'Eslatmalar • AI • Siz bilan',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildInputCard(theme),
            const SizedBox(height: 12),
            _buildSegmentBar(theme),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _buildList(theme),
                  _buildJarvisStart(theme),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildJarvisStart(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openLiveChat,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'JARVIS',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              height: 1,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Bosing va gaplashing',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: AppColors.textSecondary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Eslatma yozing...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(fontSize: 16),
              onSubmitted: (_) => _addFromTextField(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onPressed: _addFromTextField,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final s in _Segment.values) ...[
            if (s != _Segment.values.first) const SizedBox(width: 4),
            Expanded(
              child: _SegmentButton(
                label: _segmentLabel(s),
                selected: _segment == s,
                onTap: () => setState(() => _segment = s),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _segmentLabel(_Segment s) {
    switch (s) {
      case _Segment.bugun:
        return 'Bugun';
      case _Segment.ertaga:
        return 'Ertaga';
      case _Segment.barchasi:
        return 'Barchasi';
    }
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final t1 = t0.add(const Duration(days: 1));

    final filtered = <Reminder>[];
    for (final r in _reminders) {
      switch (_segment) {
        case _Segment.bugun:
          if (r.when.isBefore(t0) || !r.when.isBefore(t1)) {
            continue;
          }
        case _Segment.ertaga:
          if (r.when.isBefore(t1) ||
              !r.when.isBefore(t1.add(const Duration(days: 1)))) {
            continue;
          }
        case _Segment.barchasi:
          break;
      }
      filtered.add(r);
    }
    filtered.sort((a, b) => a.when.compareTo(b.when));

    if (filtered.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text('Bu bo\'limda eslatmalar yo\'q'),
              const SizedBox(height: 4),
              Text(
                'Markazdagi JARVIS yozuvini bosing va gaplashing',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    // Kun bo'yicha guruhlash
    final groups = <DateTime, List<Reminder>>{};
    for (final r in filtered) {
      final d = DateTime(r.when.year, r.when.month, r.when.day);
      groups.putIfAbsent(d, () => []).add(r);
    }
    final days = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: days.length,
      itemBuilder: (ctx, i) {
        final day = days[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(theme, day, t0, t1),
            const SizedBox(height: 8),
            for (final r in groups[day]!) _buildReminderCard(r),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, DateTime day, DateTime t0,
      DateTime t1) {
    final String label;
    if (day == t0) {
      label = 'Bugun, ${DateFormat('d MMMM', 'uz_UZ').format(day)}';
    } else if (day == t1) {
      label = 'Ertaga, ${DateFormat('d MMMM', 'uz_UZ').format(day)}';
    } else {
      label = DateFormat('d MMMM', 'uz_UZ').format(day);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: theme.textTheme.titleSmall),
    );
  }

  Widget _buildReminderCard(Reminder r) {
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm').format(r.when);
    final overdue = r.when.isBefore(DateTime.now()) && !r.done;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: r.done ? AppColors.mint : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          Checkbox(
            value: r.done,
            shape: const CircleBorder(),
            activeColor: AppColors.primary,
            onChanged: (_) => _toggleDone(r),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.task,
                  style: theme.textTheme.titleSmall?.copyWith(
                    decoration:
                        r.done ? TextDecoration.lineThrough : null,
                    color: r.done ? AppColors.textSecondary : null,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$time${overdue ? ' (o\'tib ketdi)' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                if (r.place != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(r.place!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
                if (r.notes != null && r.notes!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(r.notes!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'O\'chirish',
            icon: const Icon(Icons.delete_outline,
                color: AppColors.error, size: 22),
            onPressed: () => _deleteReminder(r),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? const [AppShadows.card] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConfirmResult {
  final String task;
  final String? place;
  final DateTime when;
  final String sourceText;
  final String? notes;

  _ConfirmResult({
    required this.task,
    this.place,
    required this.when,
    required this.sourceText,
    this.notes,
  });
}

class _ConfirmDialog extends StatefulWidget {
  final ParsedReminder parsed;

  const _ConfirmDialog({required this.parsed});

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late final TextEditingController _taskController;
  late final TextEditingController _placeController;
  late final TextEditingController _notesController;
  late DateTime _when;
  late String _sourceText;

  @override
  void initState() {
    super.initState();
    _taskController = TextEditingController(text: widget.parsed.task);
    _placeController = TextEditingController(text: widget.parsed.place ?? '');
    _notesController = TextEditingController();
    _when = widget.parsed.when;
    _sourceText = widget.parsed.sourceText;
  }

  @override
  void dispose() {
    _taskController.dispose();
    _placeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _save() {
    final task = _taskController.text.trim();
    if (task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vazifa yozilishi shart')),
      );
      return;
    }
    final place = _placeController.text.trim();
    final notes = _notesController.text.trim();
    Navigator.of(context).pop(_ConfirmResult(
      task: task,
      place: place.isEmpty ? null : place,
      when: _when,
      sourceText: _sourceText,
      notes: notes.isEmpty ? null : notes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Eslatmani tasdiqlash'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ovozdan olingan ma\'lumotni tekshiring',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _taskController,
              decoration: const InputDecoration(labelText: 'Vazifa'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeController,
              decoration: const InputDecoration(
                labelText: 'Joy',
                hintText: 'Ixtiyoriy',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule, color: AppColors.primary),
              title: const Text('Vaqt'),
              subtitle: Text(ParserService.formatDateTime(_when)),
              trailing: TextButton(
                onPressed: _pickDateTime,
                child: const Text('Vaqtni o\'zgartirish'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Qo\'shimcha ma\'lumot',
                hintText: 'Masalan: 12:30 da qo\'ng\'iroq qilishim kerak...',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Eshitilgan: "$_sourceText"',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Bekor qilish'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Tasdiqlash'),
        ),
      ],
    );
  }
}
