import 'package:flutter/material.dart';

import '../theme/forestring_theme.dart';
import '../theme/student_accent_controller.dart';

Future<void> showScheduleDisplayModeSheet({
  required BuildContext context,
  required StudentAccentController controller,
}) async {
  final selected = await showModalBottomSheet<ScheduleDisplayMode>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Material(
            color: const Color(0xffFCFDF9),
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '시간표 표시 방식',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final mode in ScheduleDisplayMode.values) ...[
                    _ScheduleDisplayModeOption(
                      mode: mode,
                      selected: controller.displayMode == mode,
                      onTap: () => Navigator.of(sheetContext).pop(mode),
                    ),
                    if (mode != ScheduleDisplayMode.values.last)
                      const SizedBox(height: 7),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.phone_iphone_rounded,
                          color: primaryColor,
                          size: 17,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '이 설정은 이 기기의 현재 계정에 저장되며 '
                            '다음 실행에도 그대로 유지됩니다.',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black54,
                              fontSize: 10.5,
                              height: 1.4,
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
        ),
      );
    },
  );

  if (selected != null) {
    await controller.setDisplayMode(selected);
  }
}

class _ScheduleDisplayModeOption extends StatelessWidget {
  const _ScheduleDisplayModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ScheduleDisplayMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? primaryColor.withValues(alpha: 0.075)
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? primaryColor.withValues(alpha: 0.22)
                  : primaryColor.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? primaryColor.withValues(alpha: 0.10)
                      : const Color(0xffF3F5F1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  mode.icon,
                  color: selected ? primaryColor : Colors.black45,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mode.description,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black45,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? primaryColor : Colors.black26,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
