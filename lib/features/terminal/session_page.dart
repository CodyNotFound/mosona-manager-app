import 'package:flutter/material.dart';

class SessionPage extends StatelessWidget {
  const SessionPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Session')),
      body: const Center(child: Text('TODO', style: TextStyle(color: Colors.white))),
    );
}
