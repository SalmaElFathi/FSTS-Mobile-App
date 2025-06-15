import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import '../models/news_item_model.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math';
class NewsDetailService {
  static const String fstUrl = 'https://www.fsts.ac.ma';
  final http.Client _httpClient;

  NewsDetailService({http.Client? client}) : _httpClient = client ?? http.Client();

  Future<NewsItem> getNewsDetails(String newsUrl) async {
    try {
      print('NewsDetailService: Chargement des détails depuis $newsUrl');
      
      if (!newsUrl.startsWith('http')) {
        newsUrl = '$fstUrl$newsUrl';
      }
      
      final response = await _httpClient.get(Uri.parse(newsUrl));
      print('NewsDetailService: Réponse HTTP: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        print('NewsDetailService: HTML parsé avec succès');
        
        var contentDiv = _findContentDiv(document);
        
        if (contentDiv == null) {
          print('NewsDetailService: Aucun contenu trouvé');
          throw Exception('Contenu non trouvé sur la page');
        }
        
        final title = _extractTitle(document, contentDiv);
        final content = _extractContent(contentDiv);
        final downloadLinks = _extractDownloadLinks(contentDiv, newsUrl);
        
        return NewsItem(
          title: title.isNotEmpty ? title : 'Actualité FST',
          content: content.isNotEmpty ? content : 'Contenu non disponible',
          date: '', 
          imageUrl: '',
          category: 'Actualités',
          link: newsUrl,
          downloadLinks: downloadLinks,
        );
      } else {
        print('NewsDetailService: Erreur HTTP ${response.statusCode}');
        throw Exception('Erreur HTTP ${response.statusCode} lors du chargement des détails');
      }
    } catch (e) {
      print('NewsDetailService: Erreur lors de l\'extraction des détails: $e');
      rethrow;
    }
  }

  Element? _findContentDiv(Document document) {
    final selectors = [
      'div.details__content',
      'div.blog-details-wrap',
      'div.content',
      'div.post-content',
      'div.entry-content',
      'div.article-content',
      'div.news-content',
      'article',
      'main'
    ];
    
    for (var selector in selectors) {
      var element = document.querySelector(selector);
      if (element != null) {
        print('NewsDetailService: Contenu trouvé avec sélecteur: $selector');
        return element;
      }
    }
    
    var generalSelectors = [
      'div[class*="content"]',
      'div[class*="article"]',
      'div[class*="blog"]',
      'div[class*="news"]',
      'div[class*="post"]'
    ];
    
    for (var selector in generalSelectors) {
      var elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        Element largestElement = elements.first;
        int maxLength = largestElement.text.length;
        
        for (var element in elements) {
          if (element.text.length > maxLength) {
            maxLength = element.text.length;
            largestElement = element;
          }
        }
        
        print('NewsDetailService: Contenu trouvé avec sélecteur général: $selector');
        return largestElement;
      }
    }
    
    return document.body;
  }

  String _extractTitle(Document document, Element contentDiv) {
    for (var tagName in ['h1', 'h2', 'h3']) {
      var elements = contentDiv.querySelectorAll(tagName);
      for (var element in elements) {
        var text = element.text.trim();
        if (text.isNotEmpty && text.length > 10) {
          print('NewsDetailService: Titre trouvé dans $tagName: "$text"');
          return text;
        }
      }
    }
    
    for (var tagName in ['h1', 'h2', 'h3']) {
      var elements = document.querySelectorAll(tagName);
      for (var element in elements) {
        var text = element.text.trim();
        if (text.isNotEmpty && text.length > 10) {
          print('NewsDetailService: Titre trouvé dans document.$tagName: "$text"');
          return text;
        }
      }
    }
    
    var metaTitleElement = document.querySelector('meta[property="og:title"]') ??
                          document.querySelector('meta[name="title"]');
    
    if (metaTitleElement != null) {
      var content = metaTitleElement.attributes['content'];
      if (content != null && content.isNotEmpty) {
        print('NewsDetailService: Titre trouvé dans meta: "$content"');
        return content;
      }
    }
    
    var titleElement = document.querySelector('title');
    if (titleElement != null) {
      var text = titleElement.text.trim();
      if (text.isNotEmpty) {
        print('NewsDetailService: Titre trouvé dans title: "$text"');
        return text;
      }
    }
    
    print('NewsDetailService: Aucun titre trouvé');
    return '';
  }

  String _extractContent(Element contentDiv) {
    var content = '';
    
    var paragraphs = contentDiv.querySelectorAll('p');
    if (paragraphs.isNotEmpty) {
      for (var p in paragraphs) {
        var text = p.text.trim();
        if (text.isNotEmpty) {
          content += text + '\n\n';
        }
      }
    } else {
      var divs = contentDiv.querySelectorAll('div');
      for (var div in divs) {
        var text = div.text.trim();
        if (text.isNotEmpty && text.length > 50 && text.length < 1000) {
          content += text + '\n\n';
        }
      }
      
      if (content.isEmpty) {
        content = contentDiv.text.trim();
      }
    }
    
    return content.trim();
  }

  List<String> _extractDownloadLinks(Element contentDiv, String baseUrl) {
    List<String> downloadLinks = [];
    
    var links = contentDiv.querySelectorAll('a');
    
    for (var link in links) {
      var href = link.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        if (href.toLowerCase().endsWith('.pdf') || 
            href.toLowerCase().endsWith('.doc') || 
            href.toLowerCase().endsWith('.docx') || 
            href.toLowerCase().endsWith('.xls') || 
            href.toLowerCase().endsWith('.xlsx') || 
            href.toLowerCase().endsWith('.zip') ||
            href.toLowerCase().contains('download') ||
            href.toLowerCase().contains('telecharger')) {
          
          if (!href.startsWith('http')) {
            if (href.startsWith('/')) {
              href = '$fstUrl$href';
            } else {
              var uri = Uri.parse(baseUrl);
              var basePathSegments = uri.pathSegments;
              if (basePathSegments.isNotEmpty) {
                basePathSegments = basePathSegments.sublist(0, basePathSegments.length - 1);
              }
              var basePath = basePathSegments.join('/');
              href = '$fstUrl/$basePath/$href';
            }
          }
          
          if (!downloadLinks.contains(href)) {
            downloadLinks.add(href);
          }
        }
      }
    }
    
    print('NewsDetailService: ${downloadLinks.length} liens de téléchargement trouvés');
    return downloadLinks;
  }

  Future<String> downloadPdf(String url) async {
    try {
      final response = await _httpClient.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        
        final filename = url.split('/').last;
        final filePath = '${tempDir.path}/$filename';
        
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        
        return filePath;
      } else {
        throw Exception('Erreur HTTP ${response.statusCode} lors du téléchargement');
      }
    } catch (e) {
      print('Error downloading PDF: $e');
      throw Exception('Erreur lors du téléchargement du fichier');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}