import 'package:flutter/material.dart';
import '../models/news_item_model.dart';
import '../services/news_service.dart';
import 'news_detail_screen.dart';
import '../widgets/news_card.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({Key? key}) : super(key: key);

  static const routeName = '/news';

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final NewsService _newsService = NewsService();
  List<NewsItem> _newsItems = [];
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  bool _displayAsGrid = true;
  bool _loadWithDetails = false;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _errorMessage = '';
    });

    try {
      final List<NewsItem> newsItems = await _newsService.getLatestNews();
      
      if (mounted) {
        setState(() {
          _newsItems = newsItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _newsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualités'),
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.blue[900],
        actions: [
          IconButton(
            icon: Icon(_displayAsGrid ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _displayAsGrid = !_displayAsGrid;
              });
            },
            tooltip: _displayAsGrid ? 'Afficher en liste' : 'Afficher en grille',
          ),
          IconButton(
            icon: Icon(_loadWithDetails ? Icons.details : Icons.list),
            onPressed: () {
              setState(() {
                _loadWithDetails = !_loadWithDetails;
              });
              _loadNews();
            },
            tooltip: _loadWithDetails ? 'Désactiver détails' : 'Activer détails',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNews,
        child: _buildBody(isDarkMode),
      ),
    );
  }

  Widget _buildBody(bool isDarkMode) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.white : Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chargement des actualités...',
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (_isError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: isDarkMode ? Colors.red[300] : Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Erreur lors du chargement des actualités',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadNews,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_newsItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: isDarkMode ? Colors.white54 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune actualité disponible',
              style: TextStyle(
                fontSize: 18,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadNews,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return _displayAsGrid
        ? _buildGridView(isDarkMode)
        : _buildListView(isDarkMode);
  }

  Widget _buildGridView(bool isDarkMode) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _newsItems.length,
      itemBuilder: (context, index) {
        return NewsCard(
          newsItem: _newsItems[index],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NewsDetailScreen(newsItem: _newsItems[index]),
              ),
            );
          },
          displayAsGrid: true,
        );
      },
    );
  }

  Widget _buildListView(bool isDarkMode) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsItems.length,
      itemBuilder: (context, index) {
        return NewsCard(
          newsItem: _newsItems[index],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NewsDetailScreen(newsItem: _newsItems[index]),
              ),
            );
          },
          displayAsGrid: false,
        );
      },
    );
  }
}
