import 'package:flutter/material.dart';

import '../theme/forestring_theme.dart';

class RegistrationSectionHeader extends StatelessWidget {
  const RegistrationSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: forestringTextStyle.copyWith(
                  color: Colors.black38,
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RegistrationFormCard extends StatelessWidget {
  const RegistrationFormCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(13),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: child,
    );
  }
}

class RegistrationContextCard extends StatelessWidget {
  const RegistrationContextCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
    this.surfaceColor = const Color(0xffEAF3E9),
    this.iconColor = primaryColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final Color surfaceColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 10.5,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black38,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RegistrationBottomAction extends StatelessWidget {
  const RegistrationBottomAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.check_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: neutralIvory,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: FilledButton.icon(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: loading
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon),
          label: Text(
            loading ? '처리 중...' : label,
            style: forestringTextStyle.copyWith(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration registrationInputDecoration(
  String label, {
  IconData? icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null
        ? null
        : Icon(
            icon,
            color: primaryColor,
            size: 19,
          ),
    labelStyle: forestringTextStyle.copyWith(
      color: Colors.black54,
      fontSize: 12,
    ),
    counterText: '',
    filled: true,
    fillColor: neutralIvory.withValues(alpha: 0.72),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 13,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: primaryColor.withValues(alpha: 0.06),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: primaryColor.withValues(alpha: 0.22),
      ),
    ),
  );
}
