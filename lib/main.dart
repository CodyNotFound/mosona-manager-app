import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/state/controllers.dart';

/// Entry point for the Mosona Manager application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final cookies = CookieStore(prefs);
  await cookies.hydrate();
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        cookieStoreProvider.overrideWithValue(cookies),
      ],
      child: const MosonaManagerApp(),
    ),
  );
}
