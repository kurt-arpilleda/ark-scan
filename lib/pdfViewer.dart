import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PDFViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String fileName;
  final int languageFlag;
  final bool shouldDeleteOnClose;

  const PDFViewerScreen({
    Key? key,
    required this.pdfUrl,
    required this.fileName,
    required this.languageFlag,
    this.shouldDeleteOnClose = false,
  }) : super(key: key);

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> with WidgetsBindingObserver {
  String? localPath;
  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  double downloadProgress = 0.0;
  DateTime? remoteLastModified;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadPdf();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deletePdfOnExit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _deletePdfOnExit();
    }
  }

  Future<void> loadPdf() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.fileName}');

      final headResponse = await http.head(Uri.parse(widget.pdfUrl));
      if (headResponse.statusCode != 200) {
        throw Exception('Failed to check PDF: ${headResponse.statusCode}');
      }

      final lastModifiedHeader = headResponse.headers['last-modified'];
      remoteLastModified = lastModifiedHeader != null
          ? HttpDate.parse(lastModifiedHeader)
          : null;

      bool shouldDownload = true;
      if (await file.exists()) {
        final localLastModified = await file.lastModified();
        shouldDownload = remoteLastModified != null &&
            localLastModified.isBefore(remoteLastModified!);
      }

      if (shouldDownload) {
        final request = await http.Client().send(http.Request('GET', Uri.parse(widget.pdfUrl)));

        final contentLength = request.contentLength ?? 0;
        final List<int> bytes = [];
        int received = 0;

        await for (var chunk in request.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (contentLength != 0) {
            setState(() {
              downloadProgress = received / contentLength;
            });
          }
        }

        await file.writeAsBytes(bytes);
        if (remoteLastModified != null) {
          await file.setLastModified(remoteLastModified!);
        }
      }

      setState(() {
        localPath = file.path;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isError = true;
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _deletePdfOnExit() async {
    if (_isExiting || !widget.shouldDeleteOnClose || localPath == null) return;

    _isExiting = true;
    try {
      final file = File(localPath!);
      if (await file.exists()) {
        await file.delete();
        debugPrint('PDF deleted on exit');
      }
    } catch (e) {
      debugPrint('Error deleting PDF on exit: $e');
    } finally {
      _isExiting = false;
    }
  }

  Future<bool> _onWillPop() async {
    await _deletePdfOnExit();
    return true; // Allow navigation
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF2053B3),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              await _deletePdfOnExit();
              if (mounted) Navigator.of(context).pop();
            },
          ),
          title: Text(
            widget.fileName.toLowerCase().contains('manual')
                ? (widget.languageFlag == 2 ? '手引き' : 'Manual')
                : widget.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              overflow: TextOverflow.ellipsis,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: isLoading
            ? buildLoading()
            : isError
            ? Center(child: Text('Error: $errorMessage'))
            : PDFView(
          filePath: localPath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: false,
          pageSnap: false,
          onError: (error) => debugPrint(error.toString()),
          onPageError: (page, error) => debugPrint('$page: ${error.toString()}'),
        ),
      ),
    );
  }

  Widget buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (downloadProgress > 0) ...[
              Text(
                remoteLastModified != null
                    ? (widget.languageFlag == 2 ? 'ドキュメントを更新中...' : 'Updating document...')
                    : (widget.languageFlag == 2 ? 'ダウンロード中...' : 'Downloading...'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2053B3),
                ),
              ),
              const SizedBox(height: 24),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: downloadProgress,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2053B3)),
                    ),
                  ),
                  Text(
                    '${(downloadProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2053B3)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Preparing document...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}