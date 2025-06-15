import os
import json
import logging
from typing import List, Optional, Union
from pathlib import Path
import numpy as np

from langchain_core.documents import Document
from langchain.embeddings.base import Embeddings
from langchain_community.vectorstores import FAISS
from langchain_community.docstore.in_memory import InMemoryDocstore  # 🔥 ajout important

import faiss  
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class NumpyEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        return json.JSONEncoder.default(self, obj)

class VectorStoreManager:
    def __init__(
        self, 
        embedding_model: Embeddings,
        persist_directory: str = "data/vector_store"
    ):
        self.embedding_model = embedding_model
        self.persist_directory = Path(persist_directory)
        self.persist_directory.mkdir(parents=True, exist_ok=True)
        self.index_path = self.persist_directory / "index.faiss"
        self.metadata_path = self.persist_directory / "index.json"

    def _validate_document(self, doc: Union[Document, dict, str], index: int) -> Optional[Document]:
        """Convertit et valide un document pour FAISS en conservant toutes les métadonnées"""
        try:
            logger.debug(f"Validation document {index} de type {type(doc)}")
            
            if isinstance(doc, Document):
                if not hasattr(doc, 'metadata') or doc.metadata is None:
                    doc.metadata = {}
                
                if not doc.metadata.get('chunk_id'):
                    doc.metadata['chunk_id'] = f"doc_{index}_{str(uuid4())[:8]}"
                if 'source' not in doc.metadata:
                    doc.metadata['source'] = f"document_{index}"
                    
                logger.debug(f"Document {index} est déjà un Document LangChain avec métadonnées: {list(doc.metadata.keys())}")
                return doc
            
            if isinstance(doc, dict):
                content = doc.get("text", doc.get("page_content", ""))
                
                metadata = {k: v for k, v in doc.items() 
                          if k not in ["text", "page_content", "metadata"]}
                
                if "metadata" in doc and isinstance(doc["metadata"], dict):
                    metadata.update(doc["metadata"])
                
                if 'chunk_id' not in metadata:
                    metadata['chunk_id'] = f"doc_{index}_{str(uuid4())[:8]}"
                if 'source' not in metadata:
                    metadata['source'] = f"document_{index}"
                
                logger.debug(f"Conversion dict->Document pour l'index {index} avec métadonnées: {list(metadata.keys())}")
                return Document(page_content=content, metadata=metadata)
            
            if isinstance(doc, str):
                logger.debug(f"Conversion string->Document pour l'index {index}")
                return Document(
                    page_content=doc, 
                    metadata={
                        "source": f"converted_string_{index}",
                        "chunk_id": f"str_{index}_{str(uuid4())[:8]}",
                        "content_type": "text/plain"
                    }
                )
            
            logger.warning(f"Type de document non géré à l'index {index}: {type(doc)}")
            return None
        except Exception as e:
            logger.error(f"Erreur de validation document {index}: {str(e)}")
            return None

    def create_vector_store(self, documents):
        logger.info(f"***********************************************")
        logger.info(f"Type de documents: {type(documents)}")

        try:
            logger.info(f"Début de la validation de {len(documents)} documents")
            valid_docs = []
            for i, doc in enumerate(documents):
                validated_doc = self._validate_document(doc, i)
                if validated_doc:
                    valid_docs.append(validated_doc)
                    logger.info(f"Document valide {i}: type={type(validated_doc)}, content={validated_doc.page_content[:50]}..., metadata={list(validated_doc.metadata.keys())}")
                else:
                    logger.warning(f"Document {i} invalide: type={type(doc)}")

            logger.info(f"Après validation: {len(valid_docs)}/{len(documents)} documents valides")

            if not valid_docs:
                logger.error("Aucun document valide pour le vector store.")
                return None

            logger.info(f"Création du vector store avec {len(valid_docs)} documents valides")

            vector_store = FAISS.from_documents(
                documents=valid_docs,
                embedding=self.embedding_model
            )

            os.makedirs(self.persist_directory, exist_ok=True)
            self.save_faiss(vector_store)
            logger.info(f"Vector store sauvegardé dans {self.persist_directory}")
            return vector_store

        except Exception as e:
            logger.error(f"Erreur création FAISS depuis documents: {e}", exc_info=True)
            return None

    def _load_faiss_format(self, load_path: Path, index_file: Path, json_file: Path) -> Optional[FAISS]:
        """Charge un vector store au format FAISS (.faiss + .json)"""
        try:
            logger.info(f"Chargement de l'index FAISS depuis {load_path}")
            
            index = faiss.read_index(str(index_file))
            
            with open(json_file, 'r', encoding='utf-8') as f:
                metadata = json.load(f)
            
            docs = {}
            for doc_id, doc_data in metadata["docstore"].items():
                meta = doc_data.get("metadata", {})
                
                doc = Document(
                    page_content=doc_data["page_content"],
                    metadata=meta
                )
                docs[doc_id] = doc
            
            docstore = InMemoryDocstore(docs)

            index_to_docstore_id = {int(k): v for k, v in metadata["index_to_docstore_id"].items()}

            try:
                vector_store = FAISS(
                    embedding_function=self.embedding_model.embed_query,
                    index=index,
                    docstore=docstore,
                    index_to_docstore_id=index_to_docstore_id
                )
            except TypeError:
                vector_store = FAISS(
                    embedding=self.embedding_model,
                    index=index,
                    docstore=docstore,
                    index_to_docstore_id=index_to_docstore_id
                )
            
            logger.info(f"Index FAISS chargé depuis {load_path} avec {len(docs)} documents")
            return vector_store
            
        except Exception as e:
            logger.error(f"Erreur lors du chargement du format FAISS: {str(e)}", exc_info=True)
            return None
            
    def _load_pickle_format(self, pkl_file: Path) -> Optional[FAISS]:
        """Charge un vector store depuis un fichier pickle (.pkl)"""
        try:
            logger.info(f"Chargement du vector store depuis le fichier pickle: {pkl_file}")
            import pickle
            
            with open(pkl_file, 'rb') as f:
                vector_store = pickle.load(f)
                
            if not isinstance(vector_store, FAISS):
                logger.error(f"Le fichier {pkl_file} ne contient pas un objet FAISS valide")
                return None
                
            logger.info(f"Vector store chargé depuis {pkl_file} avec succès")
            return vector_store
            
        except Exception as e:
            logger.error(f"Erreur lors du chargement du fichier pickle {pkl_file}: {str(e)}", exc_info=True)
            return None
            
    def load_faiss(self, path: str = None) -> Optional[FAISS]:
        """Charge l'index FAISS depuis le disque avec métadonnées au format JSON ou pickle"""
        load_path = Path(path) if path else self.persist_directory
        
        index_file = load_path / "index.faiss"
        json_file = load_path / "index.json"
        
        pkl_file = load_path / "index.pkl"
        
        if index_file.exists() and json_file.exists():
            return self._load_faiss_format(load_path, index_file, json_file)
        elif pkl_file.exists():
            return self._load_pickle_format(pkl_file)
        else:
            logger.warning(f"Aucun format de vector store valide trouvé dans {load_path}")
            return None

        try:
            logger.info(f"Chargement de l'index FAISS depuis {load_path}")
            
            index = faiss.read_index(str(index_file))
            
            with open(json_file, 'r', encoding='utf-8') as f:
                metadata = json.load(f)
            
            docs = {}
            for doc_id, doc_data in metadata["docstore"].items():
                meta = doc_data.get("metadata", {})
                
                doc = Document(
                    page_content=doc_data["page_content"],
                    metadata=meta
                )
                docs[doc_id] = doc
            
            docstore = InMemoryDocstore(docs)  # ✅

            index_to_docstore_id = {int(k): v for k, v in metadata["index_to_docstore_id"].items()}

            
            try:
                vector_store = FAISS(
                    embedding_function=self.embedding_model.embed_query,
                    index=index,
                    docstore=docstore,
                    index_to_docstore_id=index_to_docstore_id
                )
            except TypeError:
                try:
                    vector_store = FAISS(
                        embedding=self.embedding_model,
                        index=index,
                        docstore=docstore,
                        index_to_docstore_id=index_to_docstore_id
                    )
                except Exception as e:
                    logger.error(f"Erreur avec les deux méthodes d'initialisation FAISS: {str(e)}")
                    raise
            
            logger.info(f"Index FAISS chargé depuis {load_path} avec {len(docs)} documents")
            return vector_store
        except Exception as e:
            logger.error(f"Erreur chargement FAISS: {str(e)}", exc_info=True)
            return None

    def create_vector_store_from_texts(self, documents: List[Document]) -> Optional[FAISS]:
        """Crée un vector store à partir des textes extraits des documents"""
        if not documents:
            logger.warning("Aucun document fourni")
            return None
        
        try:
            texts = [doc.page_content for doc in documents]
            metadatas = [doc.metadata for doc in documents]

            logger.info(f"Création du vector store avec {len(texts)} textes")
            vector_store = FAISS.from_texts(
                texts=texts,
                embedding=self.embedding_model,
                metadatas=metadatas
            )
            logger.info("Vector store FAISS créé avec succès")
            return vector_store
        except Exception as e:
            logger.error(f"Erreur création FAISS depuis textes: {str(e)}", exc_info=True)
            return None

    def get_or_create_vector_store(self, documents: List[Union[Document, dict, str]]) -> Optional[FAISS]:
        """Obtient ou crée un vector store"""
        vector_store = self.load_faiss()
        
        if vector_store is None:
            logger.info("Aucun vector store existant, création d'un nouveau")
            vector_store = self.create_vector_store(documents)
        
        return vector_store

    def save_faiss(self, vector_store, path=None):
        """Sauvegarde un vectorstore FAISS sur le disque avec métadonnées en JSON"""
        save_path = Path(path) if path else self.persist_directory
        save_path.mkdir(parents=True, exist_ok=True)
        
        try:
            logger.info(f"Sauvegarde du vector store dans {save_path}")
            
            faiss_path = save_path / "index.faiss"
            faiss.write_index(vector_store.index, str(faiss_path))
            
            metadata = {
                "docstore": {},
                "index_to_docstore_id": {}
            }
            
            for doc_id, doc in vector_store.docstore._dict.items():
                metadata["docstore"][doc_id] = {
                    "page_content": doc.page_content,
                    "metadata": doc.metadata
                }
            
            for idx, doc_id in vector_store.index_to_docstore_id.items():
                metadata["index_to_docstore_id"][str(idx)] = doc_id
            
            json_path = save_path / "index.json"
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump(metadata, f, ensure_ascii=False, indent=2, cls=NumpyEncoder)
            
            logger.info(f"Vector store sauvegardé avec succès dans {save_path}")
            return True
        except Exception as e:
            logger.error(f"Erreur lors de la sauvegarde du vector store: {str(e)}", exc_info=True)
            return False
