import re
import unicodedata
import logging
from typing import List, Dict, Optional
from langchain_core.documents import Document
from langchain_community.document_transformers import Html2TextTransformer

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class FSSTTextCleaner:
    """Solution optimisée pour le nettoyage des documents de formation FSTS"""
    
    DEFAULT_PATTERNS = [
        r'^\s*\d+\s*$',  # Numéros seuls
        r'FSTS\s*-\s*Formation',  # En-têtes FSTS
        r'Référence\s*:\s*\w+',  # Références
        r'www\.?fsts\.ac\.ma',  # URL du site
        r'\s+\-+\s+',  # Lignes de séparation
        r'\s+\=+\s+',  # Lignes de séparation
        r'\s+\_+\s+',  # Lignes de séparation
        r'\s+\n\s+',  # Retours à la ligne multiples
        r'\s+\t\s+',  # Tabulations
    ]
    
    def __init__(self, custom_patterns: Optional[List[str]] = None):
        self.html_transformer = Html2TextTransformer()
        self.patterns = self.DEFAULT_PATTERNS + (custom_patterns or [])
        
    def _normalize_unicode(self, text: str) -> str:
        """Normalise les caractères Unicode et nettoie les espaces"""
        try:
            text = unicodedata.normalize('NFKC', text)
            text = re.sub(r'[\u0080-\u009F]', ' ', text)  # Supprimer les caractères de contrôle
            text = re.sub(r'[\u00AD]', '', text)  # Supprimer les tirets doux
            return re.sub(r'[\s\u00A0]+', ' ', text).strip()
        except Exception as e:
            logger.error(f"Erreur de normalisation Unicode: {str(e)}")
            return text
    
    def _remove_specific_patterns(self, text: str) -> str:
        """Supprime les motifs spécifiques"""
        try:
            for pattern in self.patterns:
                text = re.sub(pattern, '', text, flags=re.IGNORECASE|re.MULTILINE)
            return text
        except Exception as e:
            logger.error(f"Erreur de suppression des motifs: {str(e)}")
            return text
    
    def _clean_whitespace(self, text: str) -> str:
        """Nettoie les espaces tout en préservant la structure"""
        try:
            # Remplacer les espaces multiples par un seul espace
            text = re.sub(r'\s+', ' ', text)
            
            # Remplacer les retours à la ligne multiples par un seul
            text = re.sub(r'\n\s*\n', '\n', text)
            
            # Supprimer les espaces en début et fin de ligne
            text = re.sub(r'^\s+|\s+$', '', text, flags=re.MULTILINE)
            
            # Supprimer les lignes vides
            text = re.sub(r'^\s*$', '', text, flags=re.MULTILINE)
            
            return text.strip()
        except Exception as e:
            logger.error(f"Erreur de nettoyage des espaces: {str(e)}")
            return text
    
    def clean_text(self, text: str) -> str:
        """Nettoie le texte complet tout en préservant la structure"""
        try:
            # Convertir en texte brut si c'est du HTML
            text = self.html_transformer.transform(text)
            
            # Normaliser l'Unicode
            text = self._normalize_unicode(text)
            
            # Supprimer les motifs spécifiques tout en préservant la structure
            text = self._remove_specific_patterns(text)
            
            # Nettoyer les espaces tout en préservant la structure
            text = self._clean_whitespace(text)
            
            # Supprimer les espaces multiples entre les mots
            text = re.sub(r'\s+', ' ', text)
            
            # Supprimer les retours à la ligne multiples
            text = re.sub(r'\n\s*\n', '\n\n', text)
            
            # Supprimer les espaces en début et fin de ligne
            text = re.sub(r'^\s+|\s+$', '', text, flags=re.MULTILINE)
            
            # Supprimer les lignes vides
            text = re.sub(r'^\s*$', '', text, flags=re.MULTILINE)
            
            return text.strip()
        except Exception as e:
            logger.error(f"Erreur lors du nettoyage du texte: {str(e)}")
            return text
    
    def _normalize_unicode(self, text: str) -> str:
        """Normalise les caractères Unicode et nettoie les espaces"""
        try:
            text = unicodedata.normalize('NFKC', text)
            text = re.sub(r'[\u0080-\u009F]', ' ', text)  # Supprimer les caractères de contrôle
            text = re.sub(r'[\u00AD]', '', text)  # Supprimer les tirets doux
            return re.sub(r'[\s\u00A0]+', ' ', text).strip()
        except Exception as e:
            logger.error(f"Erreur de normalisation Unicode: {str(e)}")
            return text
    
    def _remove_specific_patterns(self, text: str) -> str:
        """Supprime les motifs spécifiques"""
        try:
            # Supprimer les en-têtes et pieds de page
            text = re.sub(r'^\s*\d+\s*$', '', text, flags=re.MULTILINE)  # Numéros de page
            text = re.sub(r'FSTS\s*-\s*Formation', '', text, flags=re.IGNORECASE)  # En-têtes FSTS
            text = re.sub(r'Référence\s*:\s*\w+', '', text, flags=re.IGNORECASE)  # Références
            text = re.sub(r'www\.?fsts\.ac\.ma', '', text, flags=re.IGNORECASE)  # URL du site
            
            # Supprimer les lignes de séparation
            text = re.sub(r'\s+\-+\s+', ' ', text)  # Lignes de tirets
            text = re.sub(r'\s+\=+\s+', ' ', text)  # Lignes d'égalité
            text = re.sub(r'\s+\_+\s+', ' ', text)  # Lignes de soulignement
            
            # Supprimer les espaces multiples et les retours à la ligne
            text = re.sub(r'\s+\n\s+', ' ', text)
            text = re.sub(r'\s+\t\s+', ' ', text)
            
            return text.strip()
        except Exception as e:
            logger.error(f"Erreur de suppression des motifs: {str(e)}")
            return text
    
    def clean_text(self, text: str) -> str:
        """Nettoie le texte complet"""
        try:
            # Convertir en texte brut si c'est du HTML
            text = self.html_transformer.transform(text)
            
            # Normaliser l'Unicode
            text = self._normalize_unicode(text)
            
            # Supprimer les motifs spécifiques
            text = self._remove_specific_patterns(text)
            
            return text
        except Exception as e:
            logger.error(f"Erreur lors du nettoyage du texte: {str(e)}")
            return text
    
    def _clean_whitespace(self, text: str) -> str:
        """Nettoie les espaces"""
        try:
            text = re.sub(r'\s+', ' ', text)
            return text.strip()
        except Exception as e:
            logger.error(f"Erreur de nettoyage des espaces: {str(e)}")
            return text
    
    def clean_text(self, text: str) -> str:
        """Pipeline complet de nettoyage"""
        if not isinstance(text, str):
            logger.error("Le texte à nettoyer n'est pas une chaîne valide")
            return ""
            
        try:
            text = self._normalize_unicode(text)
            text = self._remove_specific_patterns(text)
            text = self.html_transformer.transform_documents([Document(page_content=text)])[0].page_content
            return self._clean_whitespace(text)
        except Exception as e:
            logger.error(f"Erreur lors du nettoyage du texte: {str(e)}")
            return text
    
    def clean_langchain_document(self, document: Document) -> Document:
        """Nettoie un document LangChain"""
        if not isinstance(document, Document):
            logger.error("Document invalide reçu")
            return document
            
        try:
            return Document(
                page_content=self.clean_text(document.page_content),
                metadata=document.metadata.copy()
            )
        except Exception as e:
            logger.error(f"Erreur de nettoyage du document: {str(e)}")
            return document
    
    def clean_batch(self, documents: List[Document]) -> List[Document]:
        """Nettoie une liste de documents"""
        if not isinstance(documents, list):
            logger.error("Liste de documents invalide")
            return []
            
        cleaned = []
        for doc in documents:
            try:
                cleaned_doc = self.clean_langchain_document(doc)
                if cleaned_doc:
                    cleaned.append(cleaned_doc)
            except Exception as e:
                logger.error(f"Erreur lors du traitement d'un document: {str(e)}")
                continue
                
        logger.info(f"Nettoyé {len(cleaned)} documents")
        return cleaned