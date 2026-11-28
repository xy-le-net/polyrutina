class FieldShiftState {
  bool onShift = false;
  int totalShiftSeconds = 0;
  int? shiftStartedAt;
  bool shiftEdited = false;

  Map<String, dynamic> toJson() => {
    'on_shift': onShift,
    'total_shift_seconds': totalShiftSeconds,
    'shift_started_at': shiftStartedAt,
    'shift_edited': shiftEdited,
  };

  void loadJson(Map<String, dynamic> j) {
    onShift = j['on_shift'] as bool? ?? false;
    totalShiftSeconds = (j['total_shift_seconds'] as num?)?.toInt() ?? 0;
    shiftStartedAt = (j['shift_started_at'] as num?)?.toInt();
    shiftEdited = j['shift_edited'] as bool? ?? false;
  }
}
