import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../services/qa_service.dart';
import '../utils/config.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final QAService qaService = QAService(baseUrl: baseUrl);
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isDarkMode = false;
  bool _isGenerating = false;
  String _currentResponse = '';
  bool _shouldStopGeneration = false;
  
  // Rendre l'AnimationController nullable et vérifier avant utilisation
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;
  final FocusNode _textFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadThemePreference();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _animationController!.forward();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }


  @override
  void dispose() {
    _animationController?.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _isDarkMode
                  ? [const Color(0xFF121212), const Color(0xFF1A1A1A)]
                  : [const Color(0xFFFAFAFA), const Color(0xFFF5F5F5)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildModernAppBar(),
                Expanded(
                  child: _messages.isEmpty
                      ? _buildWelcomeScreen()
                      : _buildChatList(),
                ),
                _buildModernInputArea(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isDarkMode 
            ? [const Color(0xFF1A237E), const Color(0xFF000051)]
            : [const Color(0xFFE65100), const Color(0xFFFF6F00)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: (_isDarkMode ? const Color(0xFF1A237E) : const Color(0xFFE65100))
                .withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
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
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assistant FST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'En ligne',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
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
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              
              ),
              const SizedBox(width: 8),
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
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _clearChat,
                  tooltip: 'Effacer l\'historique',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    // Vérifier si l'animation est initialisée avant de l'utiliser
    if (_fadeAnimation == null) {
      return _buildWelcomeContent();
    }
    
    return FadeTransition(
      opacity: _fadeAnimation!,
      child: _buildWelcomeContent(),
    );
  }

  Widget _buildWelcomeContent() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDarkMode 
                  ? [Colors.indigoAccent.withOpacity(0.3), Colors.indigo.withOpacity(0.1)]
                  : [const Color(0xFFE65100).withOpacity(0.2), const Color(0xFFFF8F00).withOpacity(0.1)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                      .withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 80,
              color: _isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Assistant Intelligent FST',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _isDarkMode ? Colors.white : const Color(0xFF1A237E),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isDarkMode 
                  ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                  : [Colors.white, const Color(0xFFF5F5F5)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _isDarkMode 
                    ? Colors.black.withOpacity(0.3) 
                    : Colors.grey.withOpacity(0.2),
                  spreadRadius: 0,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: _isDarkMode 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.grey.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Je suis votre assistant personnel pour tout ce qui concerne la FST Settat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _isDarkMode ? Colors.white70 : Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSuggestionChips(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final suggestions = [
      'Informations sur les filières',
      'Horaires des cours',
      'Contact administration',
      'Événements à venir',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: suggestions.map((suggestion) => 
        GestureDetector(
          onTap: () => _handleSubmitted(suggestion),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDarkMode
                  ? [Colors.indigoAccent.withOpacity(0.2), Colors.indigo.withOpacity(0.1)]
                  : [const Color(0xFFE65100).withOpacity(0.1), const Color(0xFFFF8F00).withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isDarkMode 
                  ? Colors.indigoAccent.withOpacity(0.3)
                  : const Color(0xFFE65100).withOpacity(0.3),
              ),
            ),
            child: Text(
              suggestion,
              style: TextStyle(
                fontSize: 12,
                color: _isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        )
      ).toList(),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildTypingIndicator();
        }
        return _messages[index];
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildAvatar(false),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isDarkMode 
                  ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
                  : [Colors.white, const Color(0xFFF8F8F8)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: _isDarkMode 
                    ? Colors.black.withOpacity(0.3) 
                    : Colors.grey.withOpacity(0.2),
                  spreadRadius: 0,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 4),
                _buildTypingDot(1),
                const SizedBox(width: 4),
                _buildTypingDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    // Vérifier si l'animation est disponible
    if (_animationController == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: (_isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
              .withOpacity(0.5),
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animationController!,
      builder: (context, child) {
        final value = (_animationController!.value + index * 0.3) % 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: (_isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                .withOpacity(0.3 + 0.7 * (0.5 + 0.5 * (value > 0.5 ? 1 - value : value))),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildModernInputArea() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Bouton d'arrêt de génération (visible uniquement pendant la génération)
          if (_isGenerating)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              onPressed: _stopGeneration,
              tooltip: 'Arrêter la génération',
            ),
          // Champ de texte
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Tapez votre message...',
                hintStyle: TextStyle(
                  color: _isDarkMode ? Colors.white54 : Colors.grey[600],
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onSubmitted: _handleSubmitted,
              enabled: !_isGenerating,
            ),
          ),
          // Bouton d'envoi
          Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDarkMode
                    ? [Colors.indigoAccent, Colors.indigo]
                    : [const Color(0xFFE65100), const Color(0xFFFF8F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (_isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100))
                      .withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: _isGenerating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: _isGenerating || _textController.text.trim().isEmpty
                  ? null
                  : () => _handleSubmitted(_textController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUser
              ? _isDarkMode
                  ? [Colors.indigo.shade400, Colors.indigo.shade600]
                  : [const Color(0xFF1A237E), const Color(0xFF000051)]
              : _isDarkMode
                  ? [Colors.indigoAccent, Colors.indigo]
                  : [const Color(0xFFE65100), const Color(0xFFFF8F00)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isUser 
              ? (_isDarkMode ? Colors.indigo : const Color(0xFF1A237E))
              : (_isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100)))
                .withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    _textController.clear();
    _textFocusNode.unfocus();
    
    setState(() {
      _isLoading = true;
      _isGenerating = true;
      _shouldStopGeneration = false;
      _currentResponse = '';
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        isDarkMode: _isDarkMode,
      ));
    });

    _scrollToBottom();

    try {
      // Simuler un flux de réponse avec délai pour montrer le chargement
      final response = await qaService.askQuestion(text);
      
      // Si l'utilisateur a demandé d'arrêter, on ne fait rien
      if (_shouldStopGeneration) {
        return;
      }
      
      setState(() {
        _isLoading = false;
        _isGenerating = false;
        _currentResponse = '';
        _messages.add(ChatMessage(
          text: response,
          isUser: false,
          isDarkMode: _isDarkMode,
          onCopy: _copyToClipboard,
        ));
      });

      _scrollToBottom();
    } catch (e) {
      if (!_shouldStopGeneration) {
        setState(() {
          _isLoading = false;
          _isGenerating = false;
          _messages.add(
            ChatMessage(
              text: 'Désolé, je ne peux pas répondre pour le moment. Veuillez réessayer.',
              isUser: false,
              isDarkMode: _isDarkMode,
              onCopy: _copyToClipboard,
            ),
          );
        });
        _scrollToBottom();
      }
    } finally {
      if (_shouldStopGeneration) {
        _shouldStopGeneration = false;
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Réponse copiée dans le presse-papier'),
        backgroundColor: _isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Future<void> _stopGeneration() async {
    setState(() {
      _shouldStopGeneration = true;
      _isLoading = false;
      _isGenerating = false;
    });
    
    // Ajouter le message partiel si nécessaire
    if (_currentResponse.isNotEmpty) {
      _messages.add(ChatMessage(
        text: _currentResponse,
        isUser: false,
        isDarkMode: _isDarkMode,
      ));
      _currentResponse = '';
      _scrollToBottom();
    }
  }

  void _clearChat() async {
    bool success = await qaService.clearMemory();
    if (success) {
      setState(() {
        _messages.clear();
      });
      
      final snackBar = SnackBar(
        content: const Text(
          'Historique effacé avec succès',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: _isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.all(20),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      final errorSnackBar = SnackBar(
        content: const Text(
          'Erreur lors de l\'effacement de l\'historique',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.all(20),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar);
    }
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

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isDarkMode;
  final Function(String)? onCopy;

  const ChatMessage({
    Key? key,
    required this.text,
    required this.isUser,
    required this.isDarkMode,
    this.onCopy,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(false),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getBubbleColors(),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 20 : 5),
                  topRight: Radius.circular(isUser ? 5 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode 
                      ? Colors.black.withOpacity(0.3) 
                      : Colors.grey.withOpacity(0.2),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: isDarkMode 
                    ? Colors.white.withOpacity(0.1) 
                    : Colors.grey.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'Vous' : 'Assistant FST',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _getTextColor().withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: TextStyle(
                      color: _getTextColor(),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!isUser && onCopy != null)
                        GestureDetector(
                          onTap: () => onCopy!(text),
                          child: Icon(
                            Icons.content_copy,
                            size: 16,
                            color: _getTextColor().withOpacity(0.5),
                          ),
                        )
                      else
                        const SizedBox(width: 24), // Pour garder l'alignement
                      
                      Text(
                        _getTimeString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: _getTextColor().withOpacity(0.5),
                        ),
                      ),
                      
                      if (isUser) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all,
                            size: 12,
                            color: isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
                          ),
                        ],
                      ],
                    ),
                  
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            _buildAvatar(true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUser
              ? isDarkMode
                  ? [Colors.indigo.shade400, Colors.indigo.shade600]
                  : [const Color(0xFF1A237E), const Color(0xFF000051)]
              : isDarkMode
                  ? [Colors.indigoAccent, Colors.indigo]
                  : [const Color(0xFFE65100), const Color(0xFFFF8F00)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isUser 
              ? (isDarkMode ? Colors.indigo : const Color(0xFF1A237E))
              : (isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100)))
                .withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  List<Color> _getBubbleColors() {
    if (isUser) {
      return isDarkMode
          ? [const Color(0xFF1A237E), const Color(0xFF000051)]
          : [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)];
    } else {
      return isDarkMode 
        ? [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)]
        : [Colors.white, const Color(0xFFF8F8F8)];
    }
  }

  Color _getTextColor() {
    if (isUser) {
      return Colors.white;
    } else {
      return isDarkMode ? Colors.white : Colors.black87;
    }
  }

  String _getTimeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}