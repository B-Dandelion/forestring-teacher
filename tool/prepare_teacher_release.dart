import 'dart:io';

void main() {
  final projectFile = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!projectFile.existsSync()) {
    stderr.writeln('iOS project file not found. Run this from the project root.');
    exitCode = 1;
    return;
  }

  var project = projectFile.readAsStringSync();

  project = project
      .replaceAll(
        'com.example.forestringTeacher2.RunnerTests',
        'forestring.teacher.app.RunnerTests',
      )
      .replaceAll(
        'com.example.forestringTeacher2',
        'forestring.teacher.app',
      );

  final cleanedLines = project
      .split('\n')
      .where(
        (line) =>
            !line.contains('FLUTTER_BUILD_NAME =') &&
            !line.contains('FLUTTER_BUILD_NUMBER ='),
      )
      .toList();

  projectFile.writeAsStringSync(
    '${cleanedLines.join('\n').trimRight()}\n',
  );

  final firebasePlist = File('ios/Runner/GoogleService-Info.plist');
  final firebaseJson = File('firebase.json');

  final result = projectFile.readAsStringSync();
  final errors = <String>[];

  if (!result.contains('PRODUCT_BUNDLE_IDENTIFIER = forestring.teacher.app;')) {
    errors.add('Production iOS bundle identifier was not found.');
  }

  if (result.contains('com.example.forestringTeacher2')) {
    errors.add('Example iOS bundle identifier remains.');
  }

  if (result.contains('FLUTTER_BUILD_NAME =') ||
      result.contains('FLUTTER_BUILD_NUMBER =')) {
    errors.add('Hardcoded Flutter iOS version override remains.');
  }

  // v3.4 uses Firebase only as the FCM/APNs transport.
  // The Firebase client configuration is now required for release builds.
  if (!firebasePlist.existsSync()) {
    errors.add(
      'GoogleService-Info.plist is missing. '
      'FCM iOS configuration must be present for release builds.',
    );
  } else {
    final plist = firebasePlist.readAsStringSync();

    if (!plist.contains('<string>forestring.teacher.app</string>')) {
      errors.add(
        'GoogleService-Info.plist does not target forestring.teacher.app.',
      );
    }

    if (!plist.contains('<string>forestring1-1</string>')) {
      errors.add(
        'GoogleService-Info.plist does not target Firebase project '
        'forestring1-1.',
      );
    }

    if (!result.contains('GoogleService-Info.plist')) {
      errors.add(
        'GoogleService-Info.plist is not referenced by the Xcode project.',
      );
    }
  }

  // flutterfire configure may create firebase.json. It is safe client-side
  // configuration metadata and must not be deleted by the release cleanup.
  if (firebaseJson.existsSync()) {
    stdout.writeln('FlutterFire firebase.json: present');
  } else {
    stdout.writeln(
      'FlutterFire firebase.json: not present yet '
      '(run flutterfire configure during v3.4 setup)',
    );
  }

  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('ERROR: $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Teacher release preparation complete.');
  stdout.writeln('iOS bundle id: forestring.teacher.app');
  stdout.writeln('Firebase project: forestring1-1');
  stdout.writeln('FCM iOS client configuration: preserved');
  stdout.writeln('Hardcoded Flutter iOS version overrides: removed');
}
