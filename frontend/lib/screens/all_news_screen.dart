import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/news_card.dart';
import '../services/news_service.dart';
import '../models/news_item_model.dart';
import '../screens/news_detail_screen.dart';
import '../providers/theme_provider.dart';

class AllNewsScreen extends ConsumerStatefulWidget {
  const AllNewsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AllNewsScreen> createState() => _AllNewsScreenState();
}

class _AllNewsScreenState extends ConsumerState<AllNewsScreen> with TickerProviderStateMixin {
  final NewsService _newsService = NewsService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<NewsItem> _allNews = [];
  List<NewsItem> _filteredNews = [];
  bool _isLoading = true;
  String? _error;
  String _selectedCategory = 'Toutes';
  String _sortBy = 'date_desc'; 

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late AnimationController _searchAnimationController;
  late Animation<double> _searchAnimation;

  final List<String> _categories = [
    'Toutes',
    'Académique',
    'Recherche',
    'Événements',
    'Administratif',
    'Étudiants',
    'International',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadNews();
    _searchController.addListener(_onSearchChanged);
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _searchAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _searchAnimationController, curve: Curves.easeInOut),
    );
    
    _animationController.forward();
  }

  void _onSearchChanged() {
    _filterNews();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchAnimationController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _newsService.dispose();
    super.dispose();
  }

  Future<void> _loadNews({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (isRefresh) {
        _allNews.clear();
      }
    });

    try {
      final news = await _newsService.getLatestNews();
      if (!mounted) return;
      
      setState(() {
        _allNews = news;
        _isLoading = false;
      });
      
      _filterNews();
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterNews() {
    List<NewsItem> filtered = List.from(_allNews);

    if (_selectedCategory != 'Toutes') {
      filtered = filtered.where((news) => 
        news.category?.toLowerCase() == _selectedCategory.toLowerCase()).toList();
    }

    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((news) =>
        news.title.toLowerCase().contains(searchTerm) ||
        news.content.toLowerCase().contains(searchTerm)).toList();
    }

    // Trier
    switch (_sortBy) {
      case 'date_desc':
        break;
      case 'date_asc':
        filtered = filtered.reversed.toList();
        break;
      case 'title_asc':
        filtered.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'title_desc':
        filtered.sort((a, b) => b.title.compareTo(a.title));
        break;
    }

    setState(() {
      _filteredNews = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeProvider);

    return PopScope(
      canPop: false,
      child: Theme(
        data: isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
        child: Scaffold(
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildSliverAppBar(isDarkMode),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildSearchAndFilters(isDarkMode),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildNewsStats(isDarkMode),
              ),
              _buildNewsList(isDarkMode),
            ],
          ),
        ),
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
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          icon: const Icon(
            Icons.search_rounded,
            color: Colors.white,
          ),
          onPressed: _toggleSearch,
        ),
        IconButton(
          icon: const Icon(
            Icons.filter_list_rounded,
            color: Colors.white,
          ),
          onPressed: () => _showFilterDialog(isDarkMode),
        ),
      ],
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
        child: const FlexibleSpaceBar(
          

          title: Padding(
            padding: EdgeInsets.fromLTRB(15,0,0,0),
            child: Text(
              'Toutes les Actualités',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          background: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.article_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FST Settat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Centre d\'actualités',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Barre de recherche animée
          AnimatedBuilder(
            animation: _searchAnimation,
            builder: (context, child) {
              return Container(
                height: 50 + (_searchAnimation.value * 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode 
                      ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                      : [Colors.white, const Color(0xFFFAFAFA)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode 
                        ? Colors.black.withOpacity(0.3) 
                        : Colors.grey.withOpacity(0.2),
                      blurRadius: 10 + (_searchAnimation.value * 5),
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans les actualités...',
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white60 : Colors.grey[600],
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: isDarkMode ? Colors.white60 : Colors.grey[600],
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: isDarkMode ? Colors.white60 : Colors.grey[600],
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _filterNews();
                          },
                        )
                      : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Filtres de catégories
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = category;
                      });
                      _filterNews();
                    },
                    backgroundColor: isDarkMode 
                      ? const Color(0xFF2C2C2C) 
                      : Colors.grey[100],
                    selectedColor: isDarkMode 
                      ? Colors.indigoAccent.withOpacity(0.3)
                      : const Color(0xFFE65100).withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: isSelected
                        ? (isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                        : (isDarkMode ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected
                        ? (isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                        : Colors.transparent,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsStats(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
              ? Colors.black.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_filteredNews.length} actualités',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                _selectedCategory != 'Toutes' 
                  ? 'Catégorie: $_selectedCategory'
                  : 'Toutes catégories',
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _loadNews(isRefresh: true),
                icon: Icon(
                  Icons.refresh_rounded,
                  color: isDarkMode ? Colors.white70 : Colors.grey[700],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  setState(() {
                    _sortBy = value;
                  });
                  _filterNews();
                },
                icon: Icon(
                  Icons.sort_rounded,
                  color: isDarkMode ? Colors.white70 : Colors.grey[700],
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'date_desc',
                    child: Text('Plus récent'),
                  ),
                  const PopupMenuItem(
                    value: 'date_asc',
                    child: Text('Plus ancien'),
                  ),
                  const PopupMenuItem(
                    value: 'title_asc',
                    child: Text('Titre A-Z'),
                  ),
                  const PopupMenuItem(
                    value: 'title_desc',
                    child: Text('Titre Z-A'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewsList(bool isDarkMode) {
    if (_isLoading) {
      return SliverToBoxAdapter(child: _buildLoadingWidget(isDarkMode));
    }

    if (_error != null) {
      return SliverToBoxAdapter(child: _buildErrorWidget(_error!, isDarkMode));
    }

    if (_filteredNews.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyWidget(isDarkMode));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final newsItem = _filteredNews[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
        childCount: _filteredNews.length,
      ),
    );
  }

  Widget _buildLoadingWidget(bool isDarkMode) {
    return Container(
      height: 300,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
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
      ),
    );
  }

  Widget _buildErrorWidget(String error, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 16),
          Text(
            'Erreur de chargement',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Impossible de charger les actualités',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _loadNews(isRefresh: true),
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
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode 
            ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
            : [Colors.white, const Color(0xFFFAFAFA)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: isDarkMode ? Colors.white54 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune actualité trouvée',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Essayez de modifier vos critères de recherche',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    if (_searchAnimationController.isCompleted) {
      _searchAnimationController.reverse();
    } else {
      _searchAnimationController.forward();
    }
  }

  void _showFilterDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Filtres et tri',
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trier par:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            ...['date_desc', 'date_asc', 'title_asc', 'title_desc'].map(
              (sort) => RadioListTile<String>(
                value: sort,
                groupValue: _sortBy,
                title: Text(
                  _getSortTitle(sort),
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _sortBy = value!;
                  });
                  _filterNews();
                  Navigator.pop(context);
                },
                activeColor: isDarkMode 
                  ? Colors.indigoAccent 
                  : const Color(0xFFE65100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSortTitle(String sort) {
    switch (sort) {
      case 'date_desc': return 'Plus récent';
      case 'date_asc': return 'Plus ancien';
      case 'title_asc': return 'Titre A-Z';
      case 'title_desc': return 'Titre Z-A';
      default: return sort;
    }
  }

  void _showNewsDetail(NewsItem newsItem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewsDetailScreen(newsItem: newsItem),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: const Color(0xFFE65100),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFE65100),
        secondary: Color(0xFFFF8F00),
      ),
    );
  }
  
  ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: Colors.indigoAccent[400],
      colorScheme: ColorScheme.dark(
        primary: Colors.indigoAccent[400]!,
        secondary: Colors.indigoAccent[100]!,
      ),
    );
  }
}