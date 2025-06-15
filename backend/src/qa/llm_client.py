import os
import logging
from typing import Dict, Any, List, Optional
import torch
import redis
import json
import hashlib
import traceback  
from langchain_community.llms import HuggingFacePipeline, LlamaCpp
from langchain.llms.base import BaseLLM
from langchain.chains import RetrievalQA
from langchain.vectorstores.base import VectorStore
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
from langchain_google_genai import ChatGoogleGenerativeAI 

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class LLMClient:
    def __init__(self, model_type: str = "gemini", redis_url: Optional[str] = None, **kwargs):
        """
        Args:
            model_type: Type de modèle ('hf' pour HuggingFace, 'llama' pour Llama.cpp, ou 'gemini' pour Gemini API)
            redis_url: URL de connexion Redis (ex: 'redis://localhost:6379')
            **kwargs: Arguments supplémentaires pour la configuration du modèle
        """
        self.model_type = model_type.lower()
        self.redis_client = self._init_redis(redis_url) if redis_url else None
        self.llm = self._initialize_llm(**kwargs)
    
    def _init_redis(self, redis_url: str) -> Optional[redis.Redis]:
        """Initialise la connexion Redis."""
        try:
            client = redis.from_url(redis_url)
            client.ping()  
            logger.info("Connexion Redis établie avec succès")
            return client
        except Exception as e:
            logger.warning(f"Échec de la connexion Redis: {str(e)}")
            return None
    
    def _generate_cache_key(self, question: str, context: str = "") -> str:
        """Génère une clé de cache unique basée sur la question et le contexte."""
        content = f"{question}:{context}"
        return f"llm_cache:{hashlib.md5(content.encode()).hexdigest()}"
    
    def _get_cached_response(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Récupère une réponse mise en cache."""
        if not self.redis_client:
            return None
        
        try:
            cached = self.redis_client.get(cache_key)
            return json.loads(cached) if cached else None
        except Exception as e:
            logger.error(f"Erreur lors de la lecture du cache Redis: {str(e)}")
            return None
    
    def _cache_response(self, cache_key: str, response: Dict[str, Any], ttl: int = 86400) -> None:
        """Stocke une réponse dans le cache."""
        if not self.redis_client:
            return
        
        try:
            self.redis_client.setex(
                cache_key,
                ttl,  
                json.dumps(response)
            )
        except Exception as e:
            logger.error(f"Erreur lors de l'écriture dans le cache Redis: {str(e)}")

    def _initialize_llm(self, **kwargs) -> Optional[BaseLLM]:
        """Initialise un modèle LLM selon le type spécifié."""
        try:
            if self.model_type == "hf":
                return self._initialize_hf_model(**kwargs)
            elif self.model_type == "llama":
                return self._initialize_llama_model(**kwargs)
            elif self.model_type == "gemini":
                return self._initialize_gemini_model(**kwargs)
            else:
                logger.error(f"Type de modèle non supporté: {self.model_type}")
                return None
        except Exception as e:
            logger.error(f"Erreur lors de l'initialisation du modèle LLM: {str(e)}")
            logger.debug(traceback.format_exc())  
    
    def _initialize_gemini_model(self, **kwargs) -> BaseLLM:
        """Initialise un modèle Gemini API."""
        api_key = kwargs.get('api_key') or os.environ.get("GOOGLE_API_KEY")
        
        if not api_key:
            logger.error("Clé API Google non trouvée. Définissez GOOGLE_API_KEY dans l'environnement ou passez api_key dans kwargs.")
            raise ValueError("Clé API Google requise pour utiliser Gemini")
        model_name =os.getenv("LLM_MODEL")
        logger.info(f"Initialisation du modèle Gemini: {model_name}")
        
        llm = ChatGoogleGenerativeAI(
            model=model_name,
            google_api_key=api_key,
            temperature=kwargs.get('temperature', 0.7),
            top_p=kwargs.get('top_p', 0.95),
            max_output_tokens=kwargs.get('max_tokens', 1024)
        )
        
        return llm
    
    def _initialize_hf_model(self, **kwargs) -> BaseLLM:
        """Initialise un modèle HuggingFace."""
        model_id = kwargs.get('model_id', "mistralai/Mistral-7B-Instruct-v0.2")
        device = "cuda" if torch.cuda.is_available() else "cpu"
        
        logger.info(f"Chargement du modèle {model_id} sur {device}")
        
        try:
            tokenizer = AutoTokenizer.from_pretrained(model_id)
            model = AutoModelForCausalLM.from_pretrained(
                model_id,
                device_map=device,
                torch_dtype=torch.float16 if device == "cuda" else torch.float32,
                trust_remote_code=True
            )
            
            pipe = pipeline(
                "text-generation",
                model=model,
                tokenizer=tokenizer,
                max_length=kwargs.get('max_length', 1024),
                temperature=kwargs.get('temperature', 0.7),
                top_p=kwargs.get('top_p', 0.95),
                repetition_penalty=kwargs.get('repetition_penalty', 1.15)
            )
            
            llm = HuggingFacePipeline(pipeline=pipe)
            logger.info(f"Modèle HuggingFace initialisé avec succès: {model_id}")
            return llm
        except Exception as e:
            logger.error(f"Erreur lors de l'initialisation du modèle HuggingFace: {str(e)}")
            logger.debug(traceback.format_exc())
            raise      
    def _initialize_llama_model(self, **kwargs) -> BaseLLM:
        """Initialise un modèle Llama.cpp."""
        model_path = kwargs.get('model_path', "models/llama-2-7b-chat.gguf")
        
        if not os.path.exists(model_path):
            logger.error(f"Le chemin du modèle Llama n'existe pas: {model_path}")
            raise FileNotFoundError(f"Modèle non trouvé: {model_path}")
        
        logger.info(f"Chargement du modèle Llama depuis {model_path}")
        
        try:
            llm = LlamaCpp(
                model_path=model_path,
                temperature=kwargs.get('temperature', 0.7),
                max_tokens=kwargs.get('max_tokens', 1024),
                top_p=kwargs.get('top_p', 0.95),
                n_ctx=kwargs.get('n_ctx', 2048),
                verbose=kwargs.get('verbose', False)
            )
            
            logger.info(f"Modèle Llama.cpp initialisé avec succès")
            return llm
        except Exception as e:
            logger.error(f"Erreur lors de l'initialisation du modèle Llama.cpp: {str(e)}")
            logger.debug(traceback.format_exc())
            raise
    
    def create_qa_chain(self, vector_store: VectorStore, **kwargs) -> Optional[RetrievalQA]:
        """Crée une chaîne de question-réponse avec le vector store."""
        if not self.llm:
            logger.error("Le modèle LLM n'est pas initialisé.")
            return None
            
        if not vector_store:
            logger.error("Le vector store n'est pas initialisé.")
            return None
        
        try:
            retriever = vector_store.as_retriever(
                search_type="similarity",
                search_kwargs={"k": kwargs.get('k', 5)}
            )
            
            prompt = kwargs.get('prompt', None)
            
            chain_type_kwargs = {}
            if prompt:
                chain_type_kwargs["prompt"] = prompt
                
            qa_chain = RetrievalQA.from_chain_type(
                llm=self.llm,
                chain_type="stuff",
                retriever=retriever,
                return_source_documents=True,
                chain_type_kwargs=chain_type_kwargs
            )
            
            logger.info("Chaîne QA créée avec succès")
            return qa_chain
        except Exception as e:
            logger.error(f"Erreur lors de la création de la chaîne QA: {str(e)}")
            logger.debug(traceback.format_exc()) 
            return None
    
    def answer_question(self, qa_chain: RetrievalQA, question: str) -> Dict[str, Any]:
        """Répond à une question en utilisant la chaîne QA avec cache Redis."""
        try:
            if not qa_chain:
                error_msg = "La chaîne QA n'est pas initialisée."
                logger.error(error_msg)
                return {"answer": "Service indisponible. Veuillez réessayer plus tard.", "error": error_msg, "success": False}
            
            if not question or not isinstance(question, str) or len(question.strip()) < 2:
                error_msg = f"Question invalide: '{question}'"
                logger.warning(error_msg)
                return {"answer": "Veuillez poser une question plus détaillée.", "error": error_msg, "success": False}

            logger.info(f"Traitement de la question: '{question}'")
            
            cache_key = self._generate_cache_key(question)
            cached_response = self._get_cached_response(cache_key)
            if cached_response:
                logger.info("Réponse récupérée depuis le cache")
                return {"result": cached_response.get("answer"), "source_documents": []}

            try:
                result = qa_chain.invoke({"query": question})  
                
                if not result or "result" not in result:
                    error_msg = "Réponse vide du modèle"
                    logger.error(error_msg)
                    return {"answer": "Désolé, je n'ai pas pu générer de réponse.", "error": error_msg, "success": False}
                
                self._cache_response(cache_key, {"answer": result["result"]})
                
                return {
                    "result": result["result"],
                    "source_documents": result.get("source_documents", []),
                    "success": True
                }
                
            except Exception as e:
                error_msg = f"Erreur Gemini: {str(e)}"
                logger.error(f"Erreur lors de la réponse à la question: {error_msg}")
                logger.debug(traceback.format_exc())
                logger.error(f"Erreur complète lors de la réponse: {error_msg}")
                logger.error(f"Traceback: {traceback.format_exc()}") 
                return {
                    "answer": "Je rencontre des difficultés techniques. Veuillez reformuler votre question.",
                    "error": error_msg,
                    "success": False
                }
                
        except Exception as e:
            error_msg = f"Erreur système: {str(e)}"
            logger.critical(f"Erreur critique dans answer_question: {error_msg}")
            logger.debug(traceback.format_exc())
            return {
                "answer": "Une erreur inattendue est survenue.",
                "error": error_msg,
                "success": False
            }