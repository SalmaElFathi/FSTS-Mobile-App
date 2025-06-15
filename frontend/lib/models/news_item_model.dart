class NewsItem {
  String title;
  String content;
  String date;
  String imageUrl;
  String category;
  String link;
  List<String> downloadLinks;

  NewsItem({
    required this.title,
    required this.content,
    required this.date,
    required this.imageUrl,
    required this.category,
    required this.link,
    this.downloadLinks = const [],
  });
  
  NewsItem copyWith({
    String? title,
    String? content,
    String? date,
    String? imageUrl,
    String? category,
    String? link,
    List<String>? downloadLinks,
  }) {
    return NewsItem(
      title: title ?? this.title,
      content: content ?? this.content,
      date: date ?? this.date,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      link: link ?? this.link,
      downloadLinks: downloadLinks ?? this.downloadLinks,
    );
  }
  
  NewsItem mergeWith(NewsItem other) {
    return NewsItem(
      title: other.title.isNotEmpty ? other.title : this.title,
      content: other.content.isNotEmpty ? other.content : this.content,
      date: other.date.isNotEmpty ? other.date : this.date,
      imageUrl: other.imageUrl.isNotEmpty ? other.imageUrl : this.imageUrl,
      category: other.category.isNotEmpty ? other.category : this.category,
      link: other.link.isNotEmpty ? other.link : this.link,
      downloadLinks: other.downloadLinks.isNotEmpty ? other.downloadLinks : this.downloadLinks,
    );
  }
}