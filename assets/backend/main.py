import uuid
import chromadb
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import os
from docx2txt import process as docx2txt
import pandas as pd
import PyPDF2
from chromadb.utils import embedding_functions

class FileRequest(BaseModel):
    file_path: str

app = FastAPI()

class TextRequest(BaseModel):
    text: str

class DeleteRequest(BaseModel):
    id: str

# Initialize ChromaDB client
client = chromadb.PersistentClient(path="./chroma_storage")
collection = client.get_or_create_collection("flutter_vectors")

# Use a local embedding model
embedding_fn = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="all-MiniLM-L6-v2"
)
def remove_after_keyword(text: str, keyword: str):
    idx = text.lower().find(keyword.lower())
    if idx != -1:
        return text[:idx].strip()
    return text
def extract_text_from_file(file_path: str) -> Optional[str]:
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    
    ext = file_path.split('.')[-1].lower()
    
    try:
        if ext in ['doc', 'docx']:
            text = docx2txt(file_path)
            text = remove_after_keyword(text, "text formatting")
            return text
        elif ext == 'pdf':
            text = ""
            with open(file_path, 'rb') as file:
                reader = PyPDF2.PdfReader(file)
                for page in reader.pages:
                    text += page.extract_text() + "\n"
            return text
            
        elif ext in ['xlsx', 'xls']:
            df = pd.read_excel(file_path)
            text_rows = []
            for _, row in df.iterrows():
                row_text = ", ".join(f"{col}: {val}" for col, val in row.items())
                text_rows.append(row_text)
            return "\n".join(text_rows)
            
        elif ext == 'csv':
            df = pd.read_csv(file_path)
            text_rows = []
            for _, row in df.iterrows():
                row_text = ", ".join(f"{col}: {val}" for col, val in row.items())
                text_rows.append(row_text)
            return "\n".join(text_rows)
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing file: {str(e)}")
    
    raise HTTPException(status_code=400, detail="Unsupported file type")

@app.post("/add")
async def add_document(request: FileRequest):
    try:
        text = extract_text_from_file(request.file_path)
        if not text:
            raise HTTPException(status_code=400, detail="No text could be extracted")
            
        # Clean text and create embedding
        text = text.strip()
        embedding = embedding_fn([text])
        
        # Add to database
        collection.add(
            documents=[text],
            embeddings=embedding,
            ids=[str(uuid.uuid4())]
        )
        
        return {"status": "success"}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/search")
def search(query: str):
    embedding = embedding_fn([query])

    results = collection.query(
        query_embeddings=embedding,
        n_results=5
    )

    # Restructure results into cleaner objects
    matches = []
    for i in range(len(results["ids"][0])):
        matches.append({
            "id": results["ids"][0][i],
            "text": results["documents"][0][i],
            "distance": results["distances"][0][i]
        })
    print(matches)
    return {"matches": matches}

@app.post("/delete")
def delete_item(request:DeleteRequest):
    try:
        collection.delete(ids=[request.id])
        return {
            "status": "deleted",
            "id": request.id
        }
    except Exception:
        raise HTTPException(
            status_code=404,
            detail=f"Document with id '{request.id}' not found."
        )
@app.post("/drop")
def drop_database():
    try:
        client.delete_collection("flutter_vectors")
        
        global collection
        collection = client.get_or_create_collection(
            "flutter_vectors",
            embedding_function=embedding_fn
        )
        
        return {"status": "database reset successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/count")
def count_items():
    return {"count": collection.count()}