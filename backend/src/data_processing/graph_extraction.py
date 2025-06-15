import os
import json
from dotenv import load_dotenv
import nest_asyncio
from unstructured.partition.pdf import partition_pdf
from unstructured.staging.base import elements_to_json
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from autogen import AssistantAgent, ConversableAgent, UserProxyAgent, GroupChat, GroupChatManager
from autogen.agentchat.contrib.graph_rag.document import Document, DocumentType
from autogen.agentchat.contrib.graph_rag.neo4j_graph_query_engine import Neo4jGraphQueryEngine
from autogen.agentchat.contrib.graph_rag.neo4j_graph_rag_capability import Neo4jGraphCapability
from autogen.agentchat.contrib.multimodal_conversable_agent import MultimodalConversableAgent
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional
from langchain_core.documents import Document as LangchainDocument

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class GraphPDFProcessor:
    
    def __init__(self, data_dir: str, output_dir: str = None, gemini_api_key: str = None):
        load_dotenv()
        nest_asyncio.apply()
        
        self.data_dir = Path(data_dir)
        self.output_dir = Path(output_dir) if output_dir else Path("./parsed_pdf_info")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        self.gemini_api_key = gemini_api_key or os.getenv("GOOGLE_API_KEY")
        self.embedding_model_name = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
        
        self.config_list = [
            {
                "model": os.getenv("LLM_MODEL", "gemini-1.5-flash-latest"),
                "api_key": self.gemini_api_key,
                "base_url": "https://generativelanguage.googleapis.com/v1beta/models/",
            }
        ]
        
        self.embedding_model = HuggingFaceEmbedding(model_name=self.embedding_model_name)
        self.query_engine = self._init_neo4j_engine()
    
    def _init_neo4j_engine(self):
        try:
            query_engine = Neo4jGraphQueryEngine(
                username="neo4j",
                password=os.getenv("NEO4J_PASSWORD", "password"),
                host=os.getenv("NEO4J_HOST", "bolt://localhost"),
                port=int(os.getenv("NEO4J_PORT", 7687)),
                database=os.getenv("NEO4J_DATABASE", "neo4j"),
                llm_config={"config_list": self.config_list},
                embedding=self.embedding_model,
            )
            logger.info("Neo4j initialisé")
            return query_engine
        except Exception as e:
            logger.error(f"Erreur Neo4j: {e}")
            return None

    def extract_pdf_data(self, pdf_path: str):
        try:
            logger.info(f"Extraction: {pdf_path}")
            file_elements = partition_pdf(
                filename=pdf_path,
                strategy="hi_res",
                languages=["eng", "fra"],
                infer_table_structure=True,
                extract_images_in_pdf=True,
                extract_image_block_output_dir=str(self.output_dir),
                extract_image_block_types=["Image", "Table"],
                extract_forms=False,
                form_extraction_skip_tables=False,
            )
            
            output_file = self.output_dir / f"{Path(pdf_path).stem}_parsed_elements.json"
            elements_to_json(elements=file_elements, filename=str(output_file), encoding="utf-8")
            
            logger.info(f"Extraction: {len(file_elements)} éléments")
            return file_elements
        except Exception as e:
            logger.error(f"Erreur extraction {pdf_path}: {e}")
            return []

    def process_elements(self, file_elements, pdf_path: str):
        try:
            output_elements = []
            keys_to_extract = ["element_id", "text", "type"]
            metadata_keys = ["page_number", "parent_id", "image_path"]
            text_types = set(["Text", "UncategorizedText", "NarrativeText"])
            element_length = len(file_elements)
            
            for idx in range(element_length):
                data = file_elements[idx].to_dict()
                new_data = {key: data[key] for key in keys_to_extract if key in data}
                metadata = data.get("metadata", {})
                
                for key in metadata_keys:
                    if key in metadata:
                        new_data[key] = metadata[key]
                
                if data["type"] == "Table":
                    if idx > 0:
                        pre_data = file_elements[idx - 1].to_dict()
                        if pre_data["type"] in text_types:
                            new_data["text"] = pre_data["text"] + "\n\n" + new_data["text"]
                    
                    if idx < element_length - 1:
                        post_data = file_elements[idx + 1].to_dict()
                        if post_data["type"] in text_types:
                            new_data["text"] = new_data["text"] + "\n\n" + post_data["text"]
                
                new_data["source"] = pdf_path
                new_data["filename"] = os.path.basename(pdf_path)
                
                output_elements.append(new_data)
            
            output_file = self.output_dir / f"{Path(pdf_path).stem}_processed_elements.json"
            with open(output_file, "w", encoding="utf-8") as file:
                json.dump(output_elements, file, indent=4)
            
            logger.info(f"Traitement: {len(output_elements)} éléments")
            return output_elements
        except Exception as e:
            logger.error(f"Erreur traitement: {e}")
            return []

    def setup_agents(self, img_folder=None):
        if img_folder is None:
            img_folder = str(self.output_dir)
        
        llm_config = {
            "cache_seed": 42,
            "temperature": float(os.getenv("LLM_TEMPERATURE", 0)),
            "config_list": self.config_list,
            "timeout": 120,
        }

        user_proxy = UserProxyAgent(
            name="User_proxy",
            system_message="A human admin.",
            human_input_mode="NEVER",
            code_execution_config=False,
        )

        table_assistant = AssistantAgent(
            name="table_assistant",
            system_message="""You are a helpful assistant.
            You will extract the table name from the message and reply with "Find image_path for Table: {table_name}".
            For example, when you got message "What is column data in table XYZ?",
            you will reply "Find image_path for Table: XYZ"
            """,
            llm_config=llm_config,
            human_input_mode="NEVER",
        )

        rag_agent = ConversableAgent(
            name="document_rag",
            human_input_mode="NEVER",
        )
        
        if self.query_engine:
            graph_rag_capability = Neo4jGraphCapability(self.query_engine)
            graph_rag_capability.add_to_agent(rag_agent)

        img_request_format = ConversableAgent(
            name="img_request_format",
            system_message=f"""You are a helpful assistant.
            You will extract the table_file_name from the message and reply with "Please extract table from the following image and convert it to Markdown.
            <img {img_folder}/table_file_name>.".
            For example, when you got message "The image path for the table titled XYZ is "./parsed_pdf_info/abcde".",
            you will reply "Please extract table from the following image and convert it to Markdown.
            <img {img_folder}/abcde>."
            """,
            llm_config=llm_config,
            human_input_mode="NEVER",
        )

        image2table_convertor = MultimodalConversableAgent(
            name="image2table_convertor",
            system_message="""
            You are an image to table converter. You will process an image of one or multiple consecutive tables.
            You need to follow the following steps in sequence,
            1. extract the complete table contents and structure.
            2. Make sure the structure is complete and no information is left out. Otherwise, start from step 1 again.
            3. Correct typos in the text fields.
            4. In the end, output the table(s) in Markdown.
            """,
            llm_config={"config_list": self.config_list, "max_tokens": 300},
            human_input_mode="NEVER",
            max_consecutive_auto_reply=1,
        )

        conclusion = AssistantAgent(
            name="conclusion",
            system_message="""You are a helpful assistant.
            Base on the history of the groupchat, answer the original question from User_proxy.
            """,
            llm_config=llm_config,
            human_input_mode="NEVER",
        )

        return user_proxy, table_assistant, rag_agent, img_request_format, image2table_convertor, conclusion

    def init_graph_database(self, processed_elements_file: str):
        try:
            if not self.query_engine:
                logger.error("Neo4j non initialisé")
                return False
            
            self.query_engine._clear()
            
            input_documents = [Document(doctype=DocumentType.JSON, path_or_url=processed_elements_file)]
            self.query_engine.init_db(input_doc=input_documents)
            
            logger.info(f"DB Neo4j initialisée: {processed_elements_file}")
            return True
        except Exception as e:
            logger.error(f"Erreur init DB: {e}")
            return False

    def process_pdf(self, pdf_path: str) -> List[LangchainDocument]:
        try:
            file_elements = self.extract_pdf_data(pdf_path)
            if not file_elements:
                logger.error(f"Aucun élément: {pdf_path}")
                return []
            
            processed_elements = self.process_elements(file_elements, pdf_path)
            if not processed_elements:
                logger.error(f"Aucun élément traité: {pdf_path}")
                return []
            
            processed_elements_file = str(self.output_dir / f"{Path(pdf_path).stem}_processed_elements.json")
            
            if not self.init_graph_database(processed_elements_file):
                logger.error(f"Échec init DB: {pdf_path}")
                return []
            
            langchain_docs = []
            for element in processed_elements:
                metadata = {
                    "source": pdf_path,
                    "filename": os.path.basename(pdf_path),
                    "element_id": element.get("element_id", ""),
                    "element_type": element.get("type", ""),
                    "page_number": element.get("page_number", 0)
                }
                
                if element.get("type") == "Table" and "image_path" in element:
                    metadata["image_path"] = element["image_path"]
                
                doc = LangchainDocument(
                    page_content=element.get("text", ""),
                    metadata=metadata
                )
                langchain_docs.append(doc)
            
            logger.info(f"Traitement: {len(langchain_docs)} documents LangChain")
            return langchain_docs
        except Exception as e:
            logger.error(f"Erreur process_pdf {pdf_path}: {e}")
            return []

    def process_all_pdfs(self) -> List[LangchainDocument]:
        pdf_files = list(self.data_dir.glob("*.pdf"))
        all_docs = []
        
        for pdf_file in pdf_files:
            docs = self.process_pdf(str(pdf_file))
            if docs:
                all_docs.extend(docs)
                logger.info(f"{pdf_file.name} - {len(docs)} documents")
        
        return all_docs

    def query_document(self, query: str):
        try:
            if not self.query_engine:
                logger.error("Neo4j non initialisé")
                return "Erreur: Base non initialisée"
            
            user_proxy, table_assistant, rag_agent, img_request_format, image2table_convertor, conclusion = self.setup_agents()
            
            groupchat = GroupChat(
                agents=[user_proxy, table_assistant, rag_agent, img_request_format, image2table_convertor, conclusion],
                messages=[],
                speaker_selection_method="round_robin",
            )
            manager = GroupChatManager(groupchat=groupchat, llm_config={"config_list": self.config_list})
            
            user_proxy.initiate_chat(manager, message=query)
            
            chat_history = groupchat.messages
            if chat_history:
                final_message = chat_history[-1].get("content", "Aucune réponse")
                return final_message
            else:
                return "Aucune réponse"
        except Exception as e:
            logger.error(f"Erreur query: {e}")
            return f"Erreur: {e}"