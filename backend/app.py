from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import os
import uvicorn
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

try:
    from src.qa.question_answering import FSTQueryEngine
    from src.utils.config import load_dotenv
except ImportError:
    from src.qa.question_answering import FSTQueryEngine
    from src.utils.config import load_dotenv

app = FastAPI(
    title="API Questions-Réponses FST",
    description="API base connaissances FST",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class QuestionRequest(BaseModel):
    question: str


class SearchRequest(BaseModel):
    query: str
    top_k: Optional[int] = 5


class QuestionResponse(BaseModel):
    answer: str
    processing_time_ms: float


class SearchResponse(BaseModel):
    documents: List[Dict[str, Any]]


qa_engine = None


def get_qa_engine():
    global qa_engine
    if qa_engine is None:
        load_dotenv()
        try:
            qa_engine = FSTQueryEngine(
                model_name=os.getenv("LLM_MODEL"),
                temperature=float(os.getenv("LLM_TEMPERATURE", "0")),
                top_k=int(os.getenv("SEARCH_TOP_K", "5")),
                vector_store_path=os.getenv("VECTOR_STORE_DIR"),
                use_memory=True
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Erreur init QA: {e}")
    return qa_engine


@app.get("/api/test")
def test():
    return {"message": "Serveur OK"}


@app.post("/api/question", response_model=QuestionResponse)
async def answer_question(
    request: QuestionRequest,
    engine: FSTQueryEngine = Depends(get_qa_engine)
):
    import time
    start_time = time.time()
    
    print(f"Requête: {request.question}")

    try:
        print("Début traitement")
        result = engine.query(request.question)
        
        if isinstance(result, dict) and "answer" in result:
            answer = result["answer"]
            processing_time = result.get("processing_time_ms", (time.time() - start_time) * 1000)
        else:
            answer = result
            processing_time = (time.time() - start_time) * 1000
            
        print(f"Réponse: {str(answer)[:50]}...")
        print(f"Temps: {processing_time}ms")
        
        return JSONResponse(
            content={"answer": answer, "processing_time_ms": processing_time},
            headers={"Content-Type": "application/json; charset=utf-8"}
        )
    except Exception as e:
        print(f"Erreur: {e}")
        raise HTTPException(status_code=500, detail=f"Erreur: {e}")


@app.post("/api/search", response_model=SearchResponse)
async def search_docs(
    request: SearchRequest,
    engine: FSTQueryEngine = Depends(get_qa_engine)
):
    try:
        docs = engine.search_similar_docs(request.query, request.top_k)
        
        formatted_docs = []
        for doc in docs:
            formatted_doc = {
                "content": doc.page_content,
                "metadata": doc.metadata
            }
            if "embedding" in formatted_doc["metadata"]:
                del formatted_doc["metadata"]["embedding"]
            
            formatted_docs.append(formatted_doc)
        
        return {"documents": formatted_docs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur: {e}")


@app.post("/api/clear-memory")
async def clear_memory(
    engine: FSTQueryEngine = Depends(get_qa_engine)
):
    try:
        engine.clear_memory()
        return {"status": "success", "message": "Mémoire effacée"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur: {e}")


@app.post("/api/process-documents")
async def process_documents():
    from main import process_data_pipeline, DATA_DIR