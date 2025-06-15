import 'package:flutter/material.dart';
import '../services/qa_service.dart';
import '../utils/config.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final QAService qaService = QAService(baseUrl: baseUrl);
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Recherche de documents FSST')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      prefixIcon: Icon(Icons.search),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _performSearch,
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _performSearch(_searchController.text),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Rechercher'),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isSearching)
            Center(child: CircularProgressIndicator())
          else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Aucun résultat trouvé',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final document = _searchResults[index];
                  return Card(
                    margin: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.article, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Document ${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.0,
                                ),
                              ),
                            ],
                          ),
                          Divider(),
                          SizedBox(height: 8.0),
                          Text(
                            document['content'] ?? 'Contenu non disponible',
                            style: TextStyle(fontSize: 14),
                          ),
                          SizedBox(height: 12.0),
                          if (document['metadata'] != null)
                            Row(
                              children: [
                                Icon(
                                  Icons.source,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Source: ${document['metadata']['source'] ?? 'Inconnue'}',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await qaService.searchDocuments(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la recherche: $e')),
      );
    }
  }
}
