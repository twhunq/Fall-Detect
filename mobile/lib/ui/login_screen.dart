import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_auth_client.dart';
import '../state/app_controller.dart';
import 'theme.dart';

/// Đăng nhập Firebase (email/mật khẩu) hoặc chọn chế độ nội mạng.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Nhập email và mật khẩu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().signIn(_email.text, _password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Đăng nhập thất bại: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hotspot() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cài đặt qua Hotspot'),
        content: const Text(
            'Vòng đeo chưa có Wi-Fi sẽ phát mạng "BaoNga-Setup-XXXX".\n\n'
            '1. Vào Cài đặt Wi-Fi của điện thoại và kết nối mạng đó.\n'
            '2. Quay lại ứng dụng, bấm "Tiếp tục".\n\n'
            'Ứng dụng sẽ dùng địa chỉ http://192.168.4.1 và mở phần cài đặt Wi-Fi của vòng đeo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tiếp tục')),
        ],
      ),
    );
    if (go == true && mounted) {
      await context.read<AppController>().startHotspotSetup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    final colors = context.statusColors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.health_and_safety,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('Báo Ngã IoT',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Đăng nhập để xem và cài đặt từ xa',
                      textAlign: TextAlign.center, style: TextStyle(color: colors.muted)),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('loginEmail'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('loginPassword'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                    decoration: const InputDecoration(
                        labelText: 'Mật khẩu', border: OutlineInputBorder()),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: TextStyle(color: colors.bad)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Đăng nhập'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : c.enterLocalMode,
                    icon: const Icon(Icons.lan),
                    label: const Text('Chế độ nội mạng (không đăng nhập)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _hotspot,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Cài đặt qua Hotspot BaoNga-Setup-XXXX'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
