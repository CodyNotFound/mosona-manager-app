import 'package:flutter/material.dart';

class ServerFormPage extends StatelessWidget {
  const ServerFormPage({super.key, this.editServerId, this.copyFrom});

  final int? editServerId;
  final Map<String, dynamic>? copyFrom;

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: const Center(child: Text('TODO')),
    );
}
