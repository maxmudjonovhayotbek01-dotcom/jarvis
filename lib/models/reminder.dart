class Reminder {
  final String id;
  final String task;
  final String? place;
  final DateTime when;
  final DateTime createdAt;
  final bool done;
  final String sourceText;
  final String? notes;

  Reminder({
    required this.id,
    required this.task,
    this.place,
    required this.when,
    required this.createdAt,
    this.done = false,
    required this.sourceText,
    this.notes,
  });

  Reminder copyWith({
    String? id,
    String? task,
    String? place,
    DateTime? when,
    bool? done,
    String? notes,
  }) {
    return Reminder(
      id: id ?? this.id,
      task: task ?? this.task,
      place: place ?? this.place,
      when: when ?? this.when,
      createdAt: createdAt,
      done: done ?? this.done,
      sourceText: sourceText,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task': task,
        'place': place,
        'when': when.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'done': done,
        'sourceText': sourceText,
        'notes': notes,
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String,
        task: json['task'] as String,
        place: json['place'] as String?,
        when: DateTime.parse(json['when'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        done: json['done'] as bool? ?? false,
        sourceText: json['sourceText'] as String? ?? '',
        notes: json['notes'] as String?,
      );
}
