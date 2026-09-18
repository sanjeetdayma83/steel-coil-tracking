import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';

class SteelCoilTrackingApp extends StatelessWidget {
  const SteelCoilTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Steel Coil Tracking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.home,
      routes: {AppRoutes.home: (_) => const AppShell()},
    );
  }
}
