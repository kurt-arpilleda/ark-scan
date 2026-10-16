import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AutoUpdate {
  static const List<String> apiUrls = [
    "http://192.168.254.163/",
    "http://192.168.1.213/",
    "http://113.19.11.218/",
    "http://220.157.175.232/",
  ];

  static const String versionPath = "V4/Others/Kurt/LatestVersionAPK/ArkScan/version.json";
  static const String apkPathPrefix = "V4/Others/Kurt/LatestVersionAPK/ArkScan/";

  static const Duration requestTimeout = Duration(seconds: 3);
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  static bool isUpdating = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    if (isUpdating) {
      return;
    }
    isUpdating = true;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final String? fastestUrl = await _findFastestWorkingUrl();

      if (fastestUrl != null) {
        try {
          final response = await http.get(Uri.parse("$fastestUrl$versionPath")).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final Map<String, dynamic> versionInfo = jsonDecode(response.body);
            final int latestVersionCode = versionInfo["versionCode"];
            final String latestVersionName = versionInfo["versionName"];
            final String releaseNotes = versionInfo["releaseNotes"];
            final String apkFileName = versionInfo["apk"];

            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            int currentVersionCode = int.parse(packageInfo.buildNumber);

            if (latestVersionCode > currentVersionCode) {
              await _showAutomaticUpdateDialog(
                  context,
                  latestVersionName,
                  releaseNotes,
                  fastestUrl,
                  apkFileName
              );
              isUpdating = false;
              return;
            } else {
              isUpdating = false;
              return;
            }
          }
        } catch (e) {
          print("Error checking for update from $fastestUrl on attempt $attempt: $e");
        }
      }

      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }

    Fluttertoast.showToast(msg: "Failed to check for updates after $maxRetries attempts.");
    isUpdating = false;
  }

  static Future<String?> _findFastestWorkingUrl() async {
    final Completer<String> completer = Completer<String>();
    int completedRequests = 0;
    bool foundResult = false;

    for (String url in apiUrls) {
      _testUrl(url).then((bool isWorking) {
        completedRequests++;

        if (isWorking && !foundResult) {
          foundResult = true;
          if (!completer.isCompleted) {
            completer.complete(url);
            print("✅ Using update server: $url");
          }
        }

        if (completedRequests == apiUrls.length && !foundResult) {
          if (!completer.isCompleted) {
            completer.complete("");
          }
        }
      });
    }

    try {
      final result = await completer.future.timeout(Duration(seconds: 5));
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> _testUrl(String url) async {
    try {
      final response = await http.get(Uri.parse("$url$versionPath")).timeout(requestTimeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<void> _showAutomaticUpdateDialog(
      BuildContext context,
      String versionName,
      String releaseNotes,
      String apiUrl,
      String apkFileName
      ) async {
    await WakelockPlus.enable();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: Text("Updating Application"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("New Version: $versionName"),
                SizedBox(height: 10),
                Text("Release Notes:"),
                Text(releaseNotes),
                SizedBox(height: 20),
                StreamBuilder<int>(
                  stream: _downloadAndInstallApk(context, apiUrl, apkFileName),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      if (snapshot.data! == 100) {
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: 1.0,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                            SizedBox(height: 10),
                            Text("Installation in progress..."),
                          ],
                        );
                      } else if (snapshot.data! == -1) {
                        return Column(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 40),
                            SizedBox(height: 10),
                            Text("Update failed. Retrying..."),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: snapshot.data! / 100,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                            SizedBox(height: 10),
                            Text("${snapshot.data}% Downloaded"),
                          ],
                        );
                      }
                    } else {
                      return Column(
                        children: [
                          LinearProgressIndicator(
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                          SizedBox(height: 10),
                          Text("Preparing download..."),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    await WakelockPlus.disable();
  }

  static Stream<int> _downloadAndInstallApk(
      BuildContext context,
      String apiUrl,
      String apkFileName
      ) async* {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final String apkFilePath = "${externalDir.path}/$apkFileName";
          final File apkFile = File(apkFilePath);

          final request = http.Request('GET', Uri.parse("$apiUrl$apkPathPrefix$apkFileName"));
          final http.StreamedResponse response = await request.send().timeout(Duration(seconds: 30));

          if (response.statusCode == 200) {
            int totalBytes = response.contentLength ?? 0;
            int downloadedBytes = 0;

            yield 0;

            final fileSink = apkFile.openWrite();
            await for (var chunk in response.stream) {
              downloadedBytes += chunk.length;
              fileSink.add(chunk);
              int progress = totalBytes > 0 ? ((downloadedBytes / totalBytes) * 100).round() : 0;
              yield progress;
            }
            await fileSink.close();

            if (await apkFile.exists()) {
              yield 100;
              await _installApk(context, apkFilePath);
              return;
            } else {
              yield -1;
              Fluttertoast.showToast(msg: "Failed to save the APK file.");
            }
          }
        }
      } catch (e) {
        print("Error downloading APK on attempt $attempt: $e");
        yield -1;
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }
    Fluttertoast.showToast(msg: "Failed to download update after $maxRetries attempts.");
  }

  static Future<void> _installApk(BuildContext context, String apkPath) async {
    try {
      if (await Permission.requestInstallPackages.isGranted) {
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
          await Future.delayed(Duration(seconds: 2));
          await checkForUpdate(context);
        }
      } else {
        final status = await Permission.requestInstallPackages.request();
        if (status.isGranted) {
          final result = await OpenFile.open(apkPath);
          if (result.type != ResultType.done) {
            Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
            await Future.delayed(Duration(seconds: 2));
            await checkForUpdate(context);
          }
        } else {
          Fluttertoast.showToast(msg: "Installation permission denied. Retrying...");
          await Future.delayed(Duration(seconds: 2));
          await checkForUpdate(context);
        }
      }
    } catch (e) {
      print("Error installing APK: $e");
      Fluttertoast.showToast(msg: "Failed to install update. Retrying...");
      await Future.delayed(Duration(seconds: 2));
      await checkForUpdate(context);
    } finally {
      isUpdating = false;
    }
  }
}
