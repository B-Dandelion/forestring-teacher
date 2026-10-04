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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final compact = keyboardInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: primaryColor),
          ),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final topPadding = compact ? 10.0 : 18.0;
                  final bottomPadding =
                      compact ? keyboardInset + 10.0 : 22.0;
                  final availableHeight = constraints.maxHeight -
                      topPadding -
                      bottomPadding;

                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 230),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      topPadding,
                      22,
                      bottomPadding,
                    ),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              availableHeight > 0 ? availableHeight : 0,
                        ),
                        child: IntrinsicHeight(
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 430),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  if (!compact)
                                    const SizedBox(height: 72),
                                  Expanded(
                                    child: Center(
                                      child: _LoginBrand(
                                        compact: compact,
                                      ),
                                    ),
                                  ),
                                  if (compact)
                                    const SizedBox(height: 18),
                                  _LoginPanel(
                                    auth: auth,
                                    nameController: _nameController,
                                    pinController: _pinController,
                                    nameFocusNode: _nameFocusNode,
                                    pinFocusNode: _pinFocusNode,
                                    obscurePin: _obscurePin,
                                    onTogglePinVisibility: () {
                                      setState(() {
                                        _obscurePin = !_obscurePin;
                                      });
                                    },
                                    onLogin: _login,
                                  ),
                                  if (widget.onManagerQaStart != null) ...[
                                    SizedBox(
                                      height: compact ? 8 : 12,
                                    ),
                                    Center(
                                      child: TextButton.icon(
                                        onPressed:
                                            widget.onManagerQaStart,
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              Colors.white.withValues(
                                            alpha: 0.68,
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
                                            color:
                                                Colors.white.withValues(
                                              alpha: 0.68,
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
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({
    required this.compact,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 88 : 144,
            width: double.infinity,
            child: ClipRect(
              child: Transform.scale(
                scale: compact ? 1.56 : 2.05,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/img/포레스트링_선생님_로고.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 22),
          Text(
            '포레스트링 선생님',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white,
              fontSize: compact ? 23 : 31,
              fontWeight: FontWeight.w500,
              height: 1.12,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.auth,
    required this.nameController,
    required this.pinController,
    required this.nameFocusNode,
    required this.pinFocusNode,
    required this.obscurePin,
    required this.onTogglePinVisibility,
    required this.onLogin,
  });

  final AuthController auth;
  final TextEditingController nameController;
  final TextEditingController pinController;
  final FocusNode nameFocusNode;
  final FocusNode pinFocusNode;
  final bool obscurePin;
  final VoidCallback onTogglePinVisibility;
  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoginTextField(
            controller: nameController,
            focusNode: nameFocusNode,
            labelText: '이름',
            hintText: '이름을 입력하세요',
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => pinFocusNode.requestFocus(),
            suffixIcon:
                ValueListenableBuilder<TextEditingValue>(
              valueListenable: nameController,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  tooltip: '이름 지우기',
                  onPressed: nameController.clear,
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
            controller: pinController,
            focusNode: pinFocusNode,
            labelText: 'PIN',
            hintText: '4자리 숫자',
            prefixIcon: Icons.lock_outline_rounded,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            obscureText: obscurePin,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onSubmitted: (_) {
              if (!auth.isLoading) {
                onLogin();
              }
            },
            suffixIcon: IconButton(
              tooltip: obscurePin ? 'PIN 보기' : 'PIN 숨기기',
              onPressed: onTogglePinVisibility,
              icon: Icon(
                obscurePin
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
              onPressed: auth.isLoading ? null : onLogin,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    primaryColor.withValues(alpha: 0.55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
                      style: forestringTextStyle.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
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
        fillColor: const Color(0xffFAFBF8),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.black.withValues(alpha: 0.12),
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
