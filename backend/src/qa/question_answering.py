import os
import logging
import time
from typing import List, Dict, Any, Optional
import requests
import re
from collections import defaultdict
import json

from dotenv import load_dotenv
from langchain.memory import ConversationBufferMemory
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS
from langchain_community.document_loaders import DirectoryLoader, TextLoader
from langchain.schema import Document

from src.qa.promps import RAG_PROMPT
from .llm_client import LLMClient
from src.database.vector_store import VectorStoreManager

from langdetect import detect
from deep_translator import GoogleTranslator
from unidecode import unidecode

load_dotenv()

VECTOR_STORE_DIR = os.getenv("VECTOR_STORE_DIR")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_question(question: str, target_lang: str = "fr") -> str:
    try:
        detected_lang = detect(question)
        if detected_lang not in ["fr", "en", "ar"]:
            return question
        if detected_lang != target_lang:
            return GoogleTranslator(source=detected_lang, target=target_lang).translate(question)
        return question
    except Exception as e:
        logger.warning(f"Erreur de détection ou traduction de langue : {e}")
        return question


def extract_keyword(question: str) -> str:
    mots = question.lower().split()
    mots_utiles = [mot for mot in mots if len(mot) > 3]
    return mots_utiles[0] if mots_utiles else question


class FSTQueryEngine:
    """Moteur de questions-réponses optimisé pour les formations universitaires"""

    def __init__(self, model_name: str = os.getenv("LLM_MODEL"), temperature: float = 0, 
                 top_k: int = 5, vector_store_path: Optional[str] = None, use_memory: bool = True):
        self.embeddings = HuggingFaceEmbeddings(model_name=os.getenv("EMBEDDING_MODEL"))
        self.vector_store_path = vector_store_path or VECTOR_STORE_DIR
        self.vector_store_manager = VectorStoreManager(self.embeddings, self.vector_store_path)
        self.vector_store = self._load_vector_store()

        self.llm_client = LLMClient(
            model_type="gemini",
            api_key=os.getenv("GOOGLE_API_KEY"),
            model_name=model_name,
            temperature=temperature
        )

        self.memory = ConversationBufferMemory(memory_key="chat_history", return_messages=True) if use_memory else None
        self.qa_chain = self._create_qa_chain() if self.vector_store else None

        logger.info(f"FSTQueryEngine initialisé avec modèle {model_name}")

    def get_emojis_from_api(self, query: str) -> List[str]:
        default_emojis = {
            "formation": "[DEGREE]", "cours": "[BOOK]", "diplome": "[SCROLL]", "examen": "[PENCIL]", 
            "etude": "[BRAIN]", "universite": "[BUILDING]", "professeur": "[TEACHER]",
            "temps": "[HOURGLASS]", "duree": "[STOPWATCH]", "delai": "[HOURGLASS]", "date": "[CALENDAR]", 
            "annee": "[CALENDAR]", "semestre": "[CALENDAR]", "heure": "[CLOCK]",
            "bonjour": "[WAVE]", "salut": "[SMILE]", "coucou": "[HUG]", "hello": "[HAND]",
            "how are you": "[SMILE]", "ca va": "[THUMBSUP]", "bienvenue": "[OPENARMS]",
            "inscription": "[PAPER]", "dossier": "[FILE]", "document": "[DOC]", 
            "administration": "[BUILDING]", "scolarite": "[CLIPBOARD]",
            "quoi": "[QUESTION]", "quand": "[CLOCK]", "comment": "[THINK]", "pourquoi": "[QUESTION]",
            "ou": "[LOCATION]", "qui": "[PERSON]"
        }
        
        try:
            api_key = os.getenv("EMOJI_API_KEY")
            if api_key:
                keyword = extract_keyword(query)
                response = requests.get(
                    f"https://emoji-api.com/emojis?search={keyword}&access_key={api_key}",
                    timeout=2
                )
                if response.status_code == 200:
                    data = response.json()
                    if isinstance(data, list) and len(data) > 0:
                        return [item['character'] for item in data[:3]]
            
            query_lower = query.lower()
            for keyword, emoji in default_emojis.items():
                if keyword in query_lower:
                    return [emoji]
                    
            return ["ℹ️"]
            
        except Exception as e:
            logger.error(f"Erreur lors de la récupération des emojis : {e}")
            return ["💬"]

    def _load_vector_store(self) -> Optional[FAISS]:
        try:
            logger.info(f"Chargement du vector store depuis {self.vector_store_path}")
            vector_store = self.vector_store_manager.load_faiss()
            if vector_store:
                nb_docs = len(vector_store.docstore._dict)
                logger.info(f"Vector store chargé avec succès : {nb_docs} documents")
                return vector_store
            logger.warning(f"Vector store introuvable à {self.vector_store_path}")
            return None
        except Exception as e:
            logger.error(f"Erreur lors du chargement du vector store : {str(e)}")
            return None

    def _create_qa_chain(self):
        try:
            return self.llm_client.create_qa_chain(self.vector_store, prompt=RAG_PROMPT)
        except Exception as e:
            logger.error(f"Erreur lors de la création de la chaîne QA : {str(e)}")
            return None

    def query(self, question: str) -> Dict[str, Any]:
        response = {
            'question': question,
            'answer': '',
            'context_used': '',
            'documents_found': 0,
            'error': None
        }
        try:
            normalized_question = normalize_question(question)
            formation_id, _ = self._detect_formation(normalized_question)
            intent, _ = self._detect_intent(normalized_question)

            search_strategy = self._determine_search_strategy(intent, formation_id)
            relevant_docs = self._get_relevant_documents(normalized_question, search_strategy, formation_id)
            if not relevant_docs:
                response['answer'] = self._generate_no_info_response(formation_id, intent)
                return response
            context = self._build_enhanced_context(relevant_docs, intent, formation_id)
            enhanced_prompt = self._build_enhanced_prompt(
                question=question,
                normalized_question=normalized_question,
                formation_id=formation_id,
                intent=intent,
                context=context
            )
            qa_result = self.qa_chain.invoke({
                "query": enhanced_prompt,
                "context": context
            })
            response.update({
                'answer': self._post_process_answer(qa_result.get('result', '')),
                'context_used': context,
                'documents_found': len(relevant_docs)
            })
        except Exception as e:
            logger.error("Erreur lors du traitement de la question: %s", str(e))
            response.update({
                'answer': "Une erreur est survenue lors du traitement de votre question.",
                'error': str(e)
            })
        return response

    def _determine_search_strategy(self, intent: str, formation_id: str) -> Dict[str, Any]:
        """Détermine une stratégie de recherche optimisée pour les modules"""
        return {
            'k_base': 15,
            'k_modules': 8,
            'min_similarity': 0.7,
            'search_types': ['similarity', 'mmr'],
            'metadata_filters': {
                'formation_id': formation_id
            }
        }

    def _get_relevant_documents(self, question: str, strategy: Dict[str, Any], formation_id: str) -> List[Document]:
        """Récupère les documents pertinents avec focus sur les modules"""
        all_docs = []
        docs = self.vector_store.similarity_search(
            query=question,
            k=strategy['k_base'],
            filter=strategy['metadata_filters']
        )
        all_docs.extend(docs)
        module_docs = self.vector_store.max_marginal_relevance_search(
            query=f"modules programme {formation_id}",
            k=strategy['k_modules'],
            filter={
                'formation_id': formation_id
            }
        )
        all_docs.extend(module_docs)
        seen_ids = set()
        unique_docs = []
        for doc in all_docs:
            doc_id = doc.metadata.get('chunk_id', hash(doc.page_content))
            if doc_id not in seen_ids:
                seen_ids.add(doc_id)
                unique_docs.append(doc)
        return unique_docs

    def _build_enhanced_context(self, docs: List[Document], intent: str, formation_id: str) -> str:
        """Construit un contexte structuré avec focus sur les modules"""
        context_parts = []
        formation_info = self._aggregate_formation_info(docs, formation_id)
        if formation_info:
            context_parts.append("=== INFORMATIONS GÉNÉRALES ===")
            context_parts.append(json.dumps(formation_info, ensure_ascii=False, indent=2))
        modules = self._aggregate_modules(docs)
        if modules:
            context_parts.append("\n=== MODULES DU PROGRAMME ===")
            for code, module in modules.items():
                context_parts.append(f"\n--- MODULE {code} ---")
                context_parts.append(json.dumps(module, ensure_ascii=False, indent=2))
        context_parts.append("\n=== CONTENU DES DOCUMENTS ===")
        for i, doc in enumerate(docs[:5]):  
            context_parts.append(f"\n--- DOCUMENT {i+1} ---")
            context_parts.append(f"Métadonnées: {json.dumps(doc.metadata, ensure_ascii=False)}")
            context_parts.append(f"Contenu: {doc.page_content[:500]}...") 
        return "\n".join(context_parts)

    def _aggregate_formation_info(self, docs: List[Document], formation_id: str) -> Dict[str, Any]:
        """Agrège les informations générales de la formation"""
        info = {
            'formation': {},
            'objectifs': [],
            'admission': [],
            'debouches': [],
            'organisation': {}
        }
        for doc in docs:
            meta = doc.metadata
            if 'formation_info' in meta and isinstance(meta['formation_info'], dict):
                fi = meta['formation_info']
                if 'formation' in fi:
                    info['formation'].update(fi['formation'])
                if 'objectifs' in fi:
                    info['objectifs'].extend(self._ensure_list(fi['objectifs']))
                if 'admission' in fi:
                    info['admission'].extend(self._ensure_list(fi['admission']))
                if 'debouches' in fi:
                    info['debouches'].extend(self._ensure_list(fi['debouches']))
                if 'organisation' in fi:
                    info['organisation'].update(fi['organisation'])
            for field in ['formation', 'objectifs', 'admission', 'debouches', 'organisation']:
                if field in meta:
                    if isinstance(info[field], dict) and isinstance(meta[field], dict):
                        info[field].update(meta[field])
                    elif isinstance(info[field], list):
                        if isinstance(meta[field], dict):
                            for v in meta[field].values():
                                if isinstance(v, list):
                                    info[field].extend(v)
                                else:
                                    info[field].append(v)
                        else:
                            info[field].extend(self._ensure_list(meta[field]))
                    else:
                        logger.warning(f"Champ inattendu pour {field}: info={type(info[field])}, meta={type(meta[field])}")
                  
        for field in ['objectifs', 'admission', 'debouches']:
            try:
                info[field] = list(set(info[field]))
            except TypeError:
                logger.warning(f"Impossible de dédoublonner {field} car il contient des éléments non hashables: {info[field]}")
        return info

    def _aggregate_modules(self, docs: List[Document]) -> Dict[str, Dict]:
        """Agrège les modules de différents documents"""
        modules = {}
        for doc in docs:
            meta = doc.metadata
            if 'formation_info' in meta and isinstance(meta['formation_info'], dict):
                fi = meta['formation_info']
                if 'programme' in fi and 'modules' in fi['programme']:
                    for module in fi['programme']['modules']:
                        if isinstance(module, dict) and 'code' in module:
                            modules[module['code']] = self._standardize_module(module)
            if 'programme' in meta and 'modules' in meta['programme']:
                for module in meta['programme']['modules']:
                    if isinstance(module, dict) and 'code' in module:
                        modules[module['code']] = self._standardize_module(module)
            if 'module_info' in meta:
                module = meta['module_info']
                if isinstance(module, dict) and 'code' in module:
                    modules[module['code']] = self._standardize_module(module)
        return modules

    def _standardize_module(self, module: Dict) -> Dict:
        """Standardise le format d'un module"""
        required_fields = ['code', 'intitule']
        for field in required_fields:
            if field not in module:
                module[field] = 'Non spécifié'
        if 'volume_horaire' not in module:
            module['volume_horaire'] = {
                'cours': 0,
                'td': 0,
                'tp': 0,
                'total': 0
            }
        return module

    def _build_enhanced_prompt(self, question: str, normalized_question: str, 
                             formation_id: str, intent: str, context: str) -> str:
        """Construit un prompt optimisé pour les informations de formation"""
        return f"""
        Vous êtes un expert des formations universitaires à la FST Settat.
        Voici les informations disponibles sur la formation {formation_id}:

        [CONTEXTE]
        {context}

        [INSTRUCTIONS]
        - Répondez exclusivement en français
        - Structurez votre réponse avec des sections claires
        - Pour les questions sur les modules, listez TOUS les modules disponibles
        - Mentionnez quand une information est manquante
        - Soyez exhaustif mais concis

        [QUESTION]
        {question}

        [FORMAT DE RÉPONSE ATTENDU]
        # Réponse pour {formation_id}

        ## Modules du programme
        - [Code] Intitulé (Volume horaire: Xh)
          Objectifs: ...
          Prérequis: ...

        ## Informations générales
        ...

        Veuillez fournir votre réponse ci-dessous:
        """

    def _post_process_answer(self, answer: str) -> str:
        """Nettoie et améliore la réponse générée"""
        phrases_a_supprimer = [
            "D'après le contexte fourni",
            "Selon les documents",
            "Je suis un AI assistant",
            "En tant qu'IA"
        ]
        for phrase in phrases_a_supprimer:
            answer = answer.replace(phrase, "")
        answer = answer.replace("##", "\n##")  
        answer = answer.replace(" - ", "\n- ")  
        return answer.strip()

    def _detect_intent(self, question: str) -> tuple:
        """Détecte l'intention de la question"""
        intent_keywords = {
            'admission': ['admission', 'prérequis', 'conditions', 'inscription', 'candidature', 'postuler'],
            'programme': ['programme', 'cours', 'module', 'matière', 'contenu', 'enseigne'],
            'débouchés': ['débouché', 'carrière', 'métier', 'profession', 'travail', 'emploi'],
            'objectifs': ['objectif', 'compétence', 'apprentissage', 'apprendre', 'acquérir'],
            'contact': ['contact', 'email', 'téléphone', 'adresse', 'responsable', 'coordonnées'],
            'général': ['formation', 'master', 'licence', 'filière', 'département']
        }
        
        scores = defaultdict(float)
        question_tokens = question.lower().split()
        
        for intent, keywords in intent_keywords.items():
            for keyword in keywords:
                if keyword in question.lower():
                    scores[intent] += 1.0
        
        if not scores:
            return 'général', 0.5
            
        max_score = max(scores.values())
        if max_score == 0:
            return 'général', 0.5
            
        for intent in scores:
            scores[intent] = float(scores[intent]) / float(max_score)
            
        max_intent = max(scores.items(), key=lambda x: x[1])
        return max_intent[0], float(max_intent[1])

    def _detect_formation(self, question: str) -> tuple:
        """Détecte la formation concernée dans la question"""
        formations = {
            'MST_RSI_FST_SETTAT': ['mst', 'rsi', 'réseau', 'système', 'informatique'],
            'marketing digital': ['marketing', 'digital', 'numérique', 'communication']
        }
        
        scores = defaultdict(float)
        question_lower = question.lower()
        
        for formation_id, keywords in formations.items():
            for keyword in keywords:
                if keyword in question_lower:
                    scores[formation_id] += 1.0
        
        if not scores:
            return 'UNKNOWN', 0.0
            
        max_score = max(scores.values())
        if max_score == 0:
            return 'UNKNOWN', 0.0
            
        for formation in scores:
            scores[formation] = float(scores[formation]) / float(max_score)
            
        max_formation = max(scores.items(), key=lambda x: x[1])
        return max_formation[0], float(max_formation[1])

    def _generate_no_info_response(self, formation_id: str, intent: str) -> str:
        """Génère une réponse appropriée quand aucune information n'est trouvée"""
        if formation_id == 'UNKNOWN':
            return ("Je ne trouve pas d'informations spécifiques pour votre demande. "
                   "Pourriez-vous préciser la formation qui vous intéresse ?")
        
        intent_messages = {
            'admission': f"Je ne trouve pas les conditions d'admission pour la formation {formation_id}. "
                       "Vous pouvez contacter directement le secrétariat pour plus d'informations.",
            'programme': f"Je ne trouve pas le programme détaillé de la formation {formation_id}. "
                       "Le programme est peut-être en cours de mise à jour.",
            'débouchés': f"Je ne trouve pas les débouchés spécifiques pour {formation_id}. "
                       "Je vous conseille de consulter la page de la formation sur le site de la FST.",
            'objectifs': f"Je ne trouve pas les objectifs précis de la formation {formation_id}. "
                       "Vous pouvez consulter la brochure de la formation pour plus de détails.",
            'général': f"Je ne trouve pas d'informations générales sur la formation {formation_id}. "
                       "Essayez de poser une question plus spécifique ou consultez le site de la FST."
        }
        
        return intent_messages.get(intent, "Je suis désolé, je ne trouve pas l'information demandée.")

    def search_similar_docs(self, query: str, top_k: int = 5):
        try:
            if not self.vector_store:
                logger.error("Vector store non initialisé pour la recherche de documents")
                return []
            docs = self.vector_store.similarity_search(query, k=top_k)
            return docs
        except Exception as e:
            logger.error(f"Erreur lors de la recherche de documents : {str(e)}")
            return []

    def clear_memory(self):
        if self.memory:
            self.memory.clear()
            logger.info("Mémoire de conversation effacée")

    def _ensure_list(self, value):
        """Garantit que la valeur est une liste pour l'agrégation."""
        if value is None:
            return []
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            return [value]
        return [value]
