import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';

void main() {
  test('only media attached to live routines or fields is retained', () {
    final layer = TraceLayer(_MemoryTraceRepository())
      ..traces[1] = Trace(
        id: 1,
        parents: [10],
        files: [
          TraceFile(
            kind: MediaKind.photo,
            path: p.join('app', 'media', 'deleted-routine.jpg'),
            name: 'deleted-routine.jpg',
          ),
        ],
      )
      ..traces[2] = Trace(
        id: 2,
        parents: [20],
        files: [
          TraceFile(
            kind: MediaKind.photo,
            path: p.join('app', 'media', 'live-routine.jpg'),
            name: 'live-routine.jpg',
          ),
        ],
      )
      ..traces[3] = Trace(
        id: 3,
        parents: [10],
        fieldParents: [30],
        files: [
          TraceFile(
            kind: MediaKind.photo,
            path: p.join('app', 'media', 'live-field.jpg'),
            name: 'live-field.jpg',
          ),
        ],
      )
      ..traces[4] = Trace(
        id: 4,
        parents: [20],
        deleted: true,
        files: [
          TraceFile(
            kind: MediaKind.photo,
            path: p.join('app', 'media', 'deleted-trace.jpg'),
            name: 'deleted-trace.jpg',
          ),
        ],
      );

    expect(layer.attachedMediaNames(parentIds: {20}, fieldIds: {30}), {
      'live-routine.jpg',
      'live-field.jpg',
    });
  });
}

class _MemoryTraceRepository implements TraceRepository {
  @override
  Future<TraceCache> load() async => const TraceCache.empty();

  @override
  Future<void> save({required List<Trace> traces}) async {}
}
