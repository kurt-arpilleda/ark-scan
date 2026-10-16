import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiServiceJP {
  static const List<String> apiUrls = [
    "https://192.168.1.213/",
    "https://220.157.175.232/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  int? _lastWorkingServerIndex;
  late http.Client httpClient;
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  ApiServiceJP() {
    httpClient = _createHttpClient();
  }

  http.Client _createHttpClient() {
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(client);
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
    );
  }

  Future<T> _makeParallelRequest<T>(Future<_ApiResult<T>> Function(String apiUrl) requestFn) async {
    if (_lastWorkingServerIndex != null) {
      try {
        return (await requestFn(apiUrls[_lastWorkingServerIndex!]).timeout(requestTimeout)).value;
      } catch (_) {
        // fallback to parallel below
      }
    }

    final List<Future<_ApiResult<T>?>> futures = apiUrls.map((apiUrl) async {
      try {
        final result = await requestFn(apiUrl).timeout(requestTimeout);
        return result;
      } catch (e) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);

    for (final result in results) {
      if (result != null) {
        _lastWorkingServerIndex = apiUrls.indexOf(result.apiUrlUsed);
        return result.value;
      }
    }

    throw Exception("All API URLs are unreachable");
  }

  Future<String> fetchSoftwareLink(int linkID) async {
    String? deviceId = await UniqueIdentifier.serial;
    if (deviceId == null) {
      throw Exception("Unable to get device ID");
    }

    final deviceResponse = await checkDeviceId(deviceId);
    if (!deviceResponse['success']) {
      throw Exception("Device not registered or no ID number associated");
    }
    String? idNumber = deviceResponse['idNumber'];

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchLink.php?linkID=$linkID");
          print("Trying: $uri");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("softwareLink")) {
              String relativePath = data["softwareLink"];
              String fullUrl = Uri.parse(apiUrl).resolve(relativePath).toString();
              if (idNumber != null) {
                fullUrl += "?idNumber=$idNumber";
              }
              return _ApiResult(fullUrl, apiUrl);
            } else {
              throw Exception(data["error"] ?? "Invalid response format");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting ${delay.inSeconds} seconds before retry...");
          await Future.delayed(delay);
        }
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }

  Future<bool> checkIdNumber(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkIdNumber.php");
          print("Trying: $uri");
          final response = await httpClient.post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"idNumber": idNumber}),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(true, apiUrl);
            } else {
              throw Exception(data["message"] ?? "ID check failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchProfile.php?idNumber=$idNumber");
          print("Trying: $uri");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Profile fetch failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<void> updateLanguageFlag(String idNumber, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_updateLanguage.php");
          print("Trying: $uri");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              'languageFlag': languageFlag.toString(),
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(null, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Update failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });
        return;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> checkDeviceId(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkDeviceId.php?deviceID=$deviceId");
          print("Trying: $uri");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['idNumber'] != null) {
              final prefs = await _prefs;
              await prefs.setString('IDNumber', data['idNumber']);
            }
            return _ApiResult(data, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<String> fetchManualLink(int linkID, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchManualLink.php?linkID=$linkID");
          print("Trying: $uri");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("manualLinkPH") && data.containsKey("manualLinkJP")) {
              String relativePath = languageFlag == 1 ? data["manualLinkPH"] : data["manualLinkJP"];
              if (relativePath.isEmpty) {
                throw Exception("No manual available for selected language");
              }
              return _ApiResult(Uri.parse(apiUrl).resolve(relativePath).toString(), apiUrl);
            } else {
              throw Exception(data["error"] ?? "Invalid manual link format");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }
  static void setupHttpOverrides() {
    HttpOverrides.global = MyHttpOverrides();
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class _ApiResult<T> {
  final T value;
  final String apiUrlUsed;

  _ApiResult(this.value, this.apiUrlUsed);
}
