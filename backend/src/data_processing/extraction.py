import logging
import json
import re
from pathlib import Path
import os
import fitz
from PyPDF2 import PdfReader
from dotenv import load_dotenv
from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
import google.generativeai as genai

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EnhancedFSSTPDFProcessor:
    
    def __init__(self, data_dir: str, gemini_api_key: str = None):
        self.data_dir = Path(data_dir)
        self.gemini_api_key = gemini_api_key or os.getenv("GOOGLE_API_KEY")
        
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=8000,
            chunk_overlap=1000,
            length_function=len,
            add_start_index=True,
            separators=["\n\n\n\n", "\n\n\n", "\n\n", "\n", " ", ""]
        )
        
        self.current_module = None
        self.module_content = []
        
        self._configure_gemini()
        
    def _configure_gemini(self):
        try:
            if not self.gemini_api_key:
                logger.warning("Aucune clé API Gemini, désactivation LLM")
                self.use_llm = False
                return
                
            genai.configure(api_key=self.gemini_api_key)
            gemini_model = os.getenv("LLM_MODEL", "gemini-1.5-flash-latest")
            self.model = genai.GenerativeModel(gemini_model)
            self.use_llm = True
            logger.info("Gemini configuré")
                
        except Exception as e:
            logger.error(f"Erreur config Gemini: {e}")
            self.use_llm = False
    
    def _detect_document_type(self, text):
        text_lower = text.lower()
        
        if "descriptif de demande d'accréditation" in text_lower:
            return "descriptif_filiere"
        elif "module" in text_lower and any(sem in text_lower for sem in ["semestre", "s1", "s2", "s3", "s4"]):
            return "descriptif_module"
        elif "coordonnateur" in text_lower or "équipe pédagogique" in text_lower:
            return "equipe_pedagogique"
        else:
            return "document"
    
    def _analyze_table_with_model(self, table_data):
        result = {
            "table_type": "unknown",
            "module_code": None,
            "module_name": None,
            "semestre": None,
            "responsables": [],
            "volume_horaire": {},
            "contenu": [],
            "confiance": "moyenne"
        }
        
        if not table_data or not any(any(cell.strip() if cell else '' for cell in row) for row in table_data):
            result["confiance"] = "basse"
            return result
            
        try:
            cleaned_data = []
            for row in table_data:
                row = [str(cell) if cell is not None else '' for cell in row]
                while row and not row[0].strip():
                    row = row[1:]
                while row and not row[-1].strip():
                    row = row[:-1]
                if any(cell.strip() for cell in row):
                    cleaned_data.append([cell.strip() for cell in row])
            
            if not cleaned_data:
                result["confiance"] = "basse"
                return result
            
            has_header = False
            if len(cleaned_data) > 1:
                first_row_text = " ".join([cell.lower() for cell in cleaned_data[0] if cell and isinstance(cell, str)])
                second_row_text = " ".join([cell.lower() for cell in cleaned_data[1] if cell and isinstance(cell, str)])
                
                if (first_row_text and second_row_text and 
                    len(first_row_text.split()) < len(second_row_text.split()) * 0.8):
                    has_header = True
                    logger.info("En-tête détecté")
            
            if self.use_llm and hasattr(self, 'model'):
                try:
                    table_text = "\n".join([" | ".join(row) for row in cleaned_data])
                    
                    prompt = (
                        "Analyse ce tableau et retourne les informations structurées en JSON. "
                        "Structuration simple, pas d'analyse sémantique.\n\n"
                        f"{table_text}"
                    )
                    
                    response = self.model.generate_content(prompt)
                    
                    if response and hasattr(response, 'text'):
                        try:
                            json_text = response.text
                            json_match = re.search(r'```(?:json\n)?(.*?)```', json_text, re.DOTALL)
                            if json_match:
                                json_text = json_match.group(1)
                            
                            structured_data = json.loads(json_text.strip())
                            
                            if isinstance(structured_data, dict):
                                result.update(structured_data)
                                result["confiance"] = "haute"
                                return result
                                
                        except (json.JSONDecodeError, AttributeError) as e:
                            logger.warning(f"Erreur JSON: {e}")
                except Exception as e:
                    logger.warning(f"Erreur LLM: {e}")
            
            if has_header and len(cleaned_data) > 1:
                try:
                    result["contenu"] = [dict(zip(cleaned_data[0], row)) for row in cleaned_data[1:]]
                except Exception as e:
                    logger.warning(f"Erreur dict: {e}")
                    result["contenu"] = cleaned_data
            else:
                result["contenu"] = cleaned_data
            
            return result
        except Exception as e:
            logger.error(f"Erreur analyse tableau: {e}")
            result["confiance"] = "basse"
            return result

    def _detect_tables_improved(self, page):
        tables = []
        
        blocks = page.get_text("dict", flags=11)
        
        MIN_ROWS = 3
        MIN_COLS = 2
        
        table_blocks = []
        current_table = []
        
        for block in blocks.get("blocks", []):
            if 'lines' not in block:
                continue
                
            if self._is_likely_table_block(block, blocks):
                current_table.append(block)
            elif current_table:
                if len(current_table) >= MIN_ROWS:
                    table_blocks.append(current_table)
                current_table = []
        
        if current_table and len(current_table) >= MIN_ROWS:
            table_blocks.append(current_table)
            
        for block_group in table_blocks:
            table = self._blocks_to_table(block_group)
            if table and len(table) >= MIN_ROWS and len(table[0]) >= MIN_COLS:
                tables.append(table)
                
        return tables
        
    def _is_likely_table_block(self, block, all_blocks):
        if 'lines' not in block:
            return False
            
        x_positions = set()
        for line in block['lines']:
            for span in line['spans']:
                x_positions.add(round(span['bbox'][0], 2))
        
        return len(x_positions) > 1
        
    def _blocks_to_table(self, blocks):
        blocks.sort(key=lambda b: b['bbox'][1])
        
        x_positions = set()
        for block in blocks:
            for line in block['lines']:
                for span in line['spans']:
                    x_positions.add(round(span['bbox'][0], 2))
        
        x_positions = sorted(list(x_positions))
        
        table = []
        for block in blocks:
            row = [''] * (len(x_positions) + 1)
            for line in block['lines']:
                for span in line['spans']:
                    x = round(span['bbox'][0], 2)
                    col = 0
                    for i, pos in enumerate(x_positions):
                        if x >= pos:
                            col = i
                    if not row[col]:
                        row[col] = span['text']
                    else:
                        row[col] += ' ' + span['text']
            table.append([cell.strip() for cell in row if cell.strip()])
            
        return table
    
    def _extract_metadata_with_gemini(self, text):
        if not self.use_llm:
            return {}
            
        try:
            prompt = """
            Extrais les métadonnées académiques de ce texte (formation MST_RSI).
            
            RETOURNE UNIQUEMENT CE JSON:
            
            {
              "formation": {
                "nom": "nom complet",
                "acronyme": "acronyme",
                "type": "type",
                "departement": "département",
                "universite": "université"
              },
              "modules": [
                {
                  "code": "code",
                  "intitule": "intitulé",
                  "semestre": "semestre",
                  "responsable": "responsable"
                }
              ]
            }
            
            Chaîne vide "" si incertain. RIEN D'AUTRE QUE LE JSON.
            """
            
            text_chunk = text[:15000]
            full_prompt = prompt + "\n\nTexte:\n" + text_chunk
            
            response = self.model.generate_content(full_prompt)
            
            if response and hasattr(response, 'text'):
                try:
                    json_text = response.text
                    json_match = re.search(r'```json\s*(.*?)\s*```', json_text, re.DOTALL)
                    if json_match:
                        json_text = json_match.group(1)
                    return json.loads(json_text)
                except json.JSONDecodeError:
                    try:
                        json_text = re.sub(r'^[^{]*', '', response.text)
                        json_text = re.sub(r'[^}]*$', '', json_text)
                        return json.loads(json_text)
                    except:
                        logger.error("Impossible parser JSON")
                        return {}
            
            return {}
        except Exception as e:
            logger.error(f"Erreur extraction LLM: {e}")
            return {}
 
    def extract_content_from_pdf(self, pdf_path):
        structured_content = []
        
        try:
            logger.info(f"Extraction: {pdf_path}")
            
            with fitz.open(pdf_path) as doc:
                doc_metadata = {
                    "title": doc.metadata.get("title", ""),
                    "author": doc.metadata.get("author", ""),
                    "subject": doc.metadata.get("subject", ""),
                    "keywords": doc.metadata.get("keywords", ""),
                    "page_count": len(doc)
                }
                
                full_text = ""
                
                for page_num, page in enumerate(doc):
                    page_text = page.get_text()
                    if page_num < 5:
                        full_text += page_text + "\n\n"
                
                document_type = self._detect_document_type(full_text)
                logger.info(f"Type: {document_type}")
                
                formation_info = self._extract_metadata_with_gemini(full_text)
                
                for page_num, page in enumerate(doc):
                    tables = self._detect_tables_improved(page)
                    
                    for table_num, table in enumerate(tables):
                        table_data = table
                        
                        formatted_rows = []
                        for row in table_data:
                            clean_row = [cell.strip() if isinstance(cell, str) else str(cell).strip() for cell in row]
                            formatted_rows.append(" | ".join(clean_row))
                        
                        table_text = "\n".join(formatted_rows)
                        
                        if table_text.strip():
                            table_analysis = {}
                            
                            if formatted_rows and len(formatted_rows) > 0:
                                first_row = formatted_rows[0]
                                if re.search(r'\b(module|semestre|cours|volume|horaire)\b', first_row, re.IGNORECASE):
                                    table_analysis["table_type"] = "module"
                                elif re.search(r'\b(responsable|intervenant|enseignant|grade)\b', first_row, re.IGNORECASE):
                                    table_analysis["table_type"] = "responsables"
                                else:
                                    table_analysis["table_type"] = "autre"
                            
                            structured_content.append({
                                "type": "Table",
                                "content": table_text,
                                "is_table": True,
                                "metadata": {
                                    "page_number": page_num + 1,
                                    "table_num": table_num,
                                    "row_count": len(table_data),
                                    "col_count": len(table_data[0]) if table_data else 0,
                                    "formation_id": formation_info.get("formation", {}).get("acronyme", "MST_RSI"),
                                    "table_analysis": table_analysis
                                }
                            })
                            
                            logger.info(f"Tableau: page {page_num+1}, {len(table_data)} lignes")
                    
                    text_blocks = []
                    blocks = page.get_text("dict").get("blocks", [])
                    
                    for block_num, block in enumerate(blocks):
                        if "lines" not in block:
                            continue
                        
                        block_text = ""
                        is_title = False
                        
                        for line in block["lines"]:
                            for span in line["spans"]:
                                if span["size"] > 11 or (span["flags"] & 16) != 0:
                                    is_title = True
                                block_text += span["text"] + " "
                        
                        block_text = block_text.strip()
                        if not block_text:
                            continue
                        
                        if text_blocks and not is_title:
                            text_blocks[-1]["content"] += "\n" + block_text
                        else:
                            block_type = "Header" if is_title else "Text"
                            text_blocks.append({
                                "type": block_type,
                                "content": block_text,
                                "bbox": block["bbox"]
                            })
                    
                    for block_idx, block in enumerate(text_blocks):
                        metadata = {
                            "page_number": page_num + 1,
                            "block_num": block_idx,
                            "formation_id": formation_info.get("formation", {}).get("acronyme", "MST_RSI"),
                            "document_type": document_type
                        }
                        
                        structured_content.append({
                            "type": block["type"],
                            "content": block["content"],
                            "metadata": metadata
                        })
                
                logger.info(f"Extrait {len(structured_content)} éléments")
                return structured_content
                
        except Exception as e:
            logger.error(f"Erreur extraction PDF: {e}")
            
            try:
                logger.info("Fallback PyPDF2")
                with open(pdf_path, "rb") as f:
                    reader = PdfReader(f)
                    all_text = ""
                    
                    for page_num, page in enumerate(reader.pages):
                        text = page.extract_text()
                        all_text += text + "\n\n"
                        
                        if text.strip():
                            structured_content.append({
                                "type": "Text",
                                "content": text,
                                "metadata": {
                                    "page_number": page_num + 1,
                                    "formation_id": "MST_RSI"
                                }
                            })
                    
                    if not structured_content:
                        document_type = self._detect_document_type(all_text)
                        
                        structured_content.append({
                            "type": "Text",
                            "content": all_text,
                            "metadata": {
                                "formation_id": "MST_RSI",
                                "document_type": document_type
                            }
                        })
                        
                return structured_content
            except Exception as e2:
                logger.error(f"Échec PyPDF2: {e2}")
                return []

    def _split_into_chunks(self, text, metadata):
        if "\n\n" in text:
            paragraphs = text.split("\n\n")
            chunks = []
            current_chunk = []
            current_length = 0
            
            for para in paragraphs:
                para = para.strip()
                if not para:
                    continue
                    
                if current_length + len(para) < 6000:
                    current_chunk.append(para)
                    current_length += len(para)
                else:
                    if current_chunk:
                        chunk_text = "\n\n".join(current_chunk)
                        chunks.append(Document(page_content=chunk_text, metadata=metadata.copy()))
                    
                    current_chunk = [para]
                    current_length = len(para)
            
            if current_chunk:
                chunk_text = "\n\n".join(current_chunk)
                chunks.append(Document(page_content=chunk_text, metadata=metadata.copy()))
                
            return chunks
        else:
            return self.text_splitter.create_documents([text], [metadata])

    def _group_related_content(self, chunks):
        grouped_chunks = []
        current_group = []
        
        for chunk in chunks:
            if re.match(r'^M\d+\s+', chunk.page_content):
                if current_group:
                    grouped_chunks.append(self._merge_chunks(current_group))
                    current_group = []
            
            current_group.append(chunk)
            
            if sum(len(c.page_content) for c in current_group) > 6000:
                grouped_chunks.append(self._merge_chunks(current_group))
                current_group = []
        
        if current_group:
            grouped_chunks.append(self._merge_chunks(current_group))
            
        return grouped_chunks
    
    def _merge_chunks(self, chunks):
        if not chunks:
            return None
            
        merged_content = "\n\n".join(chunk.page_content for chunk in chunks)
        metadata = chunks[0].metadata.copy()
        
        if len(chunks) > 1:
            metadata['sources'] = [{
                'page': c.metadata.get('page_number', 'N/A'),
                'block': c.metadata.get('block_num', 'N/A')
            } for c in chunks]
            
        return Document(page_content=merged_content, metadata=metadata)

    def process_pdf(self, pdf_path):
        try:
            content_items = self.extract_content_from_pdf(pdf_path)
            
            if not content_items or not isinstance(content_items, list):
                logger.error(f"Format invalide: {pdf_path}")
                return []
            
            full_text = ""
            for item in content_items:
                if item.get("type") in ["Text", "Header"] and "content" in item:
                    full_text += item["content"] + "\n\n"
            
            doc_type = self._detect_document_type(full_text)
            
            documents = []
            for item in content_items:
                if "content" not in item or not item["content"].strip():
                    continue
                    
                metadata = {
                    "source": str(pdf_path),
                    "filename": os.path.basename(pdf_path),
                    "document_type": doc_type,
                    "formation_id": "MST_RSI"
                }
                
                if "metadata" in item and isinstance(item["metadata"], dict):
                    metadata.update(item["metadata"])
                
                if item.get("is_table") or item.get("type") == "Table":
                    metadata["is_table"] = True
                
                doc = Document(
                    page_content=item["content"],
                    metadata=metadata
                )
                documents.append(doc)
            
            if doc_type in ["descriptif_module", "equipe_pedagogique"] and len(documents) > 1:
                documents = self._group_related_content(documents)
            
            logger.info(f"{len(documents)} documents: {pdf_path}")
            return documents
                
        except Exception as e:
            logger.error(f"Erreur traitement {pdf_path}: {e}")
            return []

    def process_all_pdfs(self):
        pdf_files = list(self.data_dir.glob("*.pdf"))
        all_docs = []
        
        for pdf_file in pdf_files:
            logger.info(f"Traitement: {pdf_file.name}")
            docs = self.process_pdf(str(pdf_file))
            if docs:
                all_docs.extend(docs)
                logger.info(f"{pdf_file.name} - {len(docs)} documents")
            else:
                logger.warning(f"Aucun document: {pdf_file.name}")
        
        return all_docs


def test_enhanced_processor(data_dir, pdf_path=None):
    processor = EnhancedFSSTPDFProcessor(data_dir)
    
    if pdf_path:
        docs = processor.process_pdf(pdf_path)
        print(f"Extrait {len(docs)} documents")
        
        for i, doc in enumerate(docs[:3]):
            print(f"\n--- Document {i+1} ---")
            print(f"Type: {doc.metadata.get('element_type')}")
            print(f"Page: {doc.metadata.get('page_number')}")
            print(f"Content: {doc.page_content[:100]}...")
            print(f"Metadata: {doc.metadata}")
    else:
        all_docs = processor.process_all_pdfs()
        print(f"Total: {len(all_docs)} documents")