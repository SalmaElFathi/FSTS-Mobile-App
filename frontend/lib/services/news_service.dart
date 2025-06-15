import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/news_item_model.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

class NewsService {
  static const String fstUrl = 'https://www.fsts.ac.ma';
  final http.Client _httpClient = http.Client();
  
  Future<List<NewsItem>> getLatestNews() async {
    try {
      print('NewsService: Démarrage du chargement des actualités');
      
      final response = await _httpClient.get(Uri.parse('$fstUrl/posts/actualites'));
      
      print('NewsService: Réponse HTTP: ${response.statusCode}');

        if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        print('NewsService: HTML parsé avec succès');
        
        var newsElements = document.querySelectorAll('div.bsingle__post.mb-5');
        print('NewsService: ${newsElements.length} éléments trouvés avec div.bsingle_post.mb-5');
        
        if (newsElements.isEmpty) {
          newsElements = document.querySelectorAll('.bsingle__post-thumb');
          print('NewsService: ${newsElements.length} éléments trouvés avec .bsingle_post-thumb');
        }
        
        if (newsElements.isEmpty) {
          newsElements = document.querySelectorAll('div[class*="bsingle_post"]');
          print('NewsService: ${newsElements.length} éléments trouvés avec div[class*="bsingle_post"]');
        }
        
        if (newsElements.isEmpty) {
          print('NewsService: Aucun élément d\'actualité trouvé');
          throw Exception('Aucun élément d\'actualité trouvé sur la page');
        }
        
        List<NewsItem> newsItems = [];
        
        for (var i = 0; i < newsElements.length; i++) {
          try {
            var element = newsElements[i];
            print('NewsService: Traitement de l\'élément $i');
            
                var thumbElement = element.querySelector('.bsingle__post-thumb') ?? element;
            var imgElement = thumbElement.querySelector('img');
            var imageUrl = imgElement?.attributes['src'] ?? '';
            
            if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
              imageUrl = '$fstUrl$imageUrl';
            }
            print('NewsService: Image URL: $imageUrl');
            
            var adminElement = element.querySelector('.admin') ?? element.querySelector('.bsingle__content');
            
            String title = '';
            String link = '';
            
            var contentLinks = adminElement?.querySelectorAll('a') ?? [];
            for (var linkElement in contentLinks) {
              var href = linkElement.attributes['href'] ?? '';
              var linkText = linkElement.text.trim();
              
              if (linkText.isNotEmpty && 
                  !linkText.contains('En savoir plus') &&
                  !linkText.contains('fa-search')) {
                title = linkText;
                link = href;
                break;
              }
            }
            
            if (title.isEmpty) {
              var headingElements = element.querySelectorAll('h1, h2, h3, h4, h5, h6');
              for (var heading in headingElements) {
                var headingText = heading.text.trim();
                if (headingText.isNotEmpty) {
                  title = headingText;
                  
                  var headingLink = heading.querySelector('a');
                  if (headingLink != null) {
                    link = headingLink.attributes['href'] ?? '';
                  }
                  break;
                }
              }
            }
            
            if (title.isEmpty) {
              var possibleTitleElements = element.querySelectorAll('div, span, p');
              for (var elem in possibleTitleElements) {
                var elemText = elem.text.trim();
                if (elemText.length > 10 && 
                    !elemText.contains('En savoir plus') &&
                    !elemText.contains('12 May') &&
                    !elemText.contains('Actualités')) {
                  title = elemText;
                  break;
                }
              }
            }
            
            if (link.isNotEmpty && !link.startsWith('http')) {
              link = '$fstUrl$link';
            }
            
            print('NewsService: Titre trouvé: "$title"');
            print('NewsService: Lien trouvé: "$link"');
            
            String date = '';
            var calendarElements = element.querySelectorAll('.fa-calendar-alt, .fal.fa-calendar-alt');
            
            if (calendarElements.isEmpty) {
              var metaInfo = element.querySelector('.meta-info');
              var calendarInMeta = metaInfo?.querySelectorAll('.fa-calendar-alt, .fal.fa-calendar-alt');
              if (calendarInMeta != null && calendarInMeta.isNotEmpty) {
                calendarElements = calendarInMeta;
              }
            }
            
            for (var calElement in calendarElements) {
              if (calElement.parent != null) {
                date = calElement.parent!.text.trim();
                break;
              }
            }
            
            if (date.isEmpty) {
              var liElements = element.querySelectorAll('li');
              for (var li in liElements) {
                var liText = li.text.trim();
                if (liText.contains('May') || liText.contains('202')) {
                  date = liText;
                  break;
                }
              }
            }
            
            print('NewsService: Date trouvée: "$date"');
            
            String category = 'Actualités'; 
            var boxElements = element.querySelectorAll('.fa-box, .fal.fa-box');
            for (var boxElement in boxElements) {
              if (boxElement.parent != null) {
                var catText = boxElement.parent!.text.trim();
                if (catText.isNotEmpty) {
                  category = catText;
                  break;
                }
              }
            }
            
            print('NewsService: Catégorie trouvée: "$category"');
            
            String content = '';
            var paragraphs = element.querySelectorAll('p');
            for (var p in paragraphs) {
              var pText = p.text.trim();
              if (pText.isNotEmpty && 
                  pText != title && 
                  !pText.contains('En savoir plus')) {
                content = pText;
                break;
              }
            }
            
            if (content.isEmpty && title.isNotEmpty) {
              content = "Cliquez pour en savoir plus sur cette actualité.";
            }
            
            print('NewsService: Contenu trouvé: "${content.substring(0, content.length > 50 ? 50 : content.length)}..."');
            
            if (title.isNotEmpty || imageUrl.isNotEmpty) {
              if (title.isEmpty && imageUrl.isNotEmpty) {
                title = "Actualité FST";
              }
              
              var newsItem = NewsItem(
              title: title,
                content: content,
              date: date,
                imageUrl: imageUrl,
                category: category,
                link: link,
              );
              
              newsItems.add(newsItem);
              print('NewsService: Actualité ajoutée: "$title"');
            }
          } catch (e) {
            print('NewsService: Erreur lors du traitement d\'un élément: $e');
          }
        }
        
        print('NewsService: Total des actualités extraites: ${newsItems.length}');
        
        if (newsItems.isEmpty) {
          print('NewsService: Aucune actualité n\'a pu être extraite correctement');
          throw Exception('Aucune actualité extraite de la page');
        }
        
        return newsItems;
      } else {
        print('NewsService: Erreur HTTP ${response.statusCode}');
        throw Exception('Erreur lors du chargement des actualités (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('NewsService: Exception: $e');
      throw Exception('Erreur lors du chargement des actualités: $e');
    }
  }

  void dispose() {
    print('NewsService: Fermeture du client HTTP');
    _httpClient.close();
  }
}