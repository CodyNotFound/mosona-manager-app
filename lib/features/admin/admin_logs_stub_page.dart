import 'package:flutter/material.dart';

import '../logs/logs_page.dart';

/// Admin logs reuse the team logs page with admin filters.
class AdminLogsPage extends StatelessWidget {
  const AdminLogsPage({super.key});

  @override
  Widget build(BuildContext context) => const LogsPage(admin: true);
}
