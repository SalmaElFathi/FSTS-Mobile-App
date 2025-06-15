# src/utils/download_model.py
from transformers import AutoModel, AutoTokenizer
import os
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def download_huggingface_model(
    model_name: str = "sentence-transformers/all-mpnet-base-v2",
    local_path: str = "./models/all-mpnet-base-v2",
    force_redownload: bool = False
) -> Path:
    """
    Télécharge et sauvegarde un modèle HuggingFace localement
    
    Args:
        model_name: Nom du modèle sur HuggingFace Hub
        local_path: Chemin local pour sauvegarder
        force_redownload: Re-télécharge même si modèle existe déjà
    
    Returns:
        Chemin absolu du modèle sauvegardé
    """
    local_path = Path(local_path).absolute()
    
    if local_path.exists() and not force_redownload:
        logger.info(f"Modèle existe déjà à {local_path}")
        return local_path

    logger.info(f"Début du téléchargement de {model_name}...")
    
    try:
        os.makedirs(local_path, exist_ok=True)
        
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModel.from_pretrained(model_name)
        
        tokenizer.save_pretrained(local_path)
        model.save_pretrained(local_path)
        
        logger.info(f"Modèle sauvegardé avec succès à {local_path}")
        return local_path
        
    except Exception as e:
        logger.error(f"Erreur lors du téléchargement: {str(e)}")
        raise RuntimeError(f"Échec du téléchargement de {model_name}")

if __name__ == "__main__":
    # Exemple d'utilisation
    download_huggingface_model()