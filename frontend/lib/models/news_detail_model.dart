import 'package:html/parser.dart' as parser;

class NewsDetail {
  final String title;
  final String category;
  final String date;
  final String content;
  final List<String> downloadLinks;

  NewsDetail({
    required this.title,
    required this.category,
    required this.date,
    required this.content,
    required this.downloadLinks,
  });

  factory NewsDetail.fromHtml(String html) {
    final document = parser.parse(html);
    
    final titleElement = document.querySelector('.details__content h2');
    final title = titleElement?.text.trim() ?? 'Sans titre';
    
    final metaInfo = document.querySelector('.meta-info ul');
    final categoryElement = metaInfo?.querySelector('li:has(.fal.fa-box)');
    final category = categoryElement?.text.trim().split(' ').last ?? 'Actualités';
    
    final dateElement = metaInfo?.querySelector('li:has(.fal.fa-calendar-alt)');
    final date = dateElement?.text.trim().split(' ').last ?? 'Date non spécifiée';
    
    final contentElements = document.querySelectorAll('.details__content p');
    final content = contentElements.map((p) => p.text.trim()).join(' ').trim();
    
    final downloadLinks = document.querySelectorAll('.details__content a')
        .map((a) => a.attributes['href'] ?? '')
        .where((url) => url.isNotEmpty && !url.startsWith('#'))
        .toList();
    
    return NewsDetail(
      title: title,
      category: category,
      date: date,
      content: content,
      downloadLinks: downloadLinks,
    );
  }
}
