import 'package:flutter_test/flutter_test.dart';
import 'package:fst_chatbot/services/news_detail_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fst_chatbot/models/news_item_model.dart';

void main() {
  group('NewsDetailService', () {
    late NewsDetailService newsDetailService;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient((request) async {
        // Réponse simulée pour les détails
        if (request.url.toString().contains('detail1')) {
          return http.Response('''
            <div class="details__content">
              <h2>Titre détaillé</h2>
              <p>Contenu détaillé de l'actualité...</p>
              <a href="/files/document.pdf">Télécharger le PDF</a>
            </div>
          ''', 200);
        }
        
        return http.Response('Not Found', 404);
      });
      newsDetailService = NewsDetailService(client: mockClient);
    });

    test('getNewsDetails should return detailed news item', () async {
      final newsItem = NewsItem(
        title: '',
        content: '',
        date: '',
        imageUrl: '',
        category: '',
        link: 'https://www.fsts.ac.ma/actualites/detail1',
      );

      final detailedNews = await newsDetailService.getNewsDetails(newsItem.link);
      expect(detailedNews.title, 'Titre détaillé');
      expect(detailedNews.content, 'Contenu détaillé de l\'actualité...');
      expect(detailedNews.downloadLinks, contains('https://www.fsts.ac.ma/files/document.pdf'));
    });
  });
}
