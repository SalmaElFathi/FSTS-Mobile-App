import logging
import re
import os
from typing import List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime
import unicodedata
from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter, TextSplitter

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class FSSTChunker:
    
    def __init__(
        self,
        chunk_size: int = 1000,
        chunk_overlap: int = 200,
        separators: Optional[List[str]] = None,
        config_path: Optional[str] = None
    ):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        
        self.default_separators = [
            "\n\n## ", "\n## ", "\n\n### ", "\n### ",
            "\n\n", ". ", "! ", "? ", "\n", " ", ""
        ]
        
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            separators=separators or self.default_separators,
            length_function=len,
            add_start_index=True,
            keep_separator=True,
            is_separator_regex=False
        )
        
        self.section_splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size * 2,
            chunk_overlap=chunk_overlap * 2,
            separators=["\n\n## ", "\n## ", "\n\n### ", "\n### ", "\n\n", "\n", ". ", " ", ""],
            length_function=len,
            add_start_index=True,
            keep_separator=True
        )
        
        if config_path and os.path.exists(config_path):
            self._load_config(config_path)
        else:
            self._set_default_config()
    
    def _set_default_config(self):
        self.formation_patterns = {
            "MST_RSI": [
                r"master.*réseaux.*systèmes.*informatiques",
                r"master.*rsi",
                r"réseaux.*systèmes.*informatiques"
            ],
            "MST_GL": [r"master.*génie.*logiciel", r"master.*gl", r"génie.*logiciel"],
            "MST_IA": [r"master.*intelligence.*artificielle", r"master.*ia", r"intelligence.*artificielle"],
            "MST_BD": [r"master.*base.*données", r"master.*big.*data", r"master.*bd", r"big.*data"]
        }
        
        self.section_keywords = {
            "programme": ["programme de la formation", "programme formation", "contenu formation"],
            "objectifs": ["objectifs", "objectif de la formation", "objectifs visés"],
            "competences": ["compétences", "compétences visées", "compétences acquises"],
            "modules": ["modules", "liste des modules", "unités d'enseignement"],
            "contenu": ["contenu du module", "description du module"],
            "evaluation": ["évaluation", "modalités d'évaluation"],
            "bibliographie": ["bibliographie", "références", "ouvrages de référence"]
        }
        
        self.unicode_replacements = {
            '\uf0a7': '-', '\uf0b7': '-', '\u2022': '-',
            '\u00a0': ' ', '\u2013': '-', '\u2014': '-',
            '\u2018': "'", '\u2019': "'", '\u201c': '"',
            '\u201d': '"', '\u2026': '...', '\u2032': "'", '\u2033': '"'
        }
    
    def _load_config(self, config_path: str):
        import json
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        self.formation_patterns = config.get('formation_patterns', {})
        self.section_keywords = config.get('section_keywords', {})
        self.unicode_replacements = config.get('unicode_replacements', {})
    
    def chunk_documents(self, documents: List[Document]) -> List[Document]:
        if not documents:
            return []
        
        try:
            return self._safe_split_documents(self.splitter, documents)
        except Exception as e:
            logger.error(f"Erreur chunking: {e}")
            fallback = RecursiveCharacterTextSplitter(
                chunk_size=1000,
                chunk_overlap=200,
                separators=["\n\n", "\n", " ", ""]
            )
            return self._safe_split_documents(fallback, documents)
    
    def _normalize_text(self, text: str) -> str:
        if not text:
            return ""
        
        try:
            for char, replacement in self.unicode_replacements.items():
                text = text.replace(char, replacement)
            
            text = unicodedata.normalize('NFKD', text)
            text = ''.join(ch for ch in text if unicodedata.category(ch)[0] != 'C' or ch in '\n\r\t')
            text = text.encode('ascii', 'ignore').decode('ascii')
            
            return text
        except Exception as e:
            logger.error(f"Erreur normalisation: {e}")
            return ''.join(ch for ch in text if ord(ch) < 128)
    
    def _extract_formation_id(self, text: str, filename: str = "") -> str:
        text_lower = text.lower()
        
        if filename:
            filename_lower = filename.lower()
            for formation_id, patterns in self.formation_patterns.items():
                if any(re.search(p, filename_lower, re.I) for p in patterns):
                    return formation_id
        
        for formation_id, patterns in self.formation_patterns.items():
            if any(re.search(p, text_lower, re.I) for p in patterns):
                return formation_id
        
        return "UNKNOWN"
    
    def _extract_metadata(self, text: str, source_file: str = "") -> Dict[str, Any]:
        metadata = {}
        text_lower = text.lower()
        
        metadata["formation_id"] = self._extract_formation_id(text, os.path.basename(source_file))
        
        doc_type_mapping = {
            "descriptif de filière": "filiere",
            "filière": "filiere",
            "descriptif de module": "module",
            "module": "module",
            "emploi du temps": "planning",
            "planning": "planning",
            "examen": "examen",
            "contrôle": "examen"
        }
        
        for key, dtype in doc_type_mapping.items():
            if key in text_lower:
                metadata["document_type"] = dtype
                break
        else:
            metadata["document_type"] = "document"
        
        module_match = re.search(r"module\s+([\w\d]+)\s*:?\s*([^\n]+)", text_lower)
        if module_match:
            metadata["module_code"] = module_match.group(1).strip()
            metadata["module_name"] = module_match.group(2).strip()
        
        semester_match = re.search(r"semestre\s+(\d+)", text_lower)
        if semester_match:
            metadata["semester"] = semester_match.group(1)
        
        if source_file:
            metadata["source"] = os.path.basename(source_file)
        
        metadata["processed_at"] = datetime.now().strftime("%Y-%m-%d")
        
        return metadata
    
    def _enrich_metadata(self, chunk: Document, source_metadata: Dict, chunk_index: int) -> Dict[str, Any]:
        formation_id = source_metadata.get('formation_id', 'UNK')
        doc_type = source_metadata.get('document_type', 'document')
        
        return {
            "chunk_id": f"{formation_id}_{chunk_index}",
            "source": source_metadata.get("source", "unknown"),
            "formation_id": formation_id,
            "document_type": doc_type,
            "chunk_index": chunk_index,
            "processed_at": source_metadata.get("processed_at", datetime.now().strftime("%Y-%m-%d")),
            **{k: v for k, v in source_metadata.items() if k not in ["source", "formation_id", "document_type", "processed_at"]}
        }
    
    def _calculate_structure_confidence(self, text: str) -> float:
        if not text.strip():
            return 0.0
        
        lines = text.split('\n')
        total_lines = len(lines)
        
        if total_lines < 2:
            return 0.0
        
        table_indicators = sum(1 for line in lines if '|' in line and line.count('|') > 2)
        table_indicators += sum(1 for line in lines if any(sep in line for sep in ['+---', '----']))
        
        bullet_points = sum(1 for line in lines if line.strip().startswith(('- ', '* ', '• ', '\u2022 ')))
        numbered_lists = sum(1 for line in lines if re.match(r'^\s*\d+\.\s+', line))
        
        table_score = min(1.0, (table_indicators / total_lines) * 3)
        bullet_score = min(1.0, (bullet_points / total_lines) * 2)
        number_score = min(1.0, (numbered_lists / total_lines) * 2)
        
        confidence = max(table_score, bullet_score, number_score)
        
        if total_lines < 3 and confidence < 0.7:
            confidence *= 0.7
        
        return min(max(confidence, 0.0), 1.0)
    
    def _is_structured_content(self, text: str, min_confidence: float = 0.6) -> bool:
        if not text.strip():
            return False
        
        simple_checks = [
            '|' in text and text.count('|') > 3,
            any(marker in text for marker in ['+---', '----', '====']),
            sum(1 for line in text.split('\n') if line.strip().startswith(('- ', '* ', '• '))) > 2,
            sum(1 for line in text.split('\n') if re.match(r'^\s*\d+\.\s+', line)) > 2
        ]
        
        if any(simple_checks):
            return self._calculate_structure_confidence(text) >= min_confidence
        
        return self._calculate_structure_confidence(text) >= min_confidence
    
    def _safe_split_documents(self, splitter: TextSplitter, documents: List[Document]) -> List[Document]:
        try:
            all_chunks = []
            
            for doc in documents:
                if not doc.page_content.strip():
                    continue
                
                normalized_content = self._normalize_text(doc.page_content)
                confidence = self._calculate_structure_confidence(normalized_content)
                is_structured = confidence >= 0.6
                
                if is_structured:
                    logger.debug(f"Structuré détecté (confiance: {confidence:.2f})")
                    chunks = self.section_splitter.split_documents([Document(
                        page_content=normalized_content,
                        metadata={**doc.metadata, 'structure_confidence': confidence, 'content_type': 'structured'}
                    )])
                else:
                    chunks = splitter.split_documents([Document(
                        page_content=normalized_content,
                        metadata={**doc.metadata, 'structure_confidence': confidence, 'content_type': 'unstructured'}
                    )])
                
                for i, chunk in enumerate(chunks):
                    enriched_meta = self._enrich_metadata(chunk, doc.metadata, i)
                    enriched_meta.update({
                        'total_chunks': len(chunks),
                        'is_structured': self._is_structured_content(chunk.page_content)
                    })
                    chunk.metadata = enriched_meta
                
                all_chunks.extend(chunks)
            
            return all_chunks
            
        except Exception as e:
            logger.error(f"Erreur découpage: {e}")
            
            if not documents:
                return []
            
            fallback = RecursiveCharacterTextSplitter(
                chunk_size=500,
                chunk_overlap=100,
                separators=["\n\n", "\n", " ", ""]
            )
            
            try:
                normalized_docs = [
                    Document(
                        page_content=self._normalize_text(doc.page_content),
                        metadata=doc.metadata
                    )
                    for doc in documents
                ]
                return fallback.split_documents(normalized_docs)
            except:
                doc = documents[0]
                return [Document(
                    page_content=self._normalize_text(doc.page_content),
                    metadata=self._extract_metadata(doc.page_content, doc.metadata.get("source", ""))
                )]