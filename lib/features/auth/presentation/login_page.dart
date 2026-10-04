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
  final _nameFocusNode = FocusNode();
  final _pinFocusNode = FocusNode();

  bool _obscurePin = true;

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _nameFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();

    await context.read<AuthController>().signIn(
          name: _nameController.text,
          pin: _pinController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LoginTextField(
                            controller: _nameController,
                            focusNode: _nameFocusNode,
                            labelText: '이름',
                            hintText: '이름을 입력하세요',
                            prefixIcon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                _pinFocusNode.requestFocus(),
                            suffixIcon:
                                ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _nameController,
                              builder: (context, value, _) {
                                if (value.text.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return IconButton(
                                  tooltip: '이름 지우기',
                                  onPressed: _nameController.clear,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          _LoginTextField(
                            controller: _pinController,
                            focusNode: _pinFocusNode,
                            labelText: 'PIN',
                            hintText: '4자리 숫자',
                            prefixIcon: Icons.lock_outline_rounded,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            obscureText: _obscurePin,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onSubmitted: (_) {
                              if (!auth.isLoading) {
                                _login();
                              }
                            },
                            suffixIcon: IconButton(
                              tooltip: _obscurePin
                                  ? 'PIN 보기'
                                  : 'PIN 숨기기',
                              onPressed: () {
                                setState(() {
                                  _obscurePin = !_obscurePin;
                                });
                              },
                              icon: Icon(
                                _obscurePin
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 21,
                              ),
                            ),
                          ),
                          if (auth.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              auth.errorMessage!,
                              style: forestringTextStyle.copyWith(
                                color: Colors.redAccent,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed:
                                  auth.isLoading ? null : _login,
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    primaryColor.withValues(alpha: 0.55),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              child: auth.isLoading
                                  ? const SizedBox(
                                      width: 21,
                                      height: 21,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      '로그인',
                                      style:
                                          forestringTextStyle.copyWith(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                          ),
                          if (widget.onManagerQaStart != null) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: TextButton.icon(
                                onPressed: widget.onManagerQaStart,
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      primaryColor.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.developer_mode_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  'QA 지점장으로 시작',
                                  style:
                                      forestringTextStyle.copyWith(
                                    color: primaryColor.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    required this.textInputAction,
    required this.onSubmitted,
    required this.suffixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.maxLength,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;
  final TextInputAction textInputAction;
  final ValueChanged<String> onSubmitted;
  final Widget suffixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      enableSuggestions: false,
      autocorrect: false,
      onSubmitted: onSubmitted,
      style: forestringTextStyle.copyWith(
        color: Colors.black87,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: obscureText ? 1.5 : 0,
      ),
      cursorColor: primaryColor,
      decoration: InputDecoration(
        counterText: '',
        labelText: labelText,
        hintText: hintText,
        labelStyle: forestringTextStyle.copyWith(
          color: Colors.black54,
          fontSize: 14,
        ),
        hintStyle: forestringTextStyle.copyWith(
          color: Colors.black38,
          fontSize: 14,
          fontWeight: FontWeight.w300,
          letterSpacing: 0,
        ),
        prefixIcon: Icon(
          prefixIcon,
          size: 21,
          color: primaryColor,
        ),
        suffixIcon: suffixIcon,
        suffixIconColor: Colors.black45,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.black.withValues(alpha: 0.16),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: primaryColor,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
