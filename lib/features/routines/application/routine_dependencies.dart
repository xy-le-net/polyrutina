import 'package:polyrutina/core/data/journal_layer.dart';

typedef RoutineFieldContext = ({int? activeFieldId, int? rootId});
typedef RoutineFieldContextReader = RoutineFieldContext Function();
typedef RoutineFieldNameReader = String? Function(int fieldId);
typedef RoutineTraceCopier =
    Future<void> Function(
      JournalLayer journal,
      int sourceId,
      int targetId,
      List<String> slots,
    );
