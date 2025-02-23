!pip install -q fredapi gspread google-generativeai

import gspread
from google.colab import auth
auth.authenticate_user()
from google.auth import default

# Authorize Google Sheets
creds, _ = default()
gc = gspread.authorize(creds)

# Open spreadsheet and read all rows
spreadsheet = gc.open("FRED data")
sheet = spreadsheet.worksheet("Sheet1")
rows = sheet.get_all_records()

# Build dictionary for FRED series
fred_series_extended = {
    row["Series Name"]: {
        "id": row["FRED ID"],
        "frequency": row["Frequency"],
        "importance": row["Importance"]
    }
    for row in rows
}

import numpy as np
import pandas as pd
import random
from datetime import date, timedelta
from fredapi import Fred
import google.generativeai as genai

# Initialize Fred
fred = Fred(api_key="[Input Your Fred API Key]")

# Define frequency weights
frequency_weight_map = {
    "daily": 1,
    "weekly": 2,
    "monthly": 3,
    "quarterly": 4
}

# Fetch data from FRED
today = date.today()
start_date = today - timedelta(days=100)
data_frames = {}

for series_name, info in fred_series_extended.items():
    try:
        data_frames[series_name] = fred.get_series(info["id"], observation_start=start_date)
    except Exception as e:
        print(f"Error fetching {series_name} ({info['id']}): {e}")

# Combine into one DataFrame
combined_df = pd.DataFrame(data_frames)

# Filter columns that have at least one valid (non-NaN) entry in the past 3 days
recent_cutoff = pd.to_datetime(today - timedelta(days=3))
filtered_columns = [
    col for col in combined_df.columns
    if not combined_df[col][combined_df.index >= recent_cutoff].dropna().empty
]

# Compute weights (frequency * importance) for each filtered column
column_weights = [
    frequency_weight_map.get(fred_series_extended[col]["frequency"], 1)
    * fred_series_extended[col]["importance"]
    for col in filtered_columns
]

# Randomly pick a column using computed weights
selected_col = random.choices(filtered_columns, weights=column_weights, k=1)[0]

# Prepare display text for the newly updated series
selected_value = data_frames[selected_col].dropna().tail(2)
selected_today_data_str = f"{selected_col}: {selected_value.to_string()}"

# Get a tabular view of the filtered data with dates as a column
temp_df = combined_df[filtered_columns].copy().reset_index().rename(columns={"index": "Date"})
historical_data_str = temp_df.to_string(index=False)

# Create multiple prompt versions
prompt_versions = [
    f"""
The following economic data was updated (from FRED) as of {today}:
{selected_today_data_str}

Here is the historical data for reference:
{historical_data_str}

Please draft an insightful twitter post about the economic trend based on this data.
Avoid mentioning any data gap. Only provide the twitter content. No other text.
""",
    f"""
We have fresh data from FRED as of {today}:
{selected_today_data_str}

Below you can see how it has been trending:
{historical_data_str}

Craft a compelling tweet on the economic trend, relating it to other data if possible.
No data-gap mentions. Only the tweet content, no additional text.
""",
    f"""
Today's newly updated FRED series (as of {today}) is:
{selected_today_data_str}

Historic performance is outlined below:
{historical_data_str}

Please write a concise Twitter post analyzing this trend in context with broader economic indicators.
Don't mention data gaps. Provide only the tweet, nothing else.
"""
]

# Pick one prompt version at random and print it
final_prompt = random.choice(prompt_versions)

# Call Google Generative AI
genai.configure(api_key="[Input Your Gemini API Key]")
LLM_model = genai.GenerativeModel("gemini-1.5-flash")
response = LLM_model.generate_content(final_prompt)

# View the generated text
response.text

# This code is licensed under the MIT License.
# Full text of the license is available in the LICENSE file at the root of this repository.
