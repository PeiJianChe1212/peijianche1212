import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/echo_comment_task.dart';

class EchoCommentTaskStorageService {
  static const String _fileName = 'echo_comment_tasks.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<EchoCommentTask>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final tasks = decoded
          .whereType<Map>()
          .map(EchoCommentTask.fromJson)
          .where(
            (item) =>
                item.id.isNotEmpty &&
                item.echoId.isNotEmpty &&
                item.echoOwnerId.isNotEmpty &&
                item.commenterId.isNotEmpty,
          )
          .toList();
      tasks.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return tasks;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<EchoCommentTask> tasks) async {
    final file = await _file();
    final mutable = [...tasks]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    await file.writeAsString(
      jsonEncode(mutable.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> addAll(List<EchoCommentTask> additions) async {
    if (additions.isEmpty) return;
    final tasks = await loadAll();
    final ids = tasks.map((item) => item.id).toSet();
    var changed = false;
    for (final task in additions) {
      if (ids.add(task.id)) {
        tasks.add(task);
        changed = true;
      }
    }
    if (changed) await saveAll(tasks);
  }

  Future<void> update(EchoCommentTask task) async {
    final tasks = await loadAll();
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await saveAll(tasks);
  }

  Future<bool> hasTaskForEcho(String echoId) async {
    final tasks = await loadAll();
    return tasks.any((item) => item.echoId == echoId);
  }

  Future<void> deleteForEcho(String echoId) async {
    final tasks = await loadAll();
    await saveAll(tasks.where((item) => item.echoId != echoId).toList());
  }

  Future<void> prune({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final cutoff = time.subtract(const Duration(days: 30));
    final tasks = await loadAll();
    final next = tasks.where((item) {
      if (item.status == EchoCommentTaskStatus.pending) return true;
      return (item.publishedAt ?? item.createdAt).isAfter(cutoff);
    }).toList();
    if (next.length != tasks.length) await saveAll(next);
  }
}
