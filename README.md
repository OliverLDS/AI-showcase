# AI-Showcase: A Collection of AI-Powered Code Samples

Welcome to **AI-Showcase**, a repository featuring **various small AI-based applications and demonstrations**! This collection is designed to highlight different AI techniques, which are also showcased on my YouTube channel.

## 📌 About This Repository

This repository contains **practical AI implementations** in areas such as:
- **Natural Language Processing (NLP)**
- **AI-powered financial analysis**
- **Chatbots and conversational AI**
- **Machine learning demos**
- **Generative AI applications**

Each project is self-contained and designed to be **easy to understand**, making it useful for learners, AI enthusiasts, and developers.

---

## 📂 Repository Structure

### 🔹 `tesla_10k_chatbot`
**📄 `tesla_10k_chatbot.py`** – A chatbot that answers questions based on Tesla's 10-K financial report using:
- PDF text extraction (`pdfplumber`)
- Sentence embedding (`sentence_transformers`)
- Similarity search (`FAISS`)
- Response generation (`Google Gemini API`)
- Interactive UI (`Gradio`)

### 🔹 `fred_data_tweet_generator`
**📄 fred_data_tweet_generator.py** – A code that:

- Imports FRED series metadata (FRED ID, update frequency, importance) from a Google Sheet using `gspread`.
- Fetches recent data from the FRED API via `fredapi`.
- Filters out series without any fresh (past 3 days) data.
- Applies weighted random selection based on user-defined frequency and importance.
- Prepares multiple prompt templates (for example, Twitter-style commentary) and randomly selects one to display, including recent and historical data.

### 🔹 FRED_Surprise_Reporter
**📄 FRED_Surprise_Reporter.R** – An R script that:

- Loads time-series data from FRED (Federal Reserve Economic Data).
- Identifies unexpected trends in economic indicators using statistical models.
- Uses an AR(1) mean-reverting model to detect significant deviations.
- Leverages the Google Gemini API to generate insights and explanations.
- Finds correlated variables to explain anomalies.
- Generates an AI-written narrative summarizing economic shifts.
- Saves structured results and renders a Quarto report.

*(More projects will be added over time!)*

---

## 🔧 How to Use

1. **Clone the repository**:
   ```bash
   git clone https://github.com/OliverLDS/AI-showcase.git
   ```

2. **Install required dependencies**:
  ```bash
  pip install -r requirements.txt
  ```

3. **Run the chatbot example**:
  ```bash
  python tesla_10k_chatbot.py
  ```

4. **Run the tweeter generator example**:
  ```bash
  python fred_data_tweet_generator.py
  ```

5. **Run the fred surprise reporter example**:
  ```bash
  install.packages(c("tidyverse", "httr2", "quarto", "readxl"))
  source("FRED_Surprise_Reporter.R")
  ```

---

## 📺 YouTube Channel
📢 Watch the code demos and explanations on YouTube!
👉 My YouTube Channel

I regularly post AI-related tutorials, walkthroughs, and live coding sessions.

---

## 📜 License
This repository is licensed under the MIT License. See the LICENSE file for details.

---

## 🤝 Contributions
If you’d like to contribute, feel free to fork the repo and submit a pull request! You can also open issues for any bugs, improvements, or AI project ideas.

---

## 🔗 Stay Connected
📌 GitHub: https://github.com/OliverLDS

🚀 Let's explore AI together! 🎯


