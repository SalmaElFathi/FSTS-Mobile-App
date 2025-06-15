import 'package:flutter/material.dart';
import '../models/news_item_model.dart';
import '../screens/news_detail_screen.dart';

class NewsCard extends StatelessWidget {
  final NewsItem newsItem;
  final VoidCallback onTap;
  final bool displayAsGrid;

  const NewsCard({
    Key? key,
    required this.newsItem,
    required this.onTap,
    this.displayAsGrid = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (displayAsGrid) {
      return _buildGridCard(context, isDarkMode);
    } else {
      return _buildListCard(context, isDarkMode);
    }
  }

  Widget _buildGridCard(BuildContext context, bool isDarkMode) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _navigateToDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildImageWidget(isDarkMode),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    newsItem.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Date and category in a single row with spacer
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 16,
                        color: isDarkMode ? Colors.white70 : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          newsItem.category,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.white70 : Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      if (newsItem.date.isNotEmpty) ...[
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: isDarkMode ? Colors.white70 : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          newsItem.date,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // En savoir plus button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _navigateToDetail(context),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('En savoir plus'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard(BuildContext context, bool isDarkMode) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToDetail(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            SizedBox(
              width: 120,
              height: 120,
              child: _buildImageWidget(isDarkMode),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      newsItem.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Date - only if exists
                    if (newsItem.date.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: isDarkMode ? Colors.white70 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              newsItem.date,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.white70 : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    // Category - only if exists
                    if (newsItem.category.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 14,
                            color: isDarkMode ? Colors.white70 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              newsItem.category,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.white70 : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(bool isDarkMode) {
    if (newsItem.imageUrl.isNotEmpty) {
      return Image.network(
        newsItem.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: isDarkMode ? Colors.grey[700] : Colors.blue[100],
            child: const Center(
              child: Icon(Icons.image_not_supported, color: Colors.white54),
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                    : null,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDarkMode ? Colors.white70 : Colors.blue,
                ),
              ),
            ),
          );
        },
      );
    } else {
      return Container(
        color: isDarkMode ? Colors.grey[800] : Colors.blue[100],
        child: const Center(
          child: Icon(Icons.photo, color: Colors.white54),
        ),
      );
    }
  }

  // Helper method to navigate to detail screen
  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewsDetailScreen(newsItem: newsItem),
      ),
    );
  }
}