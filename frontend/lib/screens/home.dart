import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fst_chatbot/providers/navigation_provider.dart';
import 'package:fst_chatbot/providers/theme_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/news_detail_screen.dart';
import '../widgets/news_card.dart';
import '../services/news_service.dart';
import '../models/news_item_model.dart';
import '../screens/all_news_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  final NewsService _newsService = NewsService();
  List<NewsItem>? _news;
  bool _isLoading = true;
  String? _error;
  late AnimationController _animationController;
  Animation<double>? _fadeAnimation; 
  final ScrollController _scrollController = ScrollController();
  bool _showAppBarTitle = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _scrollController.addListener(_scrollListener);
    _loadNews();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  void _scrollListener() {
    if (_scrollController.offset > 200 && !_showAppBarTitle) {
      setState(() => _showAppBarTitle = true);
    } else if (_scrollController.offset <= 200 && _showAppBarTitle) {
      setState(() => _showAppBarTitle = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _newsService.dispose();
    super.dispose();
  }

  Future<void> _loadNews() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final news = await _newsService.getLatestNews();
      if (!mounted) return;
      
      setState(() {
        _news = news;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('Error loading news: $e');
    }
  }

  Future<void> _refreshNews() async {
    await _loadNews();
  }

  void _toggleTheme() {
    ref.read(themeProvider.notifier).toggleTheme();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeProvider);

    return Theme(
      data: isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(isDarkMode),
            SliverToBoxAdapter(
              child: _fadeAnimation != null 
                ? FadeTransition(
                    opacity: _fadeAnimation!,
                    child: _buildWelcomeSection(isDarkMode),
                  )
                : _buildWelcomeSection(isDarkMode), 
            ),
            SliverToBoxAdapter(
              child: _buildQuickActions(isDarkMode),
            ),
            SliverToBoxAdapter(
              child: _buildNewsSection(isDarkMode),
            ),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(isDarkMode),
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDarkMode) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode 
              ? [const Color(0xFF1A237E), const Color(0xFF000051)]
              : [const Color(0xFFE65100), const Color(0xFFFF6F00)], 
          ),
        ),
        child: FlexibleSpaceBar(
          title: AnimatedOpacity(
            opacity: _showAppBarTitle ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Text(
              'FST Assistant',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          background: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: 'fst_logo',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'FST Settat',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Assistant Mobile',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: _toggleTheme,
                      tooltip: isDarkMode ? 'Mode clair' : 'Mode sombre',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFF5F5F5)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
              ? Colors.black.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode 
                      ? [Colors.indigoAccent, Colors.indigo]
                      : [const Color(0xFFE65100), const Color(0xFFFF8F00)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.waving_hand,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bienvenue !',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : const Color(0xFF1A237E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Découvrez les actualités de votre faculté',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.05) 
                : const Color(0xFFE65100).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDarkMode 
                  ? Colors.white.withOpacity(0.1) 
                  : const Color(0xFFE65100).withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Restez connecté avec les dernières nouvelles et événements de la FST Settat',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.white70 : Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isDarkMode) {
    final actions = [
      {
        'icon': Icons.school_outlined,
        'title': 'Excellence\nAcadémique',
        'subtitle': 'Formation de qualité',
        'color': const Color(0xFF2962FF),
        'description': 'Nous formons des esprits critiques avec une éducation de qualité',
      },
      {
        'icon': Icons.science_outlined,
        'title': 'Recherche\nScientifique',
        'subtitle': 'Innovation & collaboration',
        'color': const Color(0xFF388E3C),
        'description': 'Collaboration avec l\'industrie pour l\'innovation',
      },
      {
        'icon': Icons.computer_outlined,
        'title': 'Digitalisation\n& Innovation',
        'subtitle': 'Technologies avancées',
        'color': const Color(0xFF7B1FA2),
        'description': 'Solutions innovantes aux défis de demain',
      },
      {
        'icon': Icons.contact_mail_outlined,
        'title': 'Contact\n& Support',
        'subtitle': 'Aide & assistance',
        'color': const Color(0xFFE65100),
        'description': 'Support étudiant et informations pratiques',
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nos domaines d\'excellence',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : const Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode 
                      ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                      : [Colors.white, const Color(0xFFFAFAFA)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode 
                        ? Colors.black.withOpacity(0.3) 
                        : Colors.grey.withOpacity(0.15),
                      spreadRadius: 0,
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(
                    color: isDarkMode 
                      ? Colors.white.withOpacity(0.1) 
                      : Colors.grey.withOpacity(0.1),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showDomainInfo(action, isDarkMode),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (action['color'] as Color).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              action['icon'] as IconData,
                              color: action['color'] as Color,
                              size: 24,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            action['title'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : const Color(0xFF1A237E),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action['subtitle'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDomainInfo(Map<String, dynamic> domain, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: double.maxFinite,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode 
                  ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                  : [Colors.white, const Color(0xFFFAFAFA)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header avec gradient
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        domain['color'] as Color,
                        (domain['color'] as Color).withOpacity(0.8),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          domain['icon'] as IconData,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (domain['title'] as String).replaceAll('\n', ' '),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              domain['subtitle'] as String,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Contenu
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        domain['description'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildDomainDetails(domain['title'] as String, isDarkMode),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Fermer',
                              style: TextStyle(
                                color: domain['color'] as Color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDomainDetails(String title, bool isDarkMode) {
    List<Map<String, String>> details = [];
    
    if (title.contains('Excellence')) {
      details = [
        {'icon': '🎓', 'text': 'Formation d\'esprits critiques'},
        {'icon': '📚', 'text': 'Programmes académiques variés'},
        {'icon': '🏆', 'text': 'Standards de qualité élevés'},
      ];
    } else if (title.contains('Recherche')) {
      details = [
        {'icon': '🔬', 'text': 'Laboratoires de pointe'},
        {'icon': '🤝', 'text': 'Partenariats industriels'},
        {'icon': '💡', 'text': 'Innovation continue'},
      ];
    } else if (title.contains('Digitalisation')) {
      details = [
        {'icon': '💻', 'text': 'Technologies émergentes'},
        {'icon': '🚀', 'text': 'Solutions innovantes'},
        {'icon': '🌐', 'text': 'Transformation digitale'},
      ];
    } else {
      details = [
        {'icon': '📞', 'text': 'Support étudiant 24/7'},
        {'icon': '📧', 'text': 'Assistance administrative'},
        {'icon': '🎯', 'text': 'Orientation personnalisée'},
      ];
    }
    
    return Column(
      children: details.map((detail) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.05) 
            : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(detail['icon']!, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                detail['text']!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildNewsSection(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nos dernières actualités',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : const Color(0xFF1A237E),
                ),
              ),
              TextButton(
                onPressed: () {
    ref.read(navigationIndexProvider.notifier).setIndex(1);
  },
                child: Text(
                  'Voir tout',
                  style: TextStyle(
                    color: isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildNewsList(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildNewsList(bool isDarkMode) {
    if (_isLoading) {
      return _buildLoadingWidget(isDarkMode);
    }

    if (_error != null) {
      return _buildErrorWidget(_error!, isDarkMode);
    }

    if (_news == null || _news!.isEmpty) {
      return _buildEmptyWidget(isDarkMode);
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _news!.length > 3 ? 3 : _news!.length, // Limiter à 3 pour la page d'accueil
      itemBuilder: (context, index) {
        final newsItem = _news![index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode 
                ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                : [Colors.white, const Color(0xFFFAFAFA)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isDarkMode 
                  ? Colors.black.withOpacity(0.3) 
                  : Colors.grey.withOpacity(0.15),
                spreadRadius: 0,
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.1) 
                : Colors.grey.withOpacity(0.1),
            ),
          ),
          child: NewsCard(
            newsItem: newsItem,
            onTap: () => _showNewsDetail(newsItem),
          ),
        );
      },
    );
  }

  Widget _buildLoadingWidget(bool isDarkMode) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
              ),
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Chargement des actualités...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 16),
          Text(
            'Erreur de chargement',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vérifiez votre connexion Internet',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _refreshNews,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.article_outlined,
            size: 48,
            color: isDarkMode ? Colors.white54 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune actualité disponible',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Les actualités apparaîtront ici dès qu\'elles seront disponibles',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
            ? [Colors.indigoAccent, Colors.indigo]
            : [const Color(0xFFE65100), const Color(0xFFFF8F00)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                .withOpacity(0.4),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChatScreen()),
          );
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.smart_toy_outlined, color: Colors.white),
        label: const Text(
          'Assistant IA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showNewsDetail(NewsItem newsItem) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewsDetailScreen(newsItem: newsItem)),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFE65100),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFE65100),
        secondary: Color(0xFFFF8F00),
        surface: Colors.white,
        background: Color(0xFFFAFAFA),
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
  
  ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: Colors.indigoAccent[400],
      colorScheme: ColorScheme.dark(
        primary: Colors.indigoAccent[400]!,
        secondary: Colors.indigoAccent[100]!,
        surface: const Color(0xFF1A1A1A),
        background: const Color(0xFF121212),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}