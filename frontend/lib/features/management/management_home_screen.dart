import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ManagementHomeScreen extends StatelessWidget {
  const ManagementHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Správa')),
      body: ListView(
        children: [
          ListTile(title: const Text('Stavby a patra'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/jobs-admin')),
          ListTile(title: const Text('Exporty'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/reports')),
          ListTile(title: const Text('Logy'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/logs')),
        ],
      ),
    );
  }
}
