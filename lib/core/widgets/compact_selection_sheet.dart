import 'package:flutter/material.dart';

import '../theme/forestring_theme.dart';

class CompactSelectionOption<T> {
  const CompactSelectionOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

Future<T?> showCompactSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<CompactSelectionOption<T>> options,
  T? selectedValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.56,
            ),
            decoration: BoxDecoration(
              color: const Color(0xffFCFDF9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: forestringTextStyle.copyWith(
                            color: primaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    itemCount: options.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option.value == selectedValue;
                      return Material(
                        color: selected
                            ? primaryColor.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              Navigator.of(sheetContext).pop(option.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? primaryColor.withValues(alpha: 0.20)
                                    : primaryColor.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.label,
                                        style: forestringTextStyle.copyWith(
                                          color: Colors.black87,
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w500
                                              : FontWeight.w300,
                                        ),
                                      ),
                                      if (option.subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          option.subtitle!,
                                          style:
                                              forestringTextStyle.copyWith(
                                            color: Colors.black45,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_rounded,
                                    color: primaryColor,
                                    size: 19,
                                  ),
                              ],
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
        ),
      );
    },
  );
}

class CompactSelectionField extends StatelessWidget {
  const CompactSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: neutralIvory.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled ? primaryColor : Colors.black26,
                size: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black45,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: enabled ? Colors.black87 : Colors.black38,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: enabled ? primaryColor : Colors.black26,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
