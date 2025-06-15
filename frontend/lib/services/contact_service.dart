import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../models/contact_model.dart';

class ContactService {
  static const String baseUrl = 'https://www.fsts.ac.ma';
  
  Future<ContactInfo> getContactInfo() async {
    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
        },
      );

      if (response.statusCode == 200) {
        return _parseContactFromHtml(response.body);
      } else {
        throw Exception('Erreur lors du chargement de la page: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erreur lors de la récupération des informations de contact: $e');
    }
  }

  ContactInfo _parseContactFromHtml(String htmlContent) {
    final document = parser.parse(htmlContent);
    
    String telephone = '';
    String email = '';
    String adresse = '';
    String? facebook;
    String? linkedin;

    try {
      final contactElements = document.querySelectorAll('.f-contact');
      
      for (var element in contactElements) {
        final spanElement = element.querySelector('.text span');
        final h3Element = element.querySelector('.text h3');
        
        if (spanElement != null && h3Element != null) {
          final spanText = spanElement.text.toLowerCase().trim();
          final h3Text = h3Element.text.trim();
          
          if (spanText.contains('téléphone') || spanText.contains('phone')) {
            telephone = h3Text;
          } else if (spanText.contains('email')) {
            email = h3Text;
          } else if (spanText.contains('adresse') || spanText.contains('address')) {
            adresse = h3Text;
          }
        }
      }

      final socialLinks = document.querySelectorAll('a[href*="facebook"], a[href*="linkedin"]');
      
      for (var link in socialLinks) {
        final href = link.attributes['href'];
        if (href != null) {
          if (href.contains('facebook')) {
            facebook = _formatUrl(href);
          } else if (href.contains('linkedin')) {
            linkedin = _formatUrl(href);
          }
        }
      }
    } catch (e) {
      print('Erreur lors du parsing HTML: $e');
    }

    return ContactInfo(
      telephone: telephone,
      email: email,
      adresse: adresse,
      facebook: facebook,
      linkedin: linkedin,
    );
  }

  String? _formatUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!url.startsWith('http')) {
      return 'https://$url';
    }
    return url;
  }

  void dispose() {
  }
}