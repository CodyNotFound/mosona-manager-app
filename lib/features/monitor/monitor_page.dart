import 'package:flutter/material.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key, required this.serverId});

  final int serverId;

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Monitor')),
      body: const Center(child: Text('TODO')),
    );
}
