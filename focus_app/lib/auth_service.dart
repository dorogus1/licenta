import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'windows_process_monitor.dart';

class SessionUpdate {
  final bool isActive;
  final int? endTime;
  final String? updatedBy;

  SessionUpdate({required this.isActive, this.endTime, this.updatedBy});
}

class AuthService {
  static const String _apiKey = 'AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY';
  static const String _dbUrl = 'https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app';
  
  static const String _signInUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey';
  static const String _signUpUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey';
  static const String _idpUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$_apiKey';

  Timer? _heartbeatTimer;
  Timer? _pollingTimer;
  String? _currentUserId;
  String? _deviceId;
  final _sessionStreamController = StreamController<SessionUpdate>.broadcast();

  Stream<SessionUpdate> get sessionStream => _sessionStreamController.stream;

  // --- GOOGLE SIGN IN ---
  Future<String?> signInWithGoogle() async {
    try {
      const List<String> scopes = [
        'email', 
        'profile', 
        'https://www.googleapis.com/auth/calendar.events', 
        'openid'
      ];

      if (!kIsWeb && Platform.isAndroid) {
        // NATIVE ANDROID
        final GoogleSignIn googleSignIn = GoogleSignIn(
          scopes: scopes,
          serverClientId: '1024855875521-1vep6qm5hb85ifqaatqvelf79glk0j9k.apps.googleusercontent.com',
        );

        
        try {
          await googleSignIn.signOut();
        } catch (_) {}

        final account = await googleSignIn.signIn();
        if (account == null) return 'Autentificarea a fost anulată.';

        final auth = await account.authentication;
        final String? idToken = auth.idToken;
        final String? accessToken = auth.accessToken;

        if (idToken == null) return 'Eroare: Nu s-a putut obține ID Token.';

        final prefs = await SharedPreferences.getInstance();
        if (accessToken != null) {
          await prefs.setString('google_access_token', accessToken);
        }

        return await _exchangeTokenWithFirebase(idToken);
      } else if (!kIsWeb && Platform.isWindows) {
        // WINDOWS FLOW
        return await _signInGoogleWindows(scopes);
      }
      return 'Platformă nesuportată.';
    } catch (e) {
      return 'Google Sign-In Error: $e';
    }
  }

  Future<String?> _exchangeTokenWithFirebase(String idToken) async {
    final response = await http.post(
      Uri.parse(_idpUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'postBody': 'id_token=$idToken&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      }),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200) {
      await _saveSession(data['idToken'], data['localId'], data['email']);
      _startHeartbeat(data['localId'], data['idToken']);
      return null;
    } else {
      return data['error']?['message'] ?? 'Firebase exchange failed';
    }
  }

  Future<String?> _signInGoogleWindows(List<String> scopes) async {
    final String clientId = '1024855875521-5di5ev1sjkg6s6npvvcjjb93as8n3vte.apps.googleusercontent.com';
    const String clientSecret = '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';
    
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final String redirectUri = 'http://127.0.0.1:${server.port}';

    final String authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
        '?client_id=$clientId&redirect_uri=$redirectUri&response_type=code&scope=${scopes.join(' ')}';

    if (await canLaunchUrl(Uri.parse(authUrl))) {
      await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      return 'Browser error.';
    }

    try {
      final HttpRequest request = await server.first.timeout(const Duration(minutes: 2));
      final String? code = request.uri.queryParameters['code'];
      await WindowsProcessMonitor.forceToForeground();
      
      request.response..statusCode = HttpStatus.ok..headers.contentType = ContentType.html
        ..write('<html><body><h1>Success! Return to app.</h1></body></html>');
      await request.response.close();
      await server.close();

      if (code == null) return 'No code.';

      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': code,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
      );

      final tokenData = json.decode(tokenResponse.body);
      final String? idToken = tokenData['id_token'];
      final String? accessToken = tokenData['access_token'];

      if (idToken == null) return 'No ID Token.';
      
      final prefs = await SharedPreferences.getInstance();
      if (accessToken != null) await prefs.setString('google_access_token', accessToken);

      return await _exchangeTokenWithFirebase(idToken);
    } catch (e) {
      await server.close();
      return 'Error: $e';
    }
  }

