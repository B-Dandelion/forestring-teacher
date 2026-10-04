import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../../semesters/domain/managed_semester.dart';

class LessonSemesterPicker extends StatelessWidget {
  const LessonSemesterPicker({
    super.key,
    required this.semesters,
    required this.selectedSemesterId,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final List<ManagedSemester> semesters;
  final String? selectedSemesterId;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool compact;

  ManagedSemester? get _selected {
    final id = selectedSemesterId;
    if (id == null) return null;
    for (final semester in semesters) {
      if (semester.id == id) return semester;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && semesters.isNotEmpty
              ? () => _showPicker(context)
              : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 15,
                  color: primaryColor,
                ),
                const SizedBox(width: 5),
                Text(
                  selected == null ? '학기 선택' : _semesterLabel(selected.code),
                  style: forestringTextStyle.copyWith(
                    color: enabled ? Colors.black87 : Colors.black38,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: enabled ? primaryColor : Colors.black26,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: enabled && semesters.isNotEmpty
          ? () => _showPicker(context)
          : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: '학기',
          border: const OutlineInputBorder(),
          suffixIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: enabled ? Colors.black54 : Colors.black26,
          ),
        ),
        child: Text(
          selected == null ? '선택' : _semesterLabel(selected.code),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: forestringTextStyle.copyWith(
            color: enabled ? Colors.black87 : Colors.black38,
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final selectedIndex = semesters.indexWhere(
      (semester) => semester.id == selectedSemesterId,
    );
    final initialOffset = selectedIndex <= 2
        ? 0.0
        : (selectedIndex * 56.0 - 112.0)
            .clamp(0.0, double.infinity)
            .toDouble();
    final scrollController = ScrollController(initialScrollOffset: initialOffset);

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.62,
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: const BoxDecoration(
              color: neutralIvory,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '학기 선택',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: semesters.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final semester = semesters[index];
                      final selected = semester.id == selectedSemesterId;
                      final stateLabel = semester.isCurrent
                          ? '현재'
                          : semester.isUpcoming
                              ? '예정'
                              : null;

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          onTap: () =>
                              Navigator.of(sheetContext).pop(semester.id),
                          title: Text(
                            _semesterLabel(semester.code),
                            style: forestringTextStyle.copyWith(
                              color: selected ? primaryColor : Colors.black87,
                              fontSize: 16,
                              fontWeight: selected
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                          subtitle: Text(
                            '${semester.startsOn.month}월 ${semester.startsOn.day}일 ~ '
                            '${semester.endsOn.month}월 ${semester.endsOn.day}일',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black45,
                              fontSize: 12,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: primaryColor,
                                )
                              : stateLabel == null
                                  ? null
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(alpha: 0.09),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        stateLabel,
                                        style: forestringTextStyle.copyWith(
                                          color: primaryColor,
                                          fontSize: 11,
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
      },
    );

    scrollController.dispose();
    if (picked != null && picked != selectedSemesterId) {
      onChanged(picked);
    }
  }
}

String _semesterLabel(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return code;
  return '${match.group(1)}년 ${int.parse(match.group(2)!)}월';
}
