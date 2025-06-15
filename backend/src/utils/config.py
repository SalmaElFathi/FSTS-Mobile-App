import os
from dotenv import load_dotenv
import logging

# Chargement des variables d'environnement
load_dotenv()

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration générale
DEBUG = os.getenv("DEB" \
"UG", "False").lower() == "true"
DATA_DIR = os.getenv("DATA_DIR", "data/documents")
VECTOR_STORE_DIR = os.getenv("VECTOR_STORE_DIR", "data/vector_store")

# Configurations Supabase
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# Configuration Redis pour le cache
REDIS_URL = os.getenv("REDIS_URL")

# Configuration des modèles
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
LLM_MODEL_TYPE = os.getenv("LLM_MODEL_TYPE", "gemini")  
LLM_MODEL_ID = os.getenv("LLM_MODEL_ID", "mistralai/Mistral-7B-Instruct-v0.2") 
LLM_MODEL_PATH = os.getenv("LLM_MODEL_PATH", "models/llama-2-7b-chat.gguf")

# Configuration du traitement des données
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
CHUNK_METHOD = os.getenv("CHUNK_METHOD", "chars")  # 'chars' ou 'tokens'

# Configuration de l'API Flask
FLASK_HOST = os.getenv("FLASK_HOST", "0.0.0.0")
FLASK_PORT = int(os.getenv("FLASK_PORT", "5000"))
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "False").lower() == "true"

# Vérification des configurations critiques
def validate_config():
    """Valide les configurations critiques."""
    missing_vars = []
    
    # Vérifier les variables obligatoires
    if not SUPABASE_URL:
        missing_vars.append("SUPABASE_URL")
    if not SUPABASE_KEY:
        missing_vars.append("SUPABASE_KEY")
    
    if missing_vars:
        logger.error(f"Variables d'environnement manquantes: {', '.join(missing_vars)}")
        logger.error("Veuillez créer un fichier .env avec les variables requises.")
        return False
    
    return True