import os
import sys
from pathlib import Path
from typing import List
from tqdm.auto import tqdm
from langchain_core.documents import Document
from datetime import datetime
import time
import argparse
import logging

logger = logging.getLogger(__name__)

sys.path.append(str(Path(__file__).parent.parent))

from src.utils.config import load_dotenv, DATA_DIR, VECTOR_STORE_DIR, validate_config
from src.data_processing.extraction import EnhancedFSSTPDFProcessor
from src.data_processing.cleaning import FSSTTextCleaner
from src.data_processing.chunking import FSSTChunker
from src.data_processing.embedding import FSSTEmbedder
from src.database.vector_store import VectorStoreManager
from src.utils.cache_manager import PipelineCache

os.environ['HF_HUB_DISABLE_SYMLINKS_WARNING'] = '1'

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("pipeline.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


def validate_documents(documents: List[Document], stage: str) -> bool:
    if not documents:
        logger.warning(f"Aucun document à {stage}")
        return False
    
    for i, doc in enumerate(documents[:3]):
        logger.info(f"{stage} - Document {i} type: {type(doc)}")
        if not isinstance(doc, Document):
            logger.error(f"{stage} - Document {i} invalide: {type(doc)}")
            return False
        if not doc.page_content.strip():
            logger.warning(f"Document {i} à {stage} vide")
        else:
            logger.debug(f"Document {i}: {doc.page_content[:50]}...")
    return True


def process_data_pipeline(data_dir: str) -> bool:
    try:
        cache = PipelineCache(cache_dir="src/cache")
        
        if not validate_config():
            raise ValueError("Configuration invalide")
        
        if not os.path.exists(data_dir):
            raise FileNotFoundError(f"Répertoire {data_dir} inexistant")

        pdf_files = list(Path(data_dir).glob("*.pdf"))
        
        if not pdf_files:
            logger.info(f"Aucun PDF dans {data_dir}")
            return True
            
        all_chunks = []
        all_processed = True

        google_api_key = os.environ.get("GOOGLE_API_KEY")
        if not google_api_key:
            logger.warning("Clé API Google absente - extraction LLM limitée")
        else:
            logger.info("Clé API Google trouvée")

        for pdf_file in tqdm(pdf_files, desc="Traitement PDFs"):
            file_path = str(pdf_file)
            file_id = os.path.basename(file_path).replace('.pdf', '')
            
            if cache.is_file_processed(file_path):
                logger.info(f"Fichier {file_path} en cache...")
                chunks = cache.load_intermediate_result("chunks", file_id)
                
                if chunks:
                    logger.info(f"Chargé {len(chunks)} chunks depuis cache")
                    
                    for i, chunk in enumerate(chunks[:3]):
                        if not isinstance(chunk, Document):
                            logger.warning(f"Conversion chunk {i}")
                            if isinstance(chunk, str):
                                chunks[i] = Document(
                                    page_content=chunk, 
                                    metadata={"formation_id": file_id, "chunk_id": f"{file_id}_chunk_{i}"}
                                )
                            elif isinstance(chunk, dict):
                                chunks[i] = Document(
                                    page_content=chunk.get("text", chunk.get("page_content", "")),
                                    metadata=chunk.get("metadata", {"formation_id": file_id, "chunk_id": f"{file_id}_chunk_{i}"})
                                )
                    
                    all_chunks.extend(chunks)
                    all_processed = False
                    continue
            
            all_processed = False
            
            logger.info(f"🔍 Extraction: {file_path}")
            
            pdf_processor = EnhancedFSSTPDFProcessor(data_dir, gemini_api_key=google_api_key)
            raw_docs = pdf_processor.process_pdf(file_path)
            
            if not validate_documents(raw_docs, "extraction"):
                logger.warning(f"Documents invalides après extraction: {file_path}")
                continue
                
            cache.save_intermediate_result("raw_docs", raw_docs, file_id)

            logger.info(f"🧹 Nettoyage: {file_path}")
            cleaner = FSSTTextCleaner()
            cleaned_docs = cleaner.clean_batch(raw_docs)
            
            if not validate_documents(cleaned_docs, "nettoyage"):
                logger.warning(f"Documents invalides après nettoyage: {file_path}")
                continue
                
            cache.save_intermediate_result("cleaned_docs", cleaned_docs, file_id)

            logger.info(f"✂️ Découpage: {file_path}")
            chunker = FSSTChunker(chunk_size=1000, chunk_overlap=200)
            chunks = chunker.chunk_documents(cleaned_docs)
            
            if not validate_documents(chunks, "découpage"):
                logger.warning(f"Documents invalides après découpage: {file_path}")
                continue
            
            for i, chunk in enumerate(chunks):
                if not chunk.metadata:
                    chunk.metadata = {}
                    
                chunk.metadata["chunk_id"] = f"{file_id}_chunk_{i}"
                chunk.metadata["formation_id"] = file_id
                chunk.metadata["chunk_index"] = i
                chunk.metadata["source"] = file_path
                chunk.metadata["processed_at"] = datetime.now().isoformat()
            
            cache.save_intermediate_result("chunks", chunks, file_id)
            all_chunks.extend(chunks)
            
            metadata = {
                "chunk_count": len(chunks),
                "file_name": os.path.basename(file_path)
            }
            cache.mark_file_as_processed(file_path, metadata)
        
        if all_processed:
            logger.info("✅ Tous les documents déjà traités")
            return True

        if not all_chunks:
            logger.info("Aucun document à traiter")
            return True
        
        logger.info(f"🧠 Embeddings pour {len(all_chunks)} chunks")
        
        embedder = FSSTEmbedder()
        
        cached_embeddings = cache.load_intermediate_result("embeddings")
        if cached_embeddings and len(cached_embeddings) >= len(all_chunks) and all(isinstance(doc, Document) for doc in cached_embeddings[:5]):
            logger.info(f"Embeddings depuis cache: {len(cached_embeddings)}")
            chunks_with_embeddings = cached_embeddings
        else:
            logger.info("Génération nouveaux embeddings")
            chunks_with_embeddings = embedder.embed_documents(all_chunks)
            logger.info(f"Embeddings générés: {len(chunks_with_embeddings)}")
            cache.save_intermediate_result("embeddings", chunks_with_embeddings)
        
        if not validate_documents(chunks_with_embeddings, "embeddings"):
            logger.error("Documents invalides après embedding - correction")
            fixed_chunks = []
            for i, doc in enumerate(chunks_with_embeddings):
                if isinstance(doc, Document):
                    fixed_chunks.append(doc)
                elif isinstance(doc, str):
                    fixed_chunks.append(Document(
                        page_content=doc,
                        metadata={"source": f"auto_fixed_{i}"}
                    ))
                elif isinstance(doc, dict):
                    fixed_chunks.append(Document(
                        page_content=doc.get("text", doc.get("page_content", "")),
                        metadata=doc.get("metadata", {})
                    ))
            chunks_with_embeddings = fixed_chunks
            logger.info(f"Correction: {len(fixed_chunks)} documents valides")

        documents_for_vector_store = []
        logger.info("Préparation documents pour vector store")
        
        for i, doc in enumerate(chunks_with_embeddings):
            try:
                if isinstance(doc, str):
                    logger.info(f"[Fix] String -> Document ({i})")
                    document = Document(
                        page_content=doc,
                        metadata={"source": f"auto_{i}"}
                    )
                    documents_for_vector_store.append(document)
                elif isinstance(doc, dict):
                    logger.info(f"[Fix] Dict -> Document ({i})")
                    doc_content = doc.get("text", doc.get("page_content", ""))
                    doc_metadata = doc.get("metadata", {})
                    document = Document(
                        page_content=doc_content,
                        metadata=doc_metadata
                    )
                    documents_for_vector_store.append(document)
                elif isinstance(doc, Document):
                    if not hasattr(doc, 'metadata') or doc.metadata is None:
                        doc.metadata = {}
                    
                    if "embedding" not in doc.metadata:
                        logger.info(f"Génération embedding manquant ({i})")
                        try:
                            doc.metadata["embedding"] = embedder.model.embed_documents([doc.page_content])[0]
                        except Exception as embed_error:
                            logger.warning(f"Échec embedding {i}: {embed_error}")
                    
                    documents_for_vector_store.append(doc)
                else:
                    logger.warning(f"Type inconnu {i}: {type(doc)}")
            except Exception as e:
                logger.error(f"Erreur préparation document {i}: {e}")

        documents_for_vector_store = [
            doc if isinstance(doc, Document) else Document(
                page_content=str(doc),
                metadata={"source": f"auto_converted_{i}"}
            )
            for i, doc in enumerate(documents_for_vector_store)
        ]

        logger.info(f"Documents prêts: {len(documents_for_vector_store)}")
        for i in range(min(3, len(documents_for_vector_store))):
            doc = documents_for_vector_store[i]
            logger.info(f"Document {i}: type={type(doc)}")
            if isinstance(doc, Document):
                logger.info(f"  Content: {doc.page_content[:50]}...")
                logger.info(f"  Metadata: {list(doc.metadata.keys())}")
                if "embedding" in doc.metadata:
                    logger.info(f"  Embedding: {len(doc.metadata['embedding'])} dims")
                else:
                    logger.warning(f"  Document {i} sans embedding!")

        logger.info("🗄️ Vector Store")
        vs_manager = VectorStoreManager(embedding_model=embedder.model)
        
        logger.info(f"Chargement vector store: {VECTOR_STORE_DIR}")
        vector_store = vs_manager.load_faiss(VECTOR_STORE_DIR)
        
        if vector_store:
            logger.info("Vector store existant - ajout documents")
            docs_with_embeddings = []
            for doc in documents_for_vector_store:
                if isinstance(doc, Document):
                    if "embedding" not in doc.metadata:
                        try:
                            doc.metadata["embedding"] = embedder.model.embed_documents([doc.page_content])[0]
                            docs_with_embeddings.append(doc)
                        except Exception as e:
                            logger.warning(f"Impossible générer embedding: {e}")
                    else:
                        docs_with_embeddings.append(doc)
            
            batch_size = 100
            total_docs = len(docs_with_embeddings)
            
            for i in range(0, total_docs, batch_size):
                end_idx = min(i + batch_size, total_docs)
                batch = docs_with_embeddings[i:end_idx]
                logger.info(f"Lot {i//batch_size + 1}/{(total_docs+batch_size-1)//batch_size}: {len(batch)} docs")
                try:
                    vector_store.add_documents(batch)
                except Exception as e:
                    logger.error(f"Erreur lot {i//batch_size + 1}: {e}")
            
            vs_manager.save_faiss(vector_store, VECTOR_STORE_DIR)
            logger.info("Vector store enregistré")
            
        else:
            logger.info("Création nouveau vector store")
            Path(VECTOR_STORE_DIR).parent.mkdir(parents=True, exist_ok=True)
            
            valid_docs = []
            for i, doc in enumerate(documents_for_vector_store):
                if isinstance(doc, Document):
                    if "embedding" not in doc.metadata:
                        try:
                            doc.metadata["embedding"] = embedder.model.embed_documents([doc.page_content])[0]
                        except Exception as e:
                            logger.warning(f"Échec embedding: {e}")
                            continue
                    valid_docs.append(doc)
                elif isinstance(doc, dict):
                    valid_docs.append(Document(
                        page_content=doc.get("text", doc.get("page_content", "")),
                        metadata=doc.get("metadata", {})
                    ))
                elif isinstance(doc, str):
                    valid_docs.append(Document(
                        page_content=doc,
                        metadata={"source": f"auto_converted_{i}"}
                    ))
                else:
                    logger.warning(f"Type non supporté {i}: {type(doc)}")
            
            if not valid_docs:
                logger.error("Aucun document valide")
                return False
                
            logger.info(f"Création vector store: {len(valid_docs)} docs")
            vector_store = vs_manager.create_vector_store(valid_docs)
            
            if vector_store:
                vs_manager.save_faiss(vector_store, VECTOR_STORE_DIR)
                logger.info("Vector store créé")
            else:
                logger.error("Échec création vector store")
                return False

        logger.info("✅ Pipeline réussi!")
        return True

    except Exception as e:
        logger.error(f"❌ Échec pipeline: {e}", exc_info=True)
        return False


def query_document(query: str, data_dir: str):
    try:
        logger.info("Interrogation vector store")
        vs_manager = VectorStoreManager()
        vector_store = vs_manager.load_faiss(VECTOR_STORE_DIR)
        
        if not vector_store:
            return "Erreur: Vector store non initialisé"
        
        embedder = FSSTEmbedder()
        results = vector_store.similarity_search_with_score(
            query, k=int(os.getenv("SEARCH_TOP_K", 5))
        )
        
        if not results:
            return "Aucun résultat"
        
        formatted_results = []
        for doc, score in results:
            formatted_results.append({
                "content": doc.page_content,
                "metadata": doc.metadata,
                "score": float(score)
            })
        
        return formatted_results
    except Exception as e:
        logger.error(f"Erreur interrogation: {e}")
        return f"Erreur: {e}"


if __name__ == "__main__":
    load_dotenv()
    
    parser = argparse.ArgumentParser(description="Traitement PDF")
    parser.add_argument("--query", type=str, help="Question")
    args = parser.parse_args()
    
    data_dir = Path(DATA_DIR)
    data_dir.mkdir(parents=True, exist_ok=True)
    
    if args.query:
        response = query_document(args.query, str(data_dir))
        print("\nRéponse:")
        print(response)
        exit(0)
    
    pdf_files = list(data_dir.glob("*.pdf"))
    if not pdf_files:
        logger.warning(f"Aucun PDF dans {data_dir}")
        print(f"Aucun PDF dans {data_dir}")
        exit(0)
    
    success = process_data_pipeline(data_dir)
    
    if success:
        logger.info("Pipeline réussi!")
        print("✅ Traitement terminé!")
    else:
        logger.error("Pipeline échoué")
        print("❌ Pipeline échoué")
        exit(1)