import 'package:flutter/material.dart';

import '../theme/forestring_theme.dart';
import 'push_device_repository.dart';

Future<void> showNotificationSettingsSheet({
  required BuildContext context,
}) async {
  final repository = PushDeviceRepository();

  NotificationPreferences preferences;

  try {
    preferences = await repository.getPreferences();
  } catch (_) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('알림 설정을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'),
      ),
    );
    return;
  }

  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      var current = preferences;
      var saving = false;

      Future<void> update({
        bool? pushEnabled,
        bool? lessonAssignmentEnabled,
        bool? lessonScheduleChangeEnabled,
        bool? lessonCancellationEnabled,
        bool? makeupEnabled,
        bool? flexBookingEnabled,
        required StateSetter setModalState,
      }) async {
        if (saving) {
          return;
        }

        setModalState(() {
          saving = true;
        });

        try {
          final next = await repository.updatePreferences(
            pushEnabled: pushEnabled,
            lessonAssignmentEnabled: lessonAssignmentEnabled,
            lessonScheduleChangeEnabled: lessonScheduleChangeEnabled,
            lessonCancellationEnabled: lessonCancellationEnabled,
            makeupEnabled: makeupEnabled,
            flexBookingEnabled: flexBookingEnabled,
          );

          if (!sheetContext.mounted) {
            return;
          }

          setModalState(() {
            current = next;
          });
        } catch (_) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              const SnackBar(
                content: Text('알림 설정을 저장하지 못했습니다.'),
              ),
            );
          }
        } finally {
          if (sheetContext.mounted) {
            setModalState(() {
              saving = false;
            });
          }
        }
      }

      return StatefulBuilder(
        builder: (context, setModalState) {
          final enabled = current.pushEnabled;

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '알림 설정',
                              style: forestringTextStyle.copyWith(
                                color: Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      SwitchListTile.adaptive(
                        secondary: const Icon(
                          Icons.notifications_outlined,
                          color: primaryColor,
                        ),
                        title: Text(
                          '전체 알림',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black87,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '포레스트링에서 보내는 수업 알림을 받습니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 11,
                          ),
                        ),
                        value: current.pushEnabled,
                        onChanged: saving
                            ? null
                            : (value) => update(
                                  pushEnabled: value,
                                  setModalState: setModalState,
                                ),
                      ),
                      const Divider(height: 1),
                      _NotificationSwitch(
                        title: '새 수업 배정',
                        subtitle: '새 학생 또는 수업이 담당 선생님에게 배정될 때',
                        value: current.lessonAssignmentEnabled,
                        enabled: enabled && !saving,
                        onChanged: (value) => update(
                          lessonAssignmentEnabled: value,
                          setModalState: setModalState,
                        ),
                      ),
                      _NotificationSwitch(
                        title: '수업 일정 변경',
                        subtitle: '1회 또는 정규 수업 일정이 변경될 때',
                        value: current.lessonScheduleChangeEnabled,
                        enabled: enabled && !saving,
                        onChanged: (value) => update(
                          lessonScheduleChangeEnabled: value,
                          setModalState: setModalState,
                        ),
                      ),
                      _NotificationSwitch(
                        title: '수업 취소',
                        subtitle: '담당 수업이 취소될 때',
                        value: current.lessonCancellationEnabled,
                        enabled: enabled && !saving,
                        onChanged: (value) => update(
                          lessonCancellationEnabled: value,
                          setModalState: setModalState,
                        ),
                      ),
                      _NotificationSwitch(
                        title: '보강 등록 · 취소',
                        subtitle: '담당 학생의 보강 수업이 등록되거나 취소될 때',
                        value: current.makeupEnabled,
                        enabled: enabled && !saving,
                        onChanged: (value) => update(
                          makeupEnabled: value,
                          setModalState: setModalState,
                        ),
                      ),
                      _NotificationSwitch(
                        title: '자율 학생 예약',
                        subtitle: '자율 학생이 새 수업을 예약할 때',
                        value: current.flexBookingEnabled,
                        enabled: enabled && !saving,
                        onChanged: (value) => update(
                          flexBookingEnabled: value,
                          setModalState: setModalState,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          '휴대폰 설정에서 포레스트링 알림 권한을 끈 경우에는 '
                          '여기서 켜도 알림이 표시되지 않습니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black38,
                            fontSize: 10.5,
                            height: 1.4,
                          ),
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
    },
  );
}

class _NotificationSwitch extends StatelessWidget {
  const _NotificationSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      title: Text(
        title,
        style: forestringTextStyle.copyWith(
          color: enabled ? Colors.black87 : Colors.black38,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: forestringTextStyle.copyWith(
          color: enabled ? Colors.black45 : Colors.black26,
          fontSize: 10.5,
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}
