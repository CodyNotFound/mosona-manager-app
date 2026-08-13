import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point for the Mosona Manager application.
///
/// The entire widget tree is wrapped in a [ProviderScope] so that Riverpod
/// providers are available throughout the app.
void main() {
  runApp(
    const ProviderScope(child: MosonaManagerApp()),
  );
}
