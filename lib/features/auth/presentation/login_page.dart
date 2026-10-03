import 'dart:ui';

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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _LoginBackground(),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight =
                      constraints.maxHeight - keyboardInset - 24;

                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 230),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      compact ? 12 : 34,
                      22,
                      compact ? keyboardInset + 10 : 24,
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
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 430,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                _LoginBrand(compact: compact),
                                SizedBox(
                                  height: compact ? 24 : 48,
                                ),
                                _GlassLoginPanel(
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
                                    height: compact ? 10 : 16,
                                  ),
                                  _QaEntryButton(
                                    onPressed:
                                        widget.onManagerQaStart!,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: primaryColor,
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
        children: [
          SizedBox(
            height: compact ? 92 : 126,
            width: double.infinity,
            child: ClipRect(
              child: Transform.scale(
                scale: compact ? 1.45 : 1.7,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/img/포레스트링_선생님_로고.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SizedBox(
            height: compact ? 24 : 38,
          ),
          Text(
            '포레스트링 선생님',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white,
              fontSize: compact ? 24 : 31,
              fontWeight: FontWeight.w500,
              height: 1.12,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(
            height: compact ? 7 : 12,
          ),
          Text(
            '수업과 일정을 한곳에서 편리하게 관리하세요',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.64),
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w300,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassLoginPanel extends StatelessWidget {
  const _GlassLoginPanel({
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
    const radius = 30.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 24,
            sigmaY: 24,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.19),
                        Colors.white.withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.085),
                      ],
                      stops: const [0, 0.52, 1],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 1,
                left: 34,
                right: 34,
                child: IgnorePointer(
                  child: Container(
                    height: 1.4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.70),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 20,
                left: 1,
                bottom: 72,
                child: IgnorePointer(
                  child: Container(
                    width: 1.2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -46,
                left: -26,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: -0.20,
                    child: Container(
                      width: 230,
                      height: 118,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(80),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.17),
                            Colors.white.withValues(alpha: 0.055),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 7,
                child: IgnorePointer(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.045),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  22,
                  20,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldLabel(
                      label: '이름',
                      child: _GlassTextField(
                        controller: nameController,
                        focusNode: nameFocusNode,
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
                    ),
                    const SizedBox(height: 17),
                    _FieldLabel(
                      label: '비밀번호',
                      child: _GlassTextField(
                        controller: pinController,
                        focusNode: pinFocusNode,
                        hintText: '4자리 비밀번호',
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
                          tooltip: obscurePin
                              ? '비밀번호 보기'
                              : '비밀번호 숨기기',
                          onPressed: onTogglePinVisibility,
                          icon: Icon(
                            obscurePin
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff5B1D1A)
                              .withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xffF3A79F)
                                .withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.info_outline_rounded,
                                size: 17,
                                color: Color(0xffFFD1CC),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: forestringTextStyle.copyWith(
                                  color: const Color(0xffFFE5E1),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 21),
                    SizedBox(
                      height: 55,
                      child: FilledButton(
                        onPressed: auth.isLoading ? null : onLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.95),
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.58),
                          foregroundColor: primaryColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 21,
                                height: 21,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: primaryColor,
                                ),
                              )
                            : Text(
                                '로그인',
                                style: forestringTextStyle.copyWith(
                                  color: primaryColor,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.focusNode,
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
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: obscureText ? 2 : 0,
      ),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        hintStyle: forestringTextStyle.copyWith(
          color: Colors.white.withValues(alpha: 0.48),
          fontSize: 15,
          fontWeight: FontWeight.w300,
          letterSpacing: 0,
        ),
        prefixIcon: Icon(
          prefixIcon,
          size: 21,
          color: Colors.white.withValues(alpha: 0.72),
        ),
        suffixIcon: suffixIcon,
        suffixIconColor:
            Colors.white.withValues(alpha: 0.68),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.095),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 17,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.52),
            width: 1.35,
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 2,
            bottom: 8,
          ),
          child: Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _QaEntryButton extends StatelessWidget {
  const _QaEntryButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.64),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 11,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(
          Icons.developer_mode_rounded,
          size: 17,
        ),
        label: Text(
          'QA 지점장으로 시작',
          style: forestringTextStyle.copyWith(
            color: Colors.white.withValues(alpha: 0.64),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
