import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../data/lesson_repository.dart';

class StudentSearchPickerField extends StatelessWidget {
  const StudentSearchPickerField({
    super.key,
    required this.students,
    required this.selectedStudentId,
    required this.onChanged,
    this.label = '학생',
    this.includeAllOption = false,
    this.enabled = true,
    this.compact = false,
    this.managementSearchStyle = false,
  });

  final List<VisibleStudent> students;
  final String? selectedStudentId;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool includeAllOption;
  final bool enabled;
  final bool compact;
  final bool managementSearchStyle;

  VisibleStudent? get _selectedStudent {
    final id = selectedStudentId;
    if (id == null) return null;
    for (final student in students) {
      if (student.id == id) return student;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: neutralIvory,
      builder: (_) => _StudentPickerSheet(
        students: students,
        selectedStudentId: selectedStudentId,
        includeAllOption: includeAllOption,
      ),
    );

    if (result == null) return;
    onChanged(result == _StudentPickerSheet.allValue ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedStudent;
    final valueText = selected?.displayName ??
        (includeAllOption ? '전체 학생' : '학생을 검색해 선택');

    if (managementSearchStyle) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => _open(context) : null,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: enabled ? primaryColor : Colors.black26,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected == null
                        ? (includeAllOption
                            ? '학생 검색 · 전체 학생'
                            : '학생 이름 검색')
                        : selected.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: selected == null
                          ? Colors.black38
                          : Colors.black87,
                      fontSize: 13,
                      fontWeight: selected == null
                          ? FontWeight.w300
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '선택됨',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
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

    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? () => _open(context) : null,
          child: Container(
            height: 36,
            constraints: const BoxConstraints(maxWidth: 190),
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
                Icon(
                  Icons.search_rounded,
                  size: 15,
                  color: enabled ? primaryColor : Colors.black26,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    valueText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: enabled ? Colors.black87 : Colors.black38,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
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
      borderRadius: BorderRadius.circular(9),
      onTap: enabled ? () => _open(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: neutralIvory,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: primaryColor.withValues(alpha: 0.18),
            ),
          ),
          suffixIcon: Icon(
            Icons.search_rounded,
            color: enabled ? primaryColor : Colors.black26,
          ),
        ),
        child: Text(
          valueText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: forestringTextStyle.copyWith(
            color: enabled ? Colors.black87 : Colors.black38,
          ),
        ),
      ),
    );
  }
}

class _StudentPickerSheet extends StatefulWidget {
  const _StudentPickerSheet({
    required this.students,
    required this.selectedStudentId,
    required this.includeAllOption,
  });

  static const allValue = '__all_students__';

  final List<VisibleStudent> students;
  final String? selectedStudentId;
  final bool includeAllOption;

  @override
  State<_StudentPickerSheet> createState() => _StudentPickerSheetState();
}

class _StudentPickerSheetState extends State<_StudentPickerSheet> {
  late final TextEditingController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<VisibleStudent> get _filteredStudents {
    final query = _query.trim().toLowerCase();
    final result = widget.students.where((student) {
      if (query.isEmpty) return true;
      return student.displayName.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final students = _filteredStudents;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '학생 선택',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.students.length}명',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '학생 이름 검색',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: students.isEmpty
                  ? Center(
                      child: Text(
                        '검색 결과가 없습니다.',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount:
                          students.length + (widget.includeAllOption ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (widget.includeAllOption && index == 0) {
                          return ListTile(
                            leading: const Icon(
                              Icons.groups_2_outlined,
                              color: primaryColor,
                            ),
                            title: Text(
                              '전체 학생',
                              style: forestringTextStyle.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: widget.selectedStudentId == null
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: primaryColor,
                                  )
                                : null,
                            onTap: () => Navigator.of(context)
                                .pop(_StudentPickerSheet.allValue),
                          );
                        }

                        final itemIndex =
                            index - (widget.includeAllOption ? 1 : 0);
                        final student = students[itemIndex];
                        final selected =
                            student.id == widget.selectedStudentId;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                primaryColor.withValues(alpha: 0.08),
                            foregroundColor: primaryColor,
                            child: Text(
                              student.displayName.isEmpty
                                  ? '?'
                                  : student.displayName.substring(0, 1),
                              style: forestringTextStyle.copyWith(
                                color: primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          title: Text(
                            student.displayName,
                            style: forestringTextStyle.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: primaryColor,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(student.id),
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
