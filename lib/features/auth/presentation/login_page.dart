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

    final loginPanel = _GlassLoginPanel(
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
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          const Positioned.fill(
            child: _LoginBackground(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final topPadding = compact ? 10.0 : 18.0;
                final bottomPadding =
                    compact ? keyboardInset + 10.0 : 22.0;
                final availableHeight =
                    constraints.maxHeight -
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
                            constraints: const BoxConstraints(
                              maxWidth: 430,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: compact
                                        ? Alignment.center
                                        : const Alignment(0, 0.20),
                                    child: _LoginBrand(
                                      compact: compact,
                                    ),
                                  ),
                                ),
                                if (compact)
                                  const SizedBox(height: 20),
                                loginPanel,
                                if (widget.onManagerQaStart != null) ...[
                                  SizedBox(
                                    height: compact ? 10 : 14,
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
                  ),
                );
              },
            ),
          ),
        ],
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
            height: compact ? 90 : 144,
            width: double.infinity,
            child: ClipRect(
              child: Transform.scale(
                scale: compact ? 1.60 : 2.05,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/img/포레스트링_선생님_로고.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 16 : 26),
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
          SizedBox(height: compact ? 7 : 10),
          Text(
            '수업과 일정을 한곳에서 편리하게 관리하세요',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
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
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 26,
            sigmaY: 26,
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
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.07),
                      ],
                      stops: const [0, 0.56, 1],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0.8,
                left: 34,
                right: 34,
                child: IgnorePointer(
                  child: Container(
                    height: 1.2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 86,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.07),
                          Colors.white.withValues(alpha: 0.025),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 10,
                child: IgnorePointer(
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.035),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '로그인',
                      style: forestringTextStyle.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GlassTextField(
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
                    const SizedBox(height: 14),
                    _GlassTextField(
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
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff5B1D1A)
                              .withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xffF3A79F)
                                .withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
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
                    const SizedBox(height: 16),
                    _GlassActionButton(
                      isLoading: auth.isLoading,
                      onPressed: onLogin,
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
      onTapOutside: (_) =>
          FocusManager.instance.primaryFocus?.unfocus(),
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
          color: Colors.white.withValues(alpha: 0.45),
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
            Colors.white.withValues(alpha: 0.66),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.085),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 17,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.34),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10,
            sigmaY: 10,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLoading ? null : () => onPressed(),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.15),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(
                      child: isLoading
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
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
          foregroundColor: Colors.white.withValues(alpha: 0.62),
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
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
