// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'Scut Focus';

  @override
  String get blockApps => 'Blocare Aplicații';

  @override
  String get searchApps => 'Caută aplicații...';

  @override
  String get suggestedToBlock => 'Sugerate pentru Blocare';

  @override
  String get allApps => 'Toate Aplicațiile';

  @override
  String avgUsage(String duration) {
    return 'Utilizare medie: $duration';
  }

  @override
  String get h => 'h';

  @override
  String get mPerDay => 'm/zi';

  @override
  String get permissionRequired => 'Permisiune Necesară';

  @override
  String get usageAccessContent =>
      'Pentru a detecta aplicațiile care rulează, Focus App are nevoie de permisiunea \"Acces la utilizare\".';

  @override
  String get displayOverAppsContent =>
      'Pentru a bloca aplicațiile eficient, Focus App are nevoie de permisiunea \"Afișare peste alte aplicații\".';

  @override
  String get cancel => 'Anulează';

  @override
  String get openSettings => 'Deschide Setări';

  @override
  String get grant => 'Acordă';

  @override
  String get tasksCalendar => 'Sarcini și Calendar';

  @override
  String get settings => 'Setări';

  @override
  String get focusing => 'CONCENTRARE';

  @override
  String get ready => 'GATA';

  @override
  String get resetTimer => 'RESETARE CRONOMETRU';

  @override
  String get todayTasks => 'SARCINILE DE AZI';

  @override
  String get viewAll => 'VEZI TOT';

  @override
  String get noUpcomingTasks => 'Nicio sarcină planificată pentru azi.';

  @override
  String get sessionFinished => 'Sesiune Terminată!';

  @override
  String get achieveGoal => 'Ai reușit să finalizezi ce ți-ai propus?';

  @override
  String get yesDone => 'DA, GATA';

  @override
  String get extraTime => 'EXTRA TIMP';

  @override
  String get excellent => 'Excelent! 🚀';

  @override
  String get howMuchExtra => 'Cât timp extra?';

  @override
  String get min => 'min';

  @override
  String get profile => 'Profil';

  @override
  String get notLoggedIn => 'Nu ești autentificat';

  @override
  String deviceId(String id) {
    return 'ID Dispozitiv: $id';
  }

  @override
  String get appearance => 'Aspect';

  @override
  String get darkMode => 'Mod Întunecat';

  @override
  String get language => 'Limbă';

  @override
  String get activeDevices => 'Dispozitive Active';

  @override
  String get noOtherDevices => 'Niciun alt dispozitiv activ';

  @override
  String get you => '(Tu)';

  @override
  String get logout => 'Deconectare';

  @override
  String get createAccount => 'Crează Cont';

  @override
  String get welcomeBack => 'Bine ai revenit';

  @override
  String get email => 'Email';

  @override
  String get password => 'Parolă';

  @override
  String get signIn => 'Autentificare';

  @override
  String get signUp => 'Înregistrare';

  @override
  String get signInGoogle => 'Autentificare cu Google';

  @override
  String get alreadyHaveAccount => 'Ai deja un cont? Autentifică-te';

  @override
  String get dontHaveAccount => 'Nu ai cont? Înregistrează-te';

  @override
  String get success => 'Succes!';

  @override
  String get googleLoginSuccess =>
      'Te-ai autentificat cu succes folosind Google. Bine ai venit!';

  @override
  String get getStarted => 'Începe';

  @override
  String unexpectedError(String error) {
    return 'A apărut o eroare neașteptată: $error';
  }
}
