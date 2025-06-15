import argparse
import sys
import os
from typing import List, Tuple

try:
    from ..qa.question_answering import FSTQueryEngine  
    from ..utils.config import load_dotenv
except ImportError:
    from src.qa.question_answering import FSTQueryEngine  
    from src.utils.config import load_dotenv

def parse_args():
    """Parse les arguments de ligne de commande"""
    parser = argparse.ArgumentParser(description="Interface CLI pour le système FST Q&A")  # Remplacé FSST par FST
    parser.add_argument(
        "--model", 
        type=str, 
        default="gemini-pro", 
        help="Modèle LLM à utiliser"
    )
    parser.add_argument(
        "--no-memory",
        action="store_true",
        help="Désactiver la mémoire de conversation"
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Température pour le LLM (0-1)"
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=5,
        help="Nombre de chunks à récupérer"
    )
    parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Niveau de log"
    )
    return parser.parse_args()

def setup_logging(level: str):
    """Configure le logging avec le niveau spécifié"""
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

def interactive_session(engine: FSTQueryEngine): 
    """
    Démarre une session interactive de questions-réponses
    
    Args:
        engine: Moteur de questions-réponses
    """
    chat_history: List[Tuple[str, str]] = []
    
    print(f"[BOT] Assistant FST - Posez vos questions (tapez 'exit' pour quitter)")
    print("Commandes disponibles:")
    print("  'exit' - Quitter")
    print("  'clear' - Effacer l'historique")
    print("  'search: <query>' - Rechercher des documents similaires")
    print("-" * 50)
    
    while True:
        try:
            question = input("\n[USER] Vous: ")
            
            if question.lower() in ["exit", "quit", "q", "bye"]:
                print("Au revoir!")
                break
                
            if question.lower() in ["clear", "reset", "restart"]:
                chat_history = []
                engine.clear_memory()
                print("Historique effacé")
                continue
                
            if question.lower().startswith("search:"):
                query = question[len("search:"):].strip()
                docs = engine.search_similar_docs(query)
                print(f"\n[SEARCH] Résultats pour '{query}':")
                for i, doc in enumerate(docs, 1):
                    print(f"\n--- Document {i} ---")
                    print(f"Source: {doc.metadata.get('source', 'Inconnue')}")
                    print(f"Contenu: {doc.page_content[:200]}...")
                continue
                
            if not question.strip():
                continue
                
            print("\n[BOT] Assistant: ", end="", flush=True)
            
            response = engine.query(question, chat_history)
            
            for char in response:
                print(char, end="", flush=True)
            print()
            
            chat_history.append((question, response))
            
        except KeyboardInterrupt:
            print("\nSession interrompue. Au revoir! 👋")
            break
        except Exception as e:
            print(f"\n❌ Erreur: {str(e)}")

def main():
    """Point d'entrée principal"""
    load_dotenv()
    
    if not os.getenv("GOOGLE_API_KEY"):
        print("❌ Erreur: GOOGLE_API_KEY doit être définie dans le fichier .env")
        sys.exit(1)
    
    args = parse_args()
    
    try:
        print(f"[INFO] Initialisation du moteur avec modele {args.model}...")
        engine = FSTQueryEngine(  
            model_name=args.model,
            temperature=args.temperature,
            top_k=args.top_k,
            use_memory=not args.no_memory
        )
        
        interactive_session(engine)
        
    except Exception as e:
        print(f"[ERROR] Erreur lors de l'initialisation: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()