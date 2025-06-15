import os
import time
import logging
from typing import List, Dict, Any, Optional
from functools import wraps
from supabase import create_client, Client
from langchain.schema import Document
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def retry_with_backoff(retries=3, backoff_in_seconds=1):
    """Décorateur pour réessayer les opérations avec un délai exponentiel"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempts = 0
            while True:
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    attempts += 1
                    if attempts > retries:
                        logger.error(f"Échec après {retries} tentatives: {str(e)}")
                        raise
                    sleep_time = backoff_in_seconds * (2 ** (attempts - 1))
                    logger.warning(f"Opération échouée: {str(e)}. Nouvelle tentative dans {sleep_time} secondes...")
                    time.sleep(sleep_time)
        return wrapper
    return decorator

class SupabaseManager:
    def __init__(self):
        self.url = os.getenv("SUPABASE_URL")
        self.key = os.getenv("SUPABASE_KEY")
        
        if not self.url or not self.key:
            raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set")
        
        self.client: Client = create_client(self.url, self.key)
        logger.info("Supabase client initialized")
    
    def _check_client(self):
        if not self.client:
            raise RuntimeError("Supabase client not initialized")
    
    @retry_with_backoff(retries=5, backoff_in_seconds=2)
    def insert_record(self, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Insert a record with retry logic for timeout handling"""
        try:
            self._check_client()
            response = self.client.table(table).insert(data).execute()
            return response.data[0] if response.data else None
        except Exception as e:
            logger.error(f"Error inserting record into {table}: {str(e)}")
            raise 
    def store_formation(self, formation_data: Dict[str, Any]) -> Dict[str, Any]:
        data = {
            'formation_id': formation_data['formation_id'],
            'name': formation_data.get('formation_name', ''),
            'source': formation_data.get('source', ''),
            'metadata': formation_data.get('metadata', {
                'page_count': formation_data.get('page_count', 0),
                'processed_at': formation_data.get('processed_at', datetime.now().isoformat()),
            })
        }
        try:
            return self.insert_record('formations', data) or {}
        except Exception as e:
            logger.error(f"Échec stockage formation {formation_data['formation_id']}: {str(e)}")
            return {}
    
    def store_chunk(self, chunk_data: Dict[str, Any]) -> Dict[str, Any]:
        """Store chunk with smaller embedding batches if needed"""
        embedding = chunk_data.get('embedding', [])
        if len(str(embedding)) > 100000:  
            logger.warning(f"Embedding de grande taille détecté pour chunk {chunk_data['chunk_id']}")
        
        data = {
            'chunk_id': chunk_data['chunk_id'],
            'formation_id': chunk_data['formation_id'],
            'chunk_index': chunk_data.get('chunk_index', 0),
            'text': chunk_data['text'],
            'embedding': embedding,
            'metadata': chunk_data.get('metadata', {})
        }
        
        try:
            return self.insert_record('chunks', data) or {}
        except Exception as e:
            logger.error(f"Échec stockage chunk {chunk_data['chunk_id']}: {str(e)}")
            if "timeout" in str(e).lower() or "too large" in str(e).lower():
                try:
                    logger.warning(f"Tentative de stockage sans embedding pour {chunk_data['chunk_id']}")
                    data_without_embedding = data.copy()
                    data_without_embedding['embedding'] = [] 
                    return self.insert_record('chunks', data_without_embedding) or {}
                except Exception as e2:
                    logger.error(f"Échec stockage sans embedding: {str(e2)}")
            return {}
    
    def store_document(self, title: str, **metadata) -> Optional[str]:
        result = self.insert_record('documents', {
            'title': title,
            **metadata
        })
        return result.get('id') if result else None
    
    @retry_with_backoff(retries=3, backoff_in_seconds=1)
    def search_similar_chunks(self, embedding: List[float], limit: int = 5) -> List[Dict[str, Any]]:
        try:
            self._check_client()
            result = self.client.rpc(
                'match_chunks',
                {
                    'query_embedding': embedding,
                    'match_threshold': 0.7,
                    'match_count': limit
                }
            ).execute()
            return result.data
        except Exception as e:
            logger.error(f"Error in vector search: {str(e)}")
            raise  
    
    def formation_exists(self, formation_id: str) -> bool:
        """
        Check if a formation with the given ID exists in the database
        
        Args:
            formation_id: The ID of the formation to check
            
        Returns:
            bool: True if the formation exists, False otherwise
        """
        try:
            self._check_client()
            response = self.client.table('formations').select('formation_id').eq('formation_id', formation_id).execute()
            return len(response.data) > 0
        except Exception as e:
            logger.error(f"Error checking if formation exists: {str(e)}")
            return False