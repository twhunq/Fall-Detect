import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

/// Ứng dụng gốc: theme sáng/tối theo hệ thống, chọn đăng nhập hoặc màn hình chính.
class BaoNgaApp extends StatefulWidget {
  const BaoNgaApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<BaoNgaApp> createState() => _BaoNgaAppState();
}

class _BaoNgaAppState extends State<BaoNgaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: widget.controller,
      child: MaterialApp(
        title: 'Báo Ngã IoT',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: Consumer<AppController>(
          builder: (context, c, _) => c.needsLogin ? const LoginScreen() : const HomeShell(),
        ),
      ),
    );
  }
}
