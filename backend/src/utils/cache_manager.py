import hashlib
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple, Union
from langchain_core.documents import Document
import logging

logger = logging.getLogger(__name__)

class PipelineCache:
    def __init__(self, cache_dir: str = "cache"):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.processed_files_path = self.cache_dir / "processed_files.json"
        self.processed_files = self.load_processed_files()
        
    def load_processed_files(self) -> Dict[str, Dict]:
        """Charge la liste des fichiers déjà traités"""
        if self.processed_files_path.exists():
            try:
                with open(self.processed_files_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except (json.JSONDecodeError, FileNotFoundError) as e:
                logger.warning(f"Erreur lors du chargement des fichiers traités: {e}")
                return {}
        return {}
    
    def save_processed_files(self) -> None:
        """Sauvegarde la liste des fichiers traités"""
        with open(self.processed_files_path, 'w', encoding='utf-8') as f:
            json.dump(self.processed_files, f, ensure_ascii=False, indent=2)
    
    def get_file_hash(self, file_path: str) -> str:
        """Calcule le hash MD5 d'un fichier"""
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    
    def is_file_processed(self, file_path: str) -> bool:
        """Vérifie si un fichier a déjà été traité"""
        file_path_str = str(file_path)
        file_hash = self.get_file_hash(file_path)
        
        if file_path_str in self.processed_files:
            return self.processed_files[file_path_str]["hash"] == file_hash
        return False
    
    def mark_file_as_processed(self, file_path: str, metadata: Dict = None) -> None:
        """Marque un fichier comme traité"""
        file_path_str = str(file_path)
        self.processed_files[file_path_str] = {
            "hash": self.get_file_hash(file_path),
            "processed_at": datetime.now().isoformat(),
            "metadata": metadata or {}
        }
        self.save_processed_files()
    
    def save_intermediate_result(self, stage: str, data: Union[List[Union[Document, dict]], Set[str]], file_id: str = None) -> None:
        """Sauvegarde les résultats intermédiaires avec support pour les tableaux"""
        file_name = f"{file_id}_{stage}.json" if file_id else f"{stage}.json"
        cache_file = self.cache_dir / file_name
        
        serializable_data = []
        
        if isinstance(data, set):
            serializable_data = list(data)
        else:
            for item in data:
                if isinstance(item, Document):
                    # Nettoyage du texte avant sérialisation
                    clean_content = item.page_content.strip()
                    if clean_content:  # Ignorer les documents vides
                        serializable_data.append({
                            "__type__": "Document",
                            "page_content": clean_content,
                            "metadata": item.metadata
                        })
                elif isinstance(item, dict):
                    # Gestion spéciale des tableaux
                    if "table" in item:
                        serializable_data.append({
                            "__type__": "Table",
                            "data": item["table"],
                            "metadata": item.get("metadata", {})
                        })
                    else:
                        # Nettoyage des valeurs de dictionnaire
                        clean_dict = {k: str(v).strip() for k, v in item.items() if v is not None}
                        if clean_dict:  # Ignorer les dictionnaires vides
                            serializable_data.append({
                                "__type__": "dict", 
                                "data": clean_dict
                            })
                elif isinstance(item, str):
                    clean_str = item.strip()
                    if clean_str:  # Ignorer les chaînes vides
                        serializable_data.append({
                            "__type__": "string",
                            "content": clean_str
                        })
                else:
                    logger.warning(f"Type non sérialisable: {type(item)}")
                    try:
                        str_content = str(item).strip()
                        if str_content:  # Ignorer les chaînes vides
                            serializable_data.append({
                                "__type__": "unknown",
                                "content": str_content
                            })
                    except:
                        logger.error(f"Échec de la sérialisation pour {type(item)}")
                        continue
        
        # Vérification finale avant la sauvegarde
        if not serializable_data:
            logger.warning(f"Aucune donnée valide à sauvegarder pour {file_name}")
            return
        
        try:
            with open(cache_file, 'w', encoding='utf-8') as f:
                json.dump(serializable_data, f, ensure_ascii=False, indent=2)
            logger.info(f"Résultats intermédiaires sauvegardés: {file_name}")
        except Exception as e:
            logger.error(f"Erreur lors de la sauvegarde du cache: {str(e)}")
            logger.error(f"Données problématiques: {serializable_data[:2]}...")  # Log des premières données pour débogage
    
    def load_intermediate_result(self, stage: str, file_id: str = None) -> Union[List[Union[Document, dict]], Set[str]]:
        """Charge les résultats intermédiaires"""
        file_name = f"{file_id}_{stage}.json" if file_id else f"{stage}.json"
        cache_file = self.cache_dir / file_name
        
        if not cache_file.exists():
            logger.debug(f"Fichier cache non trouvé: {file_name}")
            return [] if stage != "db_stored_chunks" else set()
            
        try:
            with open(cache_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            logger.info(f"Chargement des résultats depuis {file_name}: {len(data)} éléments")
            
            if stage == "db_stored_chunks":
                return set(data)
                
            result = []
            for i, item in enumerate(data):
                try:
                    if isinstance(item, str):
                        logger.debug(f"Conversion de la chaîne {i} en Document")
                        result.append(Document(
                            page_content=item,
                            metadata={"source": "from_cache_string"}
                        ))
                    elif isinstance(item, dict):
                        item_type = item.get("__type__", "unknown")
                        logger.debug(f"Traitement de l'élément {i} de type {item_type}")
                        
                        if item_type == "Document":
                            result.append(Document(
                                page_content=item.get("page_content", ""),
                                metadata=item.get("metadata", {})
                            ))
                        elif item_type == "dict":
                            result.append(item.get("data", {}))
                        elif item_type == "string":
                            result.append(Document(
                                page_content=item.get("content", ""),
                                metadata={"source": "from_cache_string_object"}
                            ))
                        else:
                            # Gérer le cas où le dictionnaire n'a pas de __type__ ou type inconnu
                            if "page_content" in item:
                                result.append(Document(
                                    page_content=item["page_content"],
                                    metadata=item.get("metadata", {})
                                ))
                            elif "text" in item:
                                result.append(Document(
                                    page_content=item["text"],
                                    metadata=item.get("metadata", {})
                                ))
                            elif "content" in item:
                                result.append(Document(
                                    page_content=item["content"],
                                    metadata={"source": "from_content"}
                                ))
                            else:
                                # Dernier recours: transformer en Document avec contenu vide
                                result.append(Document(
                                    page_content=str(item),
                                    metadata={"source": "from_cache_unknown", "original": item}
                                ))
                    else:
                        # Cas spécial pour les objets non identifiés
                        logger.warning(f"Type d'élément cache inattendu {i}: {type(item)}")
                        try:
                            result.append(Document(
                                page_content=str(item),
                                metadata={"source": "unknown"}
                            ))
                        except:
                            logger.error(f"Échec de la conversion pour l'élément {i}")
                except Exception as e:
                    logger.error(f"Erreur lors du traitement de l'élément {i}: {e}")
            
            # Debug des premiers éléments chargés
            for i in range(min(3, len(result))):
                if isinstance(result[i], Document):
                    logger.debug(f"Élément chargé {i}: Document, content={result[i].page_content[:50]}...")
                else:
                    logger.debug(f"Élément chargé {i}: {type(result[i])}")
                    
            return result
        except Exception as e:
            logger.error(f"Erreur lors du chargement du cache {file_name}: {e}")
            return [] if stage != "db_stored_chunks" else set()

    def clear_cache(self, older_than_days: int = None) -> None:
        """Efface les fichiers de cache"""
        logger.info(f"Nettoyage du cache dans {self.cache_dir}")
        if older_than_days:
            cutoff = datetime.now().timestamp() - (older_than_days * 86400)
            for cache_file in self.cache_dir.glob("*"):
                if cache_file.stat().st_mtime < cutoff:
                    logger.info(f"Suppression du fichier ancien: {cache_file}")
                    cache_file.unlink()
        else:
            for cache_file in self.cache_dir.glob("*"):
                if cache_file.is_file():
                    logger.info(f"Suppression du fichier: {cache_file}")
                    cache_file.unlink()
            self.processed_files = {}
            if self.processed_files_path.exists():
                self.processed_files_path.unlink()
        logger.info("Nettoyage du cache terminé")