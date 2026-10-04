import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent_controller.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_management_page.dart';
import '../../managers/presentation/manager_management_page.dart';
import '../../semesters/presentation/semester_management_page.dart';

class MasterManagementPage extends StatelessWidget {
  const MasterManagementPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    final accentController = context.watch<StudentAccentController>();

    return Scaffold(
      backgroundColor: neutralIvory,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            _sectionTitle('운영 관리'),
            const SizedBox(height: 8),
            _ManagementCard(
              children: [
                _ManagementTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '지점장 관리',
                  subtitle: '지점장 계정과 담당 지점을 관리합니다.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManagerManagementPage(),
                    ),
                  ),
                ),
                const _CardDivider(),
                _ManagementTile(
                  icon: Icons.storefront_outlined,
                  title: '지점 관리',
                  subtitle: '학원 지점 정보와 운영 상태를 관리합니다.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BranchManagementPage(
                        profile: profile,
                      ),
                    ),
                  ),
                ),
                const _CardDivider(),
                _ManagementTile(
                  icon: Icons.event_note_outlined,
                  title: '학기 관리',
                  subtitle: '학기 기간과 지점별 운영 일정을 관리합니다.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SemesterManagementPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('화면 설정'),
            const SizedBox(height: 8),
            _ManagementCard(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    accentController.isEnabled
                        ? Icons.palette_rounded
                        : Icons.palette_outlined,
                    color: primaryColor,
                  ),
                  title: Text(
                    '학생별 색상 구분',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '일정에서 학생마다 다른 색상을 사용합니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 11,
                    ),
                  ),
                  value: accentController.isEnabled,
                  activeThumbColor: primaryColor,
                  onChanged: accentController.setEnabled,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('계정'),
            const SizedBox(height: 8),
            _ManagementCard(
              children: [
                _ManagementTile(
                  icon: Icons.logout_rounded,
                  iconColor: Colors.redAccent,
                  title: '로그아웃',
                  titleColor: Colors.redAccent,
                  showChevron: false,
                  onTap: () async {
                    await context.read<AuthController>().signOut();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: forestringTextStyle.copyWith(
          color: Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ManagementTile extends StatelessWidget {
  const _ManagementTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor = primaryColor,
    this.titleColor = Colors.black87,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final Color titleColor;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 21,
        ),
      ),
      title: Text(
        title,
        style: forestringTextStyle.copyWith(
          color: titleColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: forestringTextStyle.copyWith(
                color: Colors.black45,
                fontSize: 11,
              ),
            ),
      trailing: showChevron
          ? const Icon(
              Icons.chevron_right_rounded,
              color: Colors.black38,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 68),
      child: Divider(
        height: 1,
        color: Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}
