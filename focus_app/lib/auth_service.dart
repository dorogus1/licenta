import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SessionUpdate {
  final bool isActive;
  final int? endTime;
  final String? updatedBy;

  SessionUpdate({required this.isActive, this.endTime, this.updatedBy});
}

class AuthService {
  // Using the Windows API Key found in the config
  static const String _apiKey = 'AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY';
  // Use the same DB URL as the extension.
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

  // --- GOOGLE SIGN IN (Manual Loopback Flow for Windows) ---
  Future<String?> signInWithGoogle() async {
    try {
      const String clientId = '1024855875521-5di5ev1sjkg6s6npvvcjjb93as8n3vte.apps.googleusercontent.com';
      const String clientSecret = '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';
      const List<String> scopes = [
        'email',
        'profile',
        'https://www.googleapis.com/auth/calendar.events',
        'openid' // required for id_token
      ];

      // 1. Create a local server to listen for the redirect
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final int port = server.port;
      final String redirectUri = 'http://127.0.0.1:$port';

      // 2. Construct the Authorization URL
      final String authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=$clientId'
          '&redirect_uri=$redirectUri'
          '&response_type=code'
          '&scope=${scopes.join(' ')}';

      // 3. Launch the browser
      if (await canLaunchUrl(Uri.parse(authUrl))) {
        await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
      } else {
        await server.close();
        return 'Could not launch browser for sign in.';
      }

      // 4. Wait for the redirect request
      String? code;
      try {
        final HttpRequest request = await server.first.timeout(const Duration(minutes: 2));
        code = request.uri.queryParameters['code'];
        
        // Return a simple HTML response to the user
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('<html><body><h1>Login Successful!</h1><p>You can close this tab and return to the Focus App.</p><script>window.close();</script></body></html>');
        await request.response.close();
      } catch (e) {
        await server.close();
        return 'Sign in timed out or failed: $e';
      } finally {
        await server.close();
      }

      if (code == null) {
        return 'Login failed: No authorization code received.';
      }

      // 5. Exchange Authorization Code for Tokens
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
      if (tokenResponse.statusCode != 200) {
        return 'Token exchange failed: ${tokenData['error_description']}';
      }

      final String? idToken = tokenData['id_token'];
      final String? accessToken = tokenData['access_token'];

      if (idToken == null) {
        return 'Failed to retrieve ID Token from Google.';
      }

      // 6. Save Access Token for Calendar API
      if (accessToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('google_access_token', accessToken);
      }

      // 7. Exchange Google ID Token for Firebase Token via REST
      final firebaseResponse = await http.post(
        Uri.parse(_idpUrl),
        body: json.encode({
          'postBody': 'id_token=$idToken&providerId=google.com',
          'requestUri': 'http://localhost',
          'returnIdpCredential': true,
          'returnSecureToken': true,
        }),
      );

      final firebaseData = json.decode(firebaseResponse.body);

      if (firebaseResponse.statusCode == 200) {
        final firebaseToken = firebaseData['idToken'];
        final userId = firebaseData['localId'];
        final email = firebaseData['email'];
        await _saveSession(firebaseToken, userId, email);
        _startHeartbeat(userId, firebaseToken);
        return null; // Success
      } else {
        return firebaseData['error']['message'] ?? 'Google Sign-In with Firebase failed';
      }

    } catch (e) {
      return 'Google Sign-In Error: $e';
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse(_signInUrl),
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        final token = data['idToken'];
        final userId = data['localId'];
        final email = data['email'];
        await _saveSession(token, userId, email);
        _startHeartbeat(userId, token);
        return null; // Success (no error message)
      } else {
        return data['error']['message'] ?? 'Authentication failed';
      }
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signUp(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse(_signUpUrl),
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        final token = data['idToken'];
        final userId = data['localId'];
        final email = data['email'];
        await _saveSession(token, userId, email);
        _startHeartbeat(userId, token);
        return null; // Success
      } else {
        return data['error']['message'] ?? 'Registration failed';
      }
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    _stopHeartbeat();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_email');
    
    // Optional: Mark as offline before quitting (best effort)
    if (_currentUserId != null && _deviceId != null) {
       final url = '$_dbUrl/users/$_currentUserId/devices/$_deviceId.json?auth=${prefs.getString('auth_token')}';
       try {
         await http.patch(Uri.parse(url), body: json.encode({'state': 'offline'}));
       } catch (_) {}
    }
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

  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_email');
  }

  Future<String?> getGoogleAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_access_token');
  }

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

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
    } catch (e) {
      print('Failed to get devices: $e');
    }
    return {};
  }

  Future<void> _saveSession(String token, String userId, String? email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_user_id', userId);
    if (email != null) {
      await prefs.setString('auth_email', email);
    }
    
    // Generate or retrieve a persistent device ID
    if (!prefs.containsKey('device_id')) {
      await prefs.setString('device_id', 'win_${DateTime.now().millisecondsSinceEpoch}');
    }
    _deviceId = prefs.getString('device_id');
  }

  void _startHeartbeat(String userId, String token) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
       await _saveSession(token, userId, null);
    }

    _stopHeartbeat();
    
    // Send immediate heartbeat
    _sendHeartbeatRequest(userId, token);

    // Repeat every 60 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _sendHeartbeatRequest(userId, token);
    });

    // Start Polling for Session Updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollSession(userId, token);
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollSession(String userId, String token) async {
    final url = '$_dbUrl/users/$userId/focus_session.json?auth=$token';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body);
        if (data != null) {
          _sessionStreamController.add(SessionUpdate(
            isActive: data['isActive'] ?? false,
            endTime: data['endTime'],
            updatedBy: data['updatedBy'],
          ));
        }
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<void> _sendHeartbeatRequest(String userId, String token) async {
    if (_deviceId == null) return;
    
    // Use .json extension for Firebase REST API
    final url = '$_dbUrl/users/$userId/devices/$_deviceId.json?auth=$token';
    
    try {
      await http.patch(
        Uri.parse(url),
        body: json.encode({
          'name': Platform.localHostname, // e.g. "My-PC"
          'type': 'windows',
          'platform': 'Windows ${Platform.operatingSystemVersion}',
          'state': 'online',
          'last_seen': DateTime.now().millisecondsSinceEpoch, // Server-side timestamp would be better, but this is simpler for REST
        }),
      );
    } catch (e) {
      print('Heartbeat failed: $e');
    }
  }

  // --- FOCUS SESSION SYNC ---
  Future<void> updateFocusSession(bool isActive, int? endTimeMillis) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');

    if (token == null || userId == null) return;

    final url = '$_dbUrl/users/$userId/focus_session.json?auth=$token';

    try {
      await http.put( // Use PUT to overwrite/create the session state
        Uri.parse(url),
        body: json.encode({
          'isActive': isActive,
          'endTime': endTimeMillis, // Null if paused/stopped
          'lastUpdatedAt': DateTime.now().millisecondsSinceEpoch,
          'updatedBy': _deviceId ?? 'unknown_windows',
        }),
      );
    } catch (e) {
      print('Failed to sync focus session: $e');
    }
  }

  Future<void> updatePresence(String state) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('auth_user_id');
    final deviceId = prefs.getString('device_id');

    if (token == null || userId == null || deviceId == null) return;

    final url = '$_dbUrl/users/$userId/devices/$deviceId.json?auth=$token';

    try {
      await http.patch(
        Uri.parse(url),
        body: json.encode({
          'state': state,
          'last_seen': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      print('Update presence failed: $e');
    }
  }
}
