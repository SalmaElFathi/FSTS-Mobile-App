import logging
import os
from pathlib import Path
from typing import List, Dict, Union, Any, Optional
import torch
from tqdm import tqdm
from langchain_core.documents import Document
from langchain_huggingface import HuggingFaceEmbeddings
import numpy as np
from datetime import datetime
from uuid import uuid4

try:
    from ..utils.download_model import download_huggingface_model
except ImportError:
    from src.utils.download_model import download_huggingface_model

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class FSSTEmbedder:

    def __init__(
        self,
        model_name: str = None,
        device: str = None,
        batch_size: int = 32,
        max_length: int = 512,
        local_model_path: str = None,
        fallback_model: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        config_path: Optional[str] = None
    ):
        model_name = model_name or os.getenv("EMBEDDING_MODEL")
        
        if local_model_path and model_name:
            self.model_path = download_huggingface_model(
                model_name=model_name,
                local_path=local_model_path,
                force_redownload=False
            )
            model_name = str(self.model_path)

        self.model_name = model_name or fallback_model
        self.batch_size = batch_size
        self.max_length = max_length
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.fallback_model = fallback_model

        logger.info(f"Initialisation modèle sur {self.device}")
        
        if config_path and os.path.exists(config_path):
            self._load_config(config_path)
        else:
            self._set_default_keywords()
        
        self._init_model()

    def _set_default_keywords(self):
        self.domain_keywords = {
            "mst": 1.5,
            "master": 1.5,
            "formation": 1.1,
            "fsts": 1.3,
            "settat": 1.3,
            "sciences": 1.1,
            "techniques": 1.1,
            "module": 1.2,
            "semestre": 1.2
        }
    
    def _load_config(self, config_path: str):
        import json
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            self.domain_keywords = config.get('domain_keywords', {})
        except Exception as e:
            logger.error(f"Erreur chargement config: {e}")
            self._set_default_keywords()

    def _init_model(self):
        try:
            logger.info(f"Chargement modèle: {self.model_name}")
            self.model = HuggingFaceEmbeddings(
                model_name=self.model_name,
                model_kwargs={
                    "device": self.device,
                    "trust_remote_code": True,
                    "max_length": self.max_length
                },
                encode_kwargs={
                    "batch_size": self.batch_size,
                    "normalize_embeddings": True,
                    "show_progress_bar": True
                }
            )
            self.mode = "langchain"
            logger.info("Modèle principal chargé")
        except Exception as e:
            logger.warning(f"Échec modèle principal: {e}")
            if self.fallback_model:
                logger.info(f"Tentative fallback: {self.fallback_model}")
                try:
                    self.model = HuggingFaceEmbeddings(
                        model_name=self.fallback_model,
                        model_kwargs={"device": self.device, "trust_remote_code": True},
                        encode_kwargs={"batch_size": self.batch_size, "normalize_embeddings": True}
                    )
                    self.mode = "langchain"
                    logger.info("Modèle fallback chargé")
                except Exception as fallback_error:
                    logger.error(f"Échec fallback: {fallback_error}")
                    raise RuntimeError("Impossible de charger un modèle d'embedding")
            else:
                raise

    def _validate_documents(self, documents: List[Union[Document, Dict[str, Any]]]):
        required_metadata = ["formation_id", "source"]
        
        for i, doc in enumerate(documents[:10]):
            if not isinstance(doc, (Document, dict)):
                raise TypeError(f"Document {i} invalide. Type: {type(doc)}")
            
            metadata = doc.metadata if isinstance(doc, Document) else doc
            
            for key in required_metadata:
                if key not in metadata:
                    logger.warning(f"Document {i} manque: {key}")
                    
                    if key == "formation_id" and ("filename" in metadata or "source" in metadata):
                        filename = metadata.get("filename", metadata.get("source", ""))
                        import re
                        match = re.search(r"MST_([A-Z]{2,4})_FST", str(filename))
                        if match:
                            formation_id = match.group(1)
                            if isinstance(doc, Document):
                                doc.metadata["formation_id"] = formation_id
                            else:
                                doc["formation_id"] = formation_id
                            logger.info(f"Extraction auto formation_id: {formation_id}")
                    
                    if key == "source" and "filename" in metadata:
                        if isinstance(doc, Document):
                            doc.metadata["source"] = metadata["filename"]
                        else:
                            doc["source"] = metadata["filename"]

    def _ensure_document_ids(self, documents: List[Document]) -> None:
        for i, doc in enumerate(documents):
            if not doc.metadata.get('chunk_id'):
                formation_id = doc.metadata.get('formation_id', 'UNKNOWN')
                doc.metadata['chunk_id'] = f"{formation_id}_{uuid4().hex[:6]}"
            
            if not doc.metadata.get('chunk_index'):
                doc.metadata['chunk_index'] = i

    def _augment_text_with_metadata(self, doc: Union[Document, Dict[str, Any]]) -> str:
        if isinstance(doc, Document):
            metadata = doc.metadata
            text = doc.page_content
        else:
            metadata = doc
            text = doc.get("text", doc.get("page_content", ""))

        enrichment_parts = []
        
        if metadata.get("formation_name"):
            enrichment_parts.append(f"FORMATION: {metadata['formation_name']}")
        if metadata.get("formation_type"):
            enrichment_parts.append(f"TYPE: {metadata['formation_type']}")
        if metadata.get("niveau"):
            enrichment_parts.append(f"NIVEAU: {metadata['niveau']}")
        if metadata.get("departement"):
            enrichment_parts.append(f"DEPARTEMENT: {metadata['departement']}")
        
        if metadata.get("credits"):
            enrichment_parts.append(f"CREDITS: {metadata['credits']} ECTS")
        if metadata.get("responsables"):
            try:
                if isinstance(metadata["responsables"], list):
                    if all(isinstance(r, dict) for r in metadata["responsables"]):
                        responsables = ", ".join([r.get("nom", "") for r in metadata["responsables"] if "nom" in r])
                        if responsables:
                            enrichment_parts.append(f"RESPONSABLES: {responsables}")
                    elif all(isinstance(r, str) for r in metadata["responsables"]):
                        enrichment_parts.append(f"RESPONSABLES: {', '.join(metadata['responsables'])}")
            except (TypeError, KeyError):
                pass
        
        if metadata.get("semestre"):
            enrichment_parts.append(f"SEMESTRE: {metadata['semestre']}")
        if metadata.get("module_code"):
            enrichment_parts.append(f"MODULE: {metadata['module_code']}")
        if metadata.get("module_name"):
            enrichment_parts.append(f"INTITULE_MODULE: {metadata['module_name']}")
        if metadata.get("section_type"):
            enrichment_parts.append(f"SECTION: {metadata['section_type'].upper()}")
        
        if metadata.get("formation_id"):
            enrichment_parts.append(f"ID_FORMATION: {metadata['formation_id']}")
        if metadata.get("chunk_id"):
            enrichment_parts.append(f"ID_CHUNK: {metadata['chunk_id']}")
        
        if enrichment_parts:
            return " || ".join(enrichment_parts) + "\n\n" + text
        return text

    def _apply_domain_boost(self, embedding: np.ndarray, text: str) -> np.ndarray:
        text_lower = text.lower()
        boost_factor = 1.0
        
        for keyword, weight in self.domain_keywords.items():
            if keyword in text_lower:
                boost_factor *= weight
                logger.debug(f"Boost '{keyword}': x{weight}")
        
        if boost_factor > 1.0:
            boosted = embedding * boost_factor
            return boosted / np.linalg.norm(boosted)
        return embedding

    def embed_documents(self, documents: List[Union[Document, Dict[str, Any]]]) -> List[Document]:
        if not documents:
            logger.warning("Aucun document à traiter")
            return []

        try:
            self._validate_documents(documents)
            
            processed_docs = []
            for i, doc in enumerate(documents):
                try:
                    if isinstance(doc, Document):
                        if not hasattr(doc, 'metadata') or doc.metadata is None:
                            doc.metadata = {}
                        
                        if 'chunk_id' not in doc.metadata:
                            doc.metadata['chunk_id'] = f"doc_{i}_{str(uuid4())[:8]}"
                        if 'source' not in doc.metadata:
                            doc.metadata['source'] = f"document_{i}"
                            
                        processed_docs.append(doc)
                        
                    elif isinstance(doc, dict):
                        content = doc.get("text", doc.get("page_content", ""))
                        
                        metadata = {k: v for k, v in doc.items() 
                                  if k not in ["text", "page_content", "metadata"]}
                        
                        if "metadata" in doc and isinstance(doc["metadata"], dict):
                            metadata.update(doc["metadata"])
                        
                        if 'chunk_id' not in metadata:
                            metadata['chunk_id'] = f"doc_{i}_{str(uuid4())[:8]}"
                        if 'source' not in metadata:
                            metadata['source'] = f"document_{i}"
                        
                        processed_docs.append(Document(page_content=content, metadata=metadata))
                    else:
                        logger.warning(f"Type non géré index {i}: {type(doc)}")
                        
                except Exception as e:
                    logger.error(f"Erreur document {i}: {e}", exc_info=True)
                    continue
            
            self._ensure_document_ids(processed_docs)
            
            texts = []
            for doc in processed_docs:
                augmented_text = self._augment_text_with_metadata(doc)
                doc.page_content = augmented_text
                texts.append(augmented_text)

            embeddings = []
            for i in tqdm(range(0, len(texts), self.batch_size), 
                         desc="Génération embeddings", 
                         unit="batch"):
                batch = texts[i:i + self.batch_size]
                try:
                    batch_embeddings = self.model.embed_documents(batch)
                    
                    for j, (text, embedding) in enumerate(zip(batch, batch_embeddings)):
                        emb_array = np.array(embedding)
                        boosted_emb = self._apply_domain_boost(emb_array, text)
                        batch_embeddings[j] = boosted_emb.tolist()
                    
                    embeddings.extend(batch_embeddings)
                except Exception as e:
                    logger.error(f"Erreur batch {i}: {e}")
                    empty_embedding = np.zeros(self.model.client.get_sentence_embedding_dimension())
                    embeddings.extend([empty_embedding.tolist() for _ in range(len(batch))])

            for doc, embedding in zip(processed_docs, embeddings):
                doc.metadata["embedding"] = embedding
                doc.metadata["embedding_generated_at"] = datetime.now().isoformat()
                doc.metadata["embedding_version"] = self.model_name
                doc.metadata["embedding_boosted"] = True

            logger.info(f"Embeddings générés: {len(processed_docs)} documents")
            return processed_docs

        except Exception as e:
            logger.error(f"Erreur embed_documents: {e}", exc_info=True)
            raise
    
    def embed_query(self, query: str) -> List[float]:
        try:
            embedding = self.model.embed_query(query)
            emb_array = np.array(embedding)
            boosted_emb = self._apply_domain_boost(emb_array, query)
            return boosted_emb.tolist()
        except Exception as e:
            logger.error(f"Erreur embedding requête: {e}")
            return np.zeros(self.model.client.get_sentence_embedding_dimension()).tolist()
    
    def similarity_search(self, query: str, documents: List[Document], top_k: int = 5) -> List[Document]:
        if not documents:
            logger.warning("Aucun document pour recherche")
            return []
        
        try:
            query_embedding = self.embed_query(query)
            
            document_embeddings = []
            for doc in documents:
                if "embedding" in doc.metadata:
                    document_embeddings.append(doc.metadata["embedding"])
                else:
                    logger.warning(f"Document sans embedding: {doc.metadata.get('chunk_id', 'unknown')}")
                    document_embeddings.append(np.zeros(len(query_embedding)).tolist())
            
            similarities = []
            for i, doc_embedding in enumerate(document_embeddings):
                similarity = self._cosine_similarity(query_embedding, doc_embedding)
                similarities.append((similarity, i))
            
            similarities.sort(reverse=True)
            
            return [documents[idx] for _, idx in similarities[:top_k]]
        except Exception as e:
            logger.error(f"Erreur recherche similarité: {e}")
            return []
    
    def _cosine_similarity(self, vec1: List[float], vec2: List[float]) -> float:
        try:
            np_vec1 = np.array(vec1)
            np_vec2 = np.array(vec2)
            
            dot_product = np.dot(np_vec1, np_vec2)
            norm1 = np.linalg.norm(np_vec1)
            norm2 = np.linalg.norm(np_vec2)
            
            if norm1 == 0 or norm2 == 0:
                return 0.0
            
            return dot_product / (norm1 * norm2)
        except Exception as e:
            logger.error(f"Erreur similarité cosinus: {e}")
            return 0.0