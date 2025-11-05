import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vector_app/widgets/text_display_widget.dart';
import 'services/backend_service.dart';
import 'services/document_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Search',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Document Search'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _backendService = BackendService();
  final _documentService = DocumentService();
  final _searchController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>>? _searchResults;

  Future<void> _pickAndConvertFile() async {
    try {
      setState(() => _isLoading = true);

      // Show file type selection dialog
      final fileType = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select File Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('PDF Document'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Word Document'),
                onTap: () => Navigator.pop(context, 'word'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('Excel Document'),
                onTap: () => Navigator.pop(context, 'excel'),
              ),
            ],
          ),
        ),
      );

      if (fileType == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Pick file with correct extensions
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: DocumentService.supportedExtensions[fileType]!,
      );

      if (result != null) {
        final filePath = result.files.single.path;
        if (filePath == null) throw Exception('Could not get file path');

        // Add to database
        final success = await _backendService.addDocument(filePath: filePath);
        if (!success) throw Exception('Failed to add document to database');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document added successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchDocuments() async {
    if (_searchController.text.isEmpty) return;

    try {
      setState(() => _isLoading = true);
      final results = await _backendService.searchSimilar(
        _searchController.text,
      );
      setState(() => _searchResults = results);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search error: ${e.toString()}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildSearchResults() {
    if (_searchResults == null) return const SizedBox.shrink();
    return Expanded(
      child: ListView.builder(
        itemCount: _searchResults!.length,
        itemBuilder: (context, index) {
          final result = _searchResults![index];
          return TextDisplayWidget(text: result['text']);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              final success = await _backendService.dropDatabase();
              if (success) {
                setState(() {
                  _searchResults = null;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Database cleared')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search documents...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchDocuments,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_searchResults != null && _searchResults!.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _searchResults!.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults![index];
                    return TextDisplayWidget(text: result['text']);
                  },
                ),
              )
            else
              const Center(
                child: Text('Upload documents or search for similar content'),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndConvertFile,
        tooltip: 'Upload Document',
        child: const Icon(Icons.file_upload),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
