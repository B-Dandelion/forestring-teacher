import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../auth/domain/current_profile.dart';

class TeacherMyPage extends StatelessWidget {
  const TeacherMyPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        title: Text(
          '포레스트링',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Text(
            '${profile.displayName} 선생님\n마이페이지를 준비하고 있습니다.',
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
