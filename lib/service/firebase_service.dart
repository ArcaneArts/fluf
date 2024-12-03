/*
 * Copyright (c) 2024. Crucible Labs Inc.
 *
 * Crucible is a closed source project developed by Crucible Labs Inc.
 * Do not copy, share distribute or otherwise allow this source file
 * to leave hardware approved by Crucible Labs Inc. unless otherwise
 * approved by Crucible Labs Inc.
 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fire_api/fire_api.dart';
import 'package:fire_api_flutter/fire_api_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:serviced/serviced.dart';
import 'package:universal_io/io.dart';

class FirebaseService extends StatelessService implements AsyncStartupTasked {
  final FirebaseOptions options;

  FirebaseService({required this.options});

  @override
  Future<void> onStartupTask() async {
    await Firebase.initializeApp(
      options: options,
    );
    FirebaseFirestoreDatabase.create();
    FirestoreDatabase.instance
      ..debugPooling = kDebugMode
      ..debugLogging = true
      ..throwOnGet = false
      ..injectionTimeout = const Duration(seconds: 1)
      ..streamLoopbackInjection = false
      ..streamPooling = false;

    // Bug in windows busts cache
    if (!kIsWeb && Platform.isWindows) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );

      await clearFirestoreCache();
    }

    await Future.wait([_configureCrashlytics()]);
  }

  Future<void> clearFirestoreCache() async {
    try {
      await FirebaseFirestore.instance.clearPersistence();
      print("Firestore cache cleared successfully.");
    } catch (e) {
      print("Failed to clear Firestore cache: $e");
    }
  }

  Future<void> _configureCrashlytics() async {}
}
