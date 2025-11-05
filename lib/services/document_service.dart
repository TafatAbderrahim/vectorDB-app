import 'dart:io';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf_text/pdf_text.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
//import 'package:image/image.dart' as img;

class PdfService {
  /// Extracts text from a PDF file.
  /// Uses pdf_text for normal PDFs, falls back to OCR for scanned PDFs.
  Future<String> extractPdfText(String filePath) async {
    String text = '';
    try {
      final doc = await PDFDoc.fromPath(filePath);
      text = (await doc.text).trim();
    } catch (e) {
      print('pdf_text extraction failed: $e');
    }

    // If text is empty or too short, fallback to OCR
    if (text.length < 5) {
      print('Fallback to OCR...');
      text = await _extractPdfTextWithOcr(filePath);
    }

    return text.trim();
  }

  /// OCR fallback: extract text from each page image
  Future<String> _extractPdfTextWithOcr(String filePath) async {
    // You need to convert PDF pages to images here.
    // This requires a native plugin or external tool (not supported by pure Dart).
    // For demonstration, this is a placeholder.
    // On desktop, you could use 'pdfimages' CLI tool to extract images from PDF.
    // On mobile, use a platform channel or a package that supports PDF to image.

    // Example placeholder for one-page PDF:
    List<File> pageImages = await _convertPdfToImages(filePath);

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String ocrText = '';

    for (var imageFile in pageImages) {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await textRecognizer.processImage(inputImage);
      ocrText += recognizedText.text + '\n\n--- PAGE BREAK ---\n\n';
    }
    await textRecognizer.close();

    return ocrText.trim();
  }

  /// Placeholder: convert PDF pages to images.
  /// Implement this using platform channels or external tools as needed.
  Future<List<File>> _convertPdfToImages(String filePath) async {
    // TODO: Implement PDF to image conversion.
    // For now, return an empty list.
    print('PDF to image conversion not implemented.');
    return [];
  }
}

class DocumentService {
  // Add supported file extensions
  static const supportedExtensions = {
    'pdf': ['pdf'],
    'word': ['doc', 'docx'],
    'excel': ['xls', 'xlsx', 'csv'],
  };

  Future<String?> extractText(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();

    if (supportedExtensions['pdf']!.contains(extension)) {
      return await PdfService().extractPdfText(filePath);
    } else if (supportedExtensions['word']!.contains(extension)) {
      return await extractTextFromDoc(filePath);
    } else if ((filePath.endsWith('.xlsx')) || (filePath.endsWith('.xls'))) {
      return _extractTextFromExcel(filePath);
    } else if (filePath.endsWith('.csv')) {
      return _extractTextFromCsv(filePath);
    }
    return null;
  }

  Future<String?> extractTextFromDoc(String filePath) async {
    try {
      // Run docx2txt command
      final result = await Process.run('docx2txt', [filePath, '-']);

      if (result.exitCode != 0) {
        print('Error running docx2txt: ${result.stderr}');
        return null;
      }

      // Get output as string
      String text = result.stdout as String;

      // Clean up the text
      text = _cleanExtractedText(text);

      // Convert to UTF-8 if needed
      return utf8.decode(utf8.encode(text));
    } catch (e) {
      print('Error extracting text: $e');
      return null;
    }
  }

  String _cleanExtractedText(String text) {
    try {
      // Split at "Text Formatting" and take only the content before it
      final parts = text.split('Text Formatting');
      if (parts.isEmpty) return text.trim();

      // Get the first part (before "Text Formatting")
      String cleanedText = parts[0].trim();

      // Remove any trailing empty lines
      cleanedText = cleanedText.replaceAll(RegExp(r'\n+$'), '');

      // Ensure consistent line endings
      cleanedText = cleanedText.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      return cleanedText;
    } catch (e) {
      print('Error cleaning extracted text: $e');
      return text.trim();
    }
  }

  Future<String?> _extractTextFromExcel(String filePath) async {
    try {
      final bytes = File(filePath).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      List<String> result = [];

      for (var sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        if (sheet.rows.isEmpty) continue;

        final header = sheet.rows.first
            .map((c) => c?.value.toString() ?? "")
            .toList();

        for (var i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];

          List<String> formatted = [];
          for (int j = 0; j < header.length; j++) {
            final val = row.length > j ? row[j]?.value.toString() ?? "" : "";
            formatted.add("${header[j]}: $val");
          }
          result.add(formatted.join(", "));

          // ✅ memory control: flush big chunks
          if (result.length >= 500) {
            result.add("\n--- CHUNK BREAK ---\n");
          }
        }
      }

      return result.join("\n");
    } catch (e) {
      print("Excel Error: $e");
      return null;
    }
  }

  Future<String?> _extractTextFromCsv(String filePath) async {
    try {
      final stream = File(filePath)
          .openRead()
          .transform(utf8.decoder)
          .transform(const CsvToListConverter());

      List<String>? header;
      List<String> result = [];

      await for (final row in stream) {
        if (header == null) {
          header = row.map((e) => e.toString()).toList();
        } else {
          List<String> formatted = [];
          for (int i = 0; i < row.length; i++) {
            formatted.add("${header![i]}: ${row[i]}");
          }
          result.add(formatted.join(", "));
        }

        // ✅ Safety limit: avoid huge single payload in memory
        if (result.length >= 500) {
          result.add("\n--- CHUNK BREAK ---\n");
        }
      }

      return result.join("\n");
    } catch (e) {
      print("CSV Error: $e");
      return null;
    }
  }

  Future<bool> validateFile(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();
    for (var type in supportedExtensions.values) {
      if (type.contains(extension)) return true;
    }
    return false;
  }
}
