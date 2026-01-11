import 'package:flutter/foundation.dart';

class DataRefreshBus {
  DataRefreshBus._();

  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static void notify() {
    notifier.value++;
  }
}
