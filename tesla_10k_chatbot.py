# 1) Install required packages in one line
!pip install -q faiss-cpu sentence_transformers pdfplumber google-generativeai gradio

# 2) Mount Google Drive (only if you need to access files on Drive)
from google.colab import drive
drive.mount('/content/drive')

# 3) Imports
import pdfplumber
import faiss
import numpy as np
import re
import google.generativeai as genai
import gradio as gr
from sentence_transformers import SentenceTransformer

# 4) Configure Gemini API
GOOGLE_API_KEY = "[Input Your API Key Here]"
genai.configure(api_key=GOOGLE_API_KEY)
LLM_model = genai.GenerativeModel("gemini-1.5-flash")

# 5) Load embedding model
embedding_model = SentenceTransformer("all-MiniLM-L6-v2")

# 6) Define utility functions
def extract_text_from_pdf(pdf_path):
    text_list = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                text_list.append(text)
    return "\n".join(text_list)

def split_into_sentences(text):
    # Split at punctuation followed by space, filter short lines
    sentences = re.split(r'(?<=[.!?])\s+', text)
    return [s.strip() for s in sentences if len(s.strip()) > 20]

# 7) Extract text & create embeddings index
pdf_path = "/content/drive/My Drive/Tesla.pdf"  # Update with your PDF path
raw_text = extract_text_from_pdf(pdf_path)
sentences = split_into_sentences(raw_text)

# Convert each sentence to a 384D embedding (for all-MiniLM-L6-v2)
sentence_embeddings = np.array(embedding_model.encode(sentences), dtype="float32")
faiss.normalize_L2(sentence_embeddings)  # Normalize for cosine similarity

# Build FAISS index
dimension = sentence_embeddings.shape[1]
index = faiss.IndexFlatIP(dimension)  # IP ~ cosine similarity with normalized vectors
index.add(sentence_embeddings)

# 8) Define response function
def get_gemini_response(message, history):
    # Convert query to embedding
    query_embedding = np.array(embedding_model.encode([message]), dtype="float32")
    faiss.normalize_L2(query_embedding)

    # Search top 5 relevant sentences
    D, I = index.search(query_embedding, k=5)
    top_sentences = [sentences[i] for i in I[0]]
    context = "\n".join(top_sentences)

    # Create prompt with context
    prompt = f"""
    Context: {context}

    Question: {message}

    Answer only using the above context.
    """
    response = LLM_model.generate_content(prompt)
    yield response.text  # Stream the response

# 9) Create a Gradio chat interface
chatbot = gr.ChatInterface(
    fn=get_gemini_response,
    title="Tesla 10-K Chatbot",
    description="Ask questions about Tesla's financial reports!",
    type="messages",
    save_history=True
)

# 10) Launch the chatbot
chatbot.launch(share=True, debug=True)

# This code is licensed under the MIT License.
# Full text of the license is available in the LICENSE file at the root of this repository.
