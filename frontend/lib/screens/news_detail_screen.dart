import 'package:flutter/material.dart';
import '../models/news_item_model.dart';
import '../services/news_detail_service.dart';
import '../widgets/loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart' as open_file;
import 'package:path_provider/path_provider.dart';

class NewsDetailScreen extends StatefulWidget {
  final NewsItem newsItem;

  const NewsDetailScreen({Key? key, required this.newsItem}) : super(key: key);

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final NewsDetailService _newsDetailService = NewsDetailService();
  bool _isLoading = true;
  NewsItem _detailedNews = NewsItem(
    title: '',
    content: '',
    date: '',
    imageUrl: '',
    category: '',
    link: '',
  );
  Map<String, String> _downloadedFiles = {};
  Map<String, bool> _fileDownloading = {};

  @override
  void initState() {
    super.initState();
    _loadNewsDetails();
  }

  String safeDecodeFilename(String input) {
    try {
      return Uri.decodeComponent(input);
    } catch (e) {
         String sanitized = input.replaceAll(RegExp(r'%(?![0-9A-Fa-f]{2})'), '%25');
      
      try {
        return Uri.decodeComponent(sanitized);
      } catch (e) {
        print('Could not decode filename: $input');
        return input;
      }
    }
  }

  Future<void> _loadNewsDetails() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (widget.newsItem.link.isNotEmpty) {
        final detailedNews = await _newsDetailService.getNewsDetails(widget.newsItem.link);
        
        final mergedNews = detailedNews.copyWith(
          title: detailedNews.title.isNotEmpty ? detailedNews.title : widget.newsItem.title,
          date: detailedNews.date.isNotEmpty ? detailedNews.date : widget.newsItem.date,
          imageUrl: detailedNews.imageUrl.isNotEmpty ? detailedNews.imageUrl : widget.newsItem.imageUrl,
          category: detailedNews.category.isNotEmpty ? detailedNews.category : widget.newsItem.category,
        );
        
        if (mounted) {
          setState(() {
            _detailedNews = mergedNews;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _detailedNews = widget.newsItem;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Erreur lors du chargement des détails: $e');
      if (mounted) {
        setState(() {
          _detailedNews = widget.newsItem;
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de charger les détails complets: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenFile(String url) async {
    if (_fileDownloading[url] == true) {
      return;
    }
    
    try {
      if (mounted) {
        setState(() {
          _fileDownloading[url] = true;
        });
      }
      
      if (_downloadedFiles.containsKey(url)) {
        await _openFile(_downloadedFiles[url]!);
        return;
      }
      
      final filePath = await _newsDetailService.downloadPdf(url);
      
      if (mounted) {
        setState(() {
          _downloadedFiles[url] = filePath;
          _fileDownloading[url] = false;
        });
      }
      
      await _openFile(filePath);
    } catch (e) {
      print('Erreur de téléchargement: $e');
      if (mounted) {
        setState(() {
          _fileDownloading[url] = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du téléchargement: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    try {
      final result = await open_file.OpenFile.open(filePath);
      if (result.type != open_file.ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible d\'ouvrir le fichier: ${result.message}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur lors de l\'ouverture du fichier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'ouverture du fichier: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible d\'ouvrir: $url'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur d\'ouverture d\'URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _newsDetailService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final newsItem = _isLoading ? widget.newsItem : _detailedNews;

    return Scaffold(
      body: _isLoading 
          ? const Center(child: LoadingIndicator(message: 'Chargement des détails...'))
          : _buildDetailContent(context, newsItem, isDarkMode),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: isDarkMode ? Colors.indigo[400] : Colors.indigoAccent,
        child: const Icon(Icons.arrow_back),
        tooltip: 'Retour',
      ),
    );
  }

  Widget _buildDetailContent(BuildContext context, NewsItem newsItem, bool isDarkMode) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200.0,
          floating: false,
          pinned: true,
          backgroundColor: isDarkMode ? Colors.grey[850] : Colors.blue[900],
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              newsItem.title,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: newsItem.imageUrl.isNotEmpty
                ? Image.network(
                    newsItem.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: isDarkMode ? Colors.grey[700] : Colors.blue[200],
                        child: const Center(child: Icon(Icons.image_not_supported, size: 50, color: Colors.white54)),
                      );
                    },
                  )
                : Container(
                    color: isDarkMode ? Colors.grey[700] : Colors.blue[200],
                    child: const Center(child: Icon(Icons.photo, size: 50, color: Colors.white54)),
                  ),
          ),
        ),
        
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  newsItem.title,
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 12.0),
                
                Card(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        if (newsItem.date.isNotEmpty) ...[
                          Icon(
                            Icons.calendar_today,
                            size: 16.0,
                            color: isDarkMode ? Colors.white70 : Colors.grey[700],
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            newsItem.date,
                            style: TextStyle(
                              fontSize: 14.0,
                              color: isDarkMode ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                        ],
                        const SizedBox(width: 16.0),
                        if (newsItem.category.isNotEmpty) ...[
                          Icon(
                            Icons.category,
                            size: 16.0,
                            color: isDarkMode ? Colors.white70 : Colors.grey[700],
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            newsItem.category,
                            style: TextStyle(
                              fontSize: 14.0,
                              color: isDarkMode ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24.0),
                
                if (newsItem.content.isNotEmpty)
                  Text(
                    newsItem.content,
                    style: TextStyle(
                      fontSize: 16.0,
                      height: 1.5,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: isDarkMode ? Colors.white54 : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Contenu non disponible',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode ? Colors.white70 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                if (newsItem.link.isNotEmpty) ...[
                  const SizedBox(height: 24.0),
                  const Divider(),
                  const SizedBox(height: 16.0),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Voir la source originale'),
                    onPressed: () => _launchUrl(newsItem.link),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
                
                if (newsItem.downloadLinks.isNotEmpty) ...[
                  const SizedBox(height: 24.0),
                  Text(
                    'Documents à télécharger',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  ...newsItem.downloadLinks.map((link) {
                    final filename = link.split('/').last;
                    final extension = filename.split('.').last.toLowerCase();
                    
                    IconData icon;
                    switch (extension) {
                      case 'pdf':
                        icon = Icons.picture_as_pdf;
                        break;
                      case 'doc':
                      case 'docx':
                        icon = Icons.description;
                        break;
                      case 'xls':
                      case 'xlsx':
                        icon = Icons.table_chart;
                        break;
                      case 'jpg':
                      case 'jpeg':
                      case 'png':
                        icon = Icons.image;
                        break;
                      default:
                        icon = Icons.insert_drive_file;
                    }
                    
                    final isDownloading = _fileDownloading[link] == true;
                    final isDownloaded = _downloadedFiles.containsKey(link);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        leading: Icon(icon, color: Theme.of(context).primaryColor),
                        title: Text(
                          safeDecodeFilename(filename), 
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: isDownloaded 
                            ? Text('Téléchargé') 
                            : null,
                        trailing: isDownloading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(isDownloaded ? Icons.open_in_new : Icons.download),
                        onTap: isDownloading 
                            ? null 
                            : () => _downloadAndOpenFile(link),
                      ),
                    );
                  }).toList(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}