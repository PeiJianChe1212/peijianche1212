import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/echo_comment_reply_task.dart';

class EchoCommentReplyTaskStorageService {
  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/echo_comment_reply_tasks.json');
  }

  Future<List<EchoCommentReplyTask>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(EchoCommentReplyTask.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(EchoCommentReplyTask task) async {
    final items = await loadAll();
    if (items.any((item) =>
        item.id == task.id || item.parentCommentId == task.parentCommentId)) {
      return;
    }
    items.add(task);
    await _save(items);
  }

  Future<void> update(EchoCommentReplyTask task) async {
    final items = await loadAll();
    final index = items.indexWhere((item) => item.id == task.id);
    if (index < 0) {
      items.add(task);
    } else {
      items[index] = task;
    }
    await _save(items);
  }

  Future<void> removeForEcho(String echoId) async {
    final items = await loadAll();
    items.removeWhere((item) => item.echoId == echoId);
    await _save(items);
  }

  Future<void> prune({DateTime? now}) async {
    final cutoff =
        (now ?? DateTime.now()).subtract(const Duration(days: 14));
    final items = await loadAll();
    items.removeWhere((item) =>
        item.status != EchoCommentReplyTaskStatus.pending &&
        item.createdAt.isBefore(cutoff));
    await _save(items);
  }

  Future<void> _save(List<EchoCommentReplyTask> items) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }
}