  // --- REGULAR AUTH ---
  Future<String?> signIn(String email, String password) async {
    final response = await http.post(
      Uri.parse(_signInUrl),
      body: json.encode({'email': email, 'password': password, 'returnSecureToken': true}),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200) {
      await _saveSession(data['idToken'], data['localId'], data['email']);
      _startHeartbeat(data['localId'], data['idToken']);
      return null;
    }
    return data['error']?['message'] ?? 'Login failed';
  }

  Future<String?> signUp(String email, String password) async {
    final response = await http.post(
      Uri.parse(_signUpUrl),
      body: json.encode({'email': email, 'password': password, 'returnSecureToken': true}),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200) {
      await _saveSession(data['idToken'], data['localId'], data['email']);
      _startHeartbeat(data['localId'], data['idToken']);
      return null;
    }
    return data['error']?['message'] ?? 'Sign up failed';
  }

  Future<void> signOut() async {
    _stopHeartbeat();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_email');
    await prefs.remove('google_access_token');
    
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      } catch (e) {
        debugPrint('GoogleSignIn signOut error: $e');
      }
    }
  }

  // --- HELPERS ---
  Future<void> _saveSession(String token, String userId, String? email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_user_id', userId);
    if (email != null) await prefs.setString('auth_email', email);
    if (!prefs.containsKey('device_id')) {
      await prefs.setString('device_id', 'dev_${DateTime.now().millisecondsSinceEpoch}');
    }
    _deviceId = prefs.getString('device_id');
  }

  void _startHeartbeat(String userId, String token) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    _stopHeartbeat();
    _sendHeartbeatRequest(userId, token);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sendHeartbeatRequest(userId, token));
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pollSession(userId, token));
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _pollingTimer?.cancel();
  }

  Future<void> _pollSession(String userId, String token) async {
    final url = '$_dbUrl/users/$userId/focus_session.json?auth=$token';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body);
        _sessionStreamController.add(SessionUpdate(
          isActive: data['isActive'] ?? false,
          endTime: data['endTime'],
          updatedBy: data['updatedBy'],
        ));
      }
    } catch (_) {}
  }

  Future<void> _sendHeartbeatRequest(String userId, String token) async {
    if (_deviceId == null) return;
    final url = '$_dbUrl/users/$userId/devices/$_deviceId.json?auth=$token';
    try {
      await http.patch(Uri.parse(url), body: json.encode({
        'name': Platform.localHostname,
        'type': Platform.isAndroid ? 'mobile' : 'windows',
        'platform': Platform.operatingSystem,
        'state': 'online',
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    if (token != null && userId != null) {
      _startHeartbeat(userId, token);
      return true;
    }
    return false;
  }

  Future<String?> getGoogleAccessToken() async => (await SharedPreferences.getInstance()).getString('google_access_token');
  Future<String?> getUserEmail() async => (await SharedPreferences.getInstance()).getString('auth_email');
  Future<String?> getDeviceId() async => (await SharedPreferences.getInstance()).getString('device_id');

  Future<Map<String, dynamic>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    if (token == null || userId == null) return {};
    final url = '$_dbUrl/users/$userId/devices.json?auth=$token';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.body != 'null') {
        return Map<String, dynamic>.from(json.decode(response.body));
      }
    } catch (_) {}
    return {};
  }

  Future<void> updatePresence(String state) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    if (token == null || userId == null || _deviceId == null) return;
    final url = '$_dbUrl/users/$userId/devices/$_deviceId.json?auth=$token';
    try {
      await http.patch(Uri.parse(url), body: json.encode({
        'state': state,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  Future<void> updateFocusSession(bool isActive, int? endTimeMillis) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    if (token == null || userId == null) return;
    final url = '$_dbUrl/users/$userId/focus_session.json?auth=$token';
    await http.put(Uri.parse(url), body: json.encode({
      'isActive': isActive,
      'endTime': endTimeMillis,
      'lastUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      'updatedBy': _deviceId ?? 'unknown',
    }));
  }

  Future<void> updateBlockedApps(List<String> blockedApps) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    if (token == null || userId == null) return;
    final url = '$_dbUrl/users/$userId/blocked_apps.json?auth=$token';
    await http.put(Uri.parse(url), body: json.encode(blockedApps));
  }
}
