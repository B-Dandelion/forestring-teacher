import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/forestring_theme.dart';
import 'auth_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.onManagerQaStart,
  });

  final VoidCallback? onManagerQaStart;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();

    await context.read<AuthController>().signIn(
          name: _nameController.text,
          pin: _pinController.text,
        );
  }

  InputDecoration _inputDecoration({
    required String label,
    required VoidCallback onClear,
  }) {
    return InputDecoration(
      counterText: '',
      filled: true,
      fillColor: Colors.white,
      labelText: label,
      labelStyle: const TextStyle(
        color: Colors.black,
        fontFamily: 'ELAND',
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(
          color: Colors.black,
          width: 1.2,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(
          color: Colors.black,
          width: 1.8,
        ),
      ),
      suffixIcon: IconButton(
        onPressed: onClear,
        icon: const Icon(Icons.close),
        color: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: primaryColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/img/포레스트링_선생님_로고.png',
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '포레스트링 선생님',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'ELAND',
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'ELAND',
                    ),
                    decoration: _inputDecoration(
                      label: '이름',
                      onClear: _nameController.clear,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onSubmitted: (_) => _login(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'ELAND',
                    ),
                    decoration: _inputDecoration(
                      label: '비밀번호',
                      onClear: _pinController.clear,
                    ),
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        auth.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'ELAND',
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _login,
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryColor,
                              ),
                            )
                          : const Text(
                              '로그인',
                              style: TextStyle(
                                color: primaryColor,
                                fontFamily: 'ELAND',
                                fontWeight: FontWeight.w500,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),
                  if (widget.onManagerQaStart != null) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: widget.onManagerQaStart,
                      icon: const Icon(
                        Icons.developer_mode_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: const Text(
                        'QA 지점장으로 시작',
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'ELAND',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
