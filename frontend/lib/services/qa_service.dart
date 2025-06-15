import 'dart:convert';
import 'package:http/http.dart' as http;

class QAService {
  final String baseUrl;

  QAService({required this.baseUrl});

  Future<String> askQuestion(String question) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/question'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': question}),
          )
          .timeout(
            Duration(seconds: 120),
            onTimeout: () {
              throw Exception('Délai d\'attente dépassé');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String answer = data['answer'];
        return answer;
      } else {
        throw Exception('Erreur API: ${response.statusCode}');
      }
    } catch (e) {
      return 'Erreur lors de la communication avec le serveur: $e';
    }
  }

  Future<List<Map<String, dynamic>>> searchDocuments(
    String query, {
    int topK = 5,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'top_k': topK}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['documents']);
      } else {
        throw Exception('Erreur API: ${response.statusCode}');
      }
    } catch (e) {
      print('Erreur lors de la recherche: $e');
      return [];
    }
  }

  Future<bool> clearMemory() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/clear-memory'),
        headers: {'Content-Type': 'application/json'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erreur lors de l\'effacement de la mémoire: $e');
      return false;
    }
  }
}
