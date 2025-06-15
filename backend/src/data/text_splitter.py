from langchain.text_splitter import RecursiveCharacterTextSplitter
from typing import List
from langchain.schema import Document

class FSTextSplitter:
    def __init__(
        self,
        chunk_size: int = 1000,
        chunk_overlap: int = 200,
        length_function = len,
    ):
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            length_function=length_function,
            separators=["\n\n", "\n", " ", ""]
        )
    
    def split_documents(self, documents: List[Document]) -> List[Document]:
        """
        Split documents into chunks with overlap for better context preservation
        """
        try:
            return self.text_splitter.split_documents(documents)
        except Exception as e:
            print(f"Error splitting documents: {e}")
            return documents

    def split_text(self, text: str, metadata: dict = None) -> List[Document]:
        """
        Split a single text into chunks with overlap
        """
        try:
            return self.text_splitter.create_documents(
                texts=[text],
                metadatas=[metadata] if metadata else None
            )
        except Exception as e:
            print(f"Error splitting text: {e}")
            return [Document(page_content=text, metadata=metadata or {})] 