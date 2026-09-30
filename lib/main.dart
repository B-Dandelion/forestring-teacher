import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_gate.dart';
import 'core/config/app_config.dart';
import 'core/theme/forestring_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    AppConfig.validate();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    ).timeout(const Duration(seconds: 10));
  } on TimeoutException {
    runApp(
      const _StartupFailureApp(
        message: '앱 시작이 지연되고 있습니다.\n인터넷 연결을 확인한 뒤 앱을 다시 실행해주세요.',
      ),
    );
    return;
  } catch (_) {
    runApp(
      const _StartupFailureApp(
        message: '앱을 시작하지 못했습니다.\n잠시 후 다시 실행해주세요.',
      ),
    );
    return;
  }

  final authController = AuthController(
    AuthRepository(),
  );

  runApp(
    ChangeNotifierProvider.value(
      value: authController,
      child: const ForestringTeacher(),
    ),
  );

  unawaited(authController.initialize());
}

class ForestringTeacher extends StatelessWidget {
  const ForestringTeacher({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: MaterialApp(
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [
          Locale('ko', 'KR'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        title: '포레스트링 선생님',
        theme: buildForestringTheme(),
        builder: (context, child) {
          final app = child ?? const SizedBox.shrink();

          if (!AppConfig.isStaging) {
            return app;
          }

          return Banner(
            message: 'STAGING',
            location: BannerLocation.topEnd,
            child: app,
          );
        },
        home: const AppGate(),
      ),
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildForestringTheme(),
      home: Scaffold(
        backgroundColor: primaryColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: forestringTextStyle.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
