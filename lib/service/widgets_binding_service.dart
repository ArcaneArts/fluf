/*
 * Copyright (c) 2024. Crucible Labs Inc.
 *
 * Crucible is a closed source project developed by Crucible Labs Inc.
 * Do not copy, share distribute or otherwise allow this source file
 * to leave hardware approved by Crucible Labs Inc. unless otherwise
 * approved by Crucible Labs Inc.
 */

import 'package:flutter/cupertino.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:serviced/serviced.dart';

class WidgetsBindingService extends Service {
  late WidgetsBinding binding;

  @override
  void onStart() {
    binding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: binding);
  }

  void dropSplash() {
    FlutterNativeSplash.remove();
  }

  @override
  void onStop() {}
}
