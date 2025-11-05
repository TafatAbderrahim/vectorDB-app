import 'package:http/http.dart' as http;
import 'dart:convert';

class BackendService {
  final String baseUrl;

  BackendService({this.baseUrl = 'http://127.0.0.1:8000'});

  Future<bool> addDocument({required String filePath}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'file_path': filePath}),
      );

      if (response.statusCode != 200) {
        print('Error adding document: ${response.statusCode} ${response.body}');
        return false;
      }
      return true;
    } catch (e) {
      print('Error adding document: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> searchSimilar(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search?query=${Uri.encodeComponent(query)}'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final matches = data['matches'] as List;
      // Sort by distance (least to most)
      matches.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
      );

      return matches
          .map<Map<String, dynamic>>(
            (match) => {
              'id': match['id'],
              'text': match['text'],
              'distance': match['distance'],
            },
          )
          .toList();
    } catch (e) {
      print('Error searching: $e');
      return [];
    }
  }

  Future<bool> deleteDocument(String id) async {
    if (id.trim().isEmpty) return false;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting document: $e');
      return false;
    }
  }

  Future<bool> dropDatabase() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/drop'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error dropping database: $e');
      return false;
    }
  }

  Future<int> countDocuments() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/count'));
      if (response.statusCode != 200) return 0;
      final data = jsonDecode(response.body);
      return data['count'] ?? 0;
    } catch (e) {
      print('Error counting documents: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getAllDocuments() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/all'));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final docs = data['documents'] as List;
      return docs
          .map<Map<String, dynamic>>(
            (doc) => {'id': doc['id'], 'text': doc['text']},
          )
          .toList();
    } catch (e) {
      print('Error fetching all documents: $e');
      return [];
    }
  }
}
