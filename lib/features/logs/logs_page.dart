import 'package:flutter/material.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, this.admin = false});

  final bool admin;

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Logs')),
      body: const Center(child: Text('TODO')),
    );
}
