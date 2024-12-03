import 'package:fast_log/fast_log.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:serviced/serviced.dart';
import 'package:synchronized/synchronized.dart';

Box get dataBox => svc<HiveService>()._data!;
LazyBox get cacheBox => svc<HiveService>()._cache!;

class HiveService extends StatelessService implements AsyncStartupTasked {
  final String prefix;

  HiveService({this.prefix = "fluf"});

  Box? _data;
  LazyBox? _cache;
  final Lock _lock = Lock();

  @override
  Future<void> onStartupTask() async {
    if (!kIsWeb) {
      Hive.initFlutter(prefix);
      info("Initialized Hive storage location");
    }

    await Future.wait([
      hive("data").then((value) => _data = value),
      hiveLazy("cache").then((value) => _cache = value),
    ]);

    success("Storage Initialized");
  }

  Future<Box> hive(String box) async {
    if (Hive.isBoxOpen("$prefix$box")) {
      return Hive.box("$prefix$box");
    }

    return Hive.openBox("$prefix$box").then((value) {
      info("Initialized Hive Box ${value.name} with ${value.keys.length} keys");
      return value;
    });
  }

  Future<LazyBox> hiveLazy(String box) => _lock.synchronized(() async {
        if (Hive.isBoxOpen("$prefix$box")) {
          return Hive.lazyBox("$prefix$box");
        }

        return Hive.openLazyBox("$prefix$box").then((value) {
          info(
              "Initialized Lazy Hive Box ${value.name} with ${value.keys.length} keys");
          return value;
        });
      });
}
