// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Focus Shield';

  @override
  String get blockApps => 'Block Apps';

  @override
  String get searchApps => 'Search apps...';

  @override
  String get suggestedToBlock => 'Suggested to Block';

  @override
  String get allApps => 'All Apps';

  @override
  String avgUsage(String duration) {
    return 'Avg usage: $duration';
  }

  @override
  String get h => 'h';

  @override
  String get mPerDay => 'm/day';

  @override
  String get permissionRequired => 'Permission Required';

  @override
  String get usageAccessContent =>
      'To detect running apps, Focus App needs \"Usage Access\" permission.';

  @override
  String get displayOverAppsContent =>
      'To block apps effectively, Focus App needs \"Display over other apps\" permission.';

  @override
  String get cancel => 'Cancel';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get grant => 'Grant';

  @override
  String get tasksCalendar => 'Tasks & Calendar';

  @override
  String get settings => 'Settings';

  @override
  String get focusing => 'FOCUSING';

  @override
  String get ready => 'READY';

  @override
  String get resetTimer => 'RESET TIMER';

  @override
  String get todayTasks => 'TODAY\'S TASKS';

  @override
  String get viewAll => 'VIEW ALL';

  @override
  String get noUpcomingTasks => 'No upcoming tasks for today.';

  @override
  String get sessionFinished => 'Session Finished!';

  @override
  String get achieveGoal => 'Did you achieve your goal?';

  @override
  String get yesDone => 'YES, DONE';

  @override
  String get extraTime => 'EXTRA TIME';

  @override
  String get excellent => 'Excellent! 🚀';

  @override
  String get howMuchExtra => 'How much extra time?';

  @override
  String get min => 'min';

  @override
  String get profile => 'Profile';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String deviceId(String id) {
    return 'Device ID: $id';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get language => 'Language';

  @override
  String get activeDevices => 'Active Devices';

  @override
  String get noOtherDevices => 'No other active devices';

  @override
  String get you => '(You)';

  @override
  String get logout => 'Logout';

  @override
  String get createAccount => 'Create Account';

  @override
  String get welcomeBack => 'Welcome Back';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign In';

  @override
  String get signUp => 'Sign Up';

  @override
  String get signInGoogle => 'Sign in with Google';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign In';

  @override
  String get dontHaveAccount => 'Don\'t have an account? Sign Up';

  @override
  String get success => 'Success!';

  @override
  String get googleLoginSuccess =>
      'You have successfully logged in with Google. Welcome!';

  @override
  String get getStarted => 'Get Started';

  @override
  String unexpectedError(String error) {
    return 'An unexpected error occurred: $error';
  }
}
