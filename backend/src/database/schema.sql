CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS formations (
    formation_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chunks (
    chunk_id TEXT PRIMARY KEY,
    formation_id TEXT REFERENCES formations(formation_id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    embedding vector(768),  
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS chunks_embedding_idx 
ON chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

CREATE OR REPLACE FUNCTION match_chunks(
    query_embedding vector(768),
    match_threshold FLOAT,
    match_count INT
)
RETURNS TABLE (
    chunk_id TEXT,
    formation_id TEXT,
    chunk_index INTEGER,
    text TEXT,
    similarity FLOAT
)
LANGUAGE SQL STABLE
AS $$
    SELECT
        chunk_id,
        formation_id,
        chunk_index,
        text,
        1 - (embedding <=> query_embedding) AS similarity
    FROM chunks
    WHERE 1 - (embedding <=> query_embedding) > match_threshold
    ORDER BY similarity DESC
    LIMIT match_count;
$$;