import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';

class RegularWeekdaySelector extends StatelessWidget {
  const RegularWeekdaySelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  static const _labels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (index) {
        final weekday = index + 1;
        final selected = weekday == value;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 6 ? 0 : 5),
            child: Material(
              color: selected
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: enabled ? () => onChanged(weekday) : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? primaryColor
                          : primaryColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Text(
                    _labels[index],
                    style: forestringTextStyle.copyWith(
                      color: selected
                          ? Colors.white
                          : enabled
                              ? Colors.black87
                              : Colors.black26,
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class RegularTimeField extends StatelessWidget {
  const RegularTimeField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final int? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null ? '선택 불가' : regularFormatMinutes(value!);

    return Material(
      color: primaryColor.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 19,
                color: enabled ? primaryColor : Colors.black26,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시작 시간',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black45,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: forestringTextStyle.copyWith(
                        color: enabled ? Colors.black87 : Colors.black38,
                        fontSize: 14,
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

Future<int?> showRegularTimePicker({
  required BuildContext context,
  required List<int> options,
  required int? selectedMinutes,
}) {
  final morning = options.where((minutes) => minutes < 12 * 60).toList();
  final afternoon = options.where((minutes) => minutes >= 12 * 60).toList();

  return showModalBottomSheet<int>(
    context: context,
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
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xffFCFDF9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 24,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '시작 시간 선택',
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
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (morning.isNotEmpty)
                          _RegularTimeSection(
                            title: '오전',
                            options: morning,
                            selectedMinutes: selectedMinutes,
                            onSelected: (value) =>
                                Navigator.of(sheetContext).pop(value),
                          ),
                        if (morning.isNotEmpty && afternoon.isNotEmpty)
                          const SizedBox(height: 16),
                        if (afternoon.isNotEmpty)
                          _RegularTimeSection(
                            title: '오후',
                            options: afternoon,
                            selectedMinutes: selectedMinutes,
                            onSelected: (value) =>
                                Navigator.of(sheetContext).pop(value),
                          ),
                      ],
                    ),
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

class _RegularTimeSection extends StatelessWidget {
  const _RegularTimeSection({
    required this.title,
    required this.options,
    required this.selectedMinutes,
    required this.onSelected,
  });

  final String title;
  final List<int> options;
  final int? selectedMinutes;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: forestringTextStyle.copyWith(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 7,
            mainAxisSpacing: 7,
            mainAxisExtent: 40,
          ),
          itemCount: options.length,
          itemBuilder: (context, index) {
            final minutes = options[index];
            final selected = minutes == selectedMinutes;

            return Material(
              color: selected
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: () => onSelected(minutes),
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selected
                          ? primaryColor
                          : primaryColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Text(
                    regularFormatMinutes(minutes),
                    style: forestringTextStyle.copyWith(
                      color: selected ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

String regularFormatMinutes(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}
