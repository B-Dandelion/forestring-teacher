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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = constraints.maxHeight - keyboardInset - 36;

              return AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  22,
                  18,
                  22,
                  keyboardInset > 0 ? keyboardInset + 12 : 22,
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: minHeight > 0 ? minHeight : 0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LoginBrand(
                              compact: keyboardInset > 0,
                            ),
                            SizedBox(
                              height: keyboardInset > 0 ? 22 : 34,
                            ),
                            _LoginCard(
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
                              const SizedBox(height: 14),
                              _QaEntryButton(
                                onPressed: widget.onManagerQaStart!,
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Column(
        children: [
          Image.asset(
            'assets/img/포레스트링_선생님_로고.png',
            height: compact ? 88 : 122,
            fit: BoxFit.contain,
          ),
          SizedBox(height: compact ? 12 : 20),
          Text(
            '포레스트링 선생님',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white,
              fontSize: compact ? 25 : 29,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
          SizedBox(height: compact ? 5 : 8),
          Text(
            '수업과 일정을 한곳에서 관리하세요',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w300,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xffFAFAF6),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(
            label: '이름',
            child: TextField(
              controller: nameController,
              focusNode: nameFocusNode,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              onSubmitted: (_) => pinFocusNode.requestFocus(),
              style: forestringTextStyle.copyWith(
                color: const Color(0xff20231F),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              decoration: _fieldDecoration(
                hintText: '이름을 입력하세요',
                prefixIcon: Icons.person_outline_rounded,
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
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
          ),
          const SizedBox(height: 16),
          _FieldLabel(
            label: '비밀번호',
            child: TextField(
              controller: pinController,
              focusNode: pinFocusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              obscureText: obscurePin,
              maxLength: 4,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onSubmitted: (_) {
                if (!auth.isLoading) {
                  onLogin();
                }
              },
              style: forestringTextStyle.copyWith(
                color: const Color(0xff20231F),
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: 2,
              ),
              decoration: _fieldDecoration(
                hintText: '4자리 비밀번호',
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  tooltip: obscurePin ? '비밀번호 보기' : '비밀번호 숨기기',
                  onPressed: onTogglePinVisibility,
                  icon: Icon(
                    obscurePin
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                ),
              ).copyWith(
                counterText: '',
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
                color: const Color(0xffFFF2F0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xffA84E45),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      auth.errorMessage!,
                      style: forestringTextStyle.copyWith(
                        color: const Color(0xff8E4038),
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
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: auth.isLoading ? null : onLogin,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                disabledBackgroundColor:
                    primaryColor.withValues(alpha: 0.55),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData prefixIcon,
    required Widget suffixIcon,
  }) {
    const borderColor = Color(0xffE1E5DE);

    return InputDecoration(
      hintText: hintText,
      hintStyle: forestringTextStyle.copyWith(
        color: const Color(0xff9B9F99),
        fontSize: 15,
        fontWeight: FontWeight.w300,
        letterSpacing: 0,
      ),
      prefixIcon: Icon(
        prefixIcon,
        size: 21,
        color: const Color(0xff657069),
      ),
      suffixIcon: suffixIcon,
      suffixIconColor: const Color(0xff657069),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: borderColor,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: secondaryColor,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: Color(0xffC87067),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: Color(0xffC87067),
          width: 1.5,
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
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            label,
            style: forestringTextStyle.copyWith(
              color: const Color(0xff2D322E),
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
          foregroundColor: Colors.white.withValues(alpha: 0.68),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
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
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
