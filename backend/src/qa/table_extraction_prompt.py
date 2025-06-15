"""
Prompt pour l'extraction de tableaux avec Gemini
"""

TABLE_EXTRACTION_PROMPT = """
Tu es un expert en analyse de tableaux extraits de documents PDF. 

CONTEXTE:
Le document suivant contient des tableaux décrivant les modules d'une formation universitaire.

TÂCHE:
Analyse le contenu et extrais les informations structurées suivantes pour chaque module :
1. Le nom du module
2. Le code du module
3. Le volume horaire total
4. La répartition des heures (cours, TD, TP)
5. Les enseignants responsables
6. Une description du module

INSTRUCTIONS:
- Si une information n'est pas disponible, utilise 'Non spécifié'
- Conserve la structure des données
- Sois précis dans l'extraction des informations

Retourne uniquement les données extraites au format JSON.
"""
