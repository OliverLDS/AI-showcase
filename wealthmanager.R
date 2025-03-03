library(shiny)
library(httr2)
library(markdown)
library(jsonlite)

# Configuration
AI_NAME <- "Oliver"
GEMINI_API_KEY <- "[INPUT YOUR API KEY]"
GEMINI_URL <- "https://generativelanguage.googleapis.com/v1beta/models/"
GEMINI_MODEL <- "gemini-2.0-flash"
GEMINI_ACTION <- "generateContent"

# Language dictionary
lang_dict <- list(
  en = list(
    title = "Oliver (Wealth management planner)",
    language_label = "Language",
    user_input = "Type your message:",
    send_button = "Send",
    you = "You:",
    ai_name = paste0(AI_NAME, ":"),
    response_format = "Please provide me only the dialogue text, no other content.",
    update_user_db_prompt = 'Output ONLY JSON format with the following structure (no extra text): {
      "gender": null,
      "age": null,
      "occupation": null,
      "wealth": null,
      "top3_major_concerns": [null, null, null],
      "top3_major_interested_topic": [null, null, null],
      "risk_tolerance": 5,
      "financial_knowledge": 5,
      "trust_on_me": 5
    }',
    greetings = c(
      "Assume your name is Oliver, a financial advisor. Return a simple self-introduction welcome message and ask for the user's name and how you can help.",
      "Assume your name is Oliver, a financial advisor. Return a simple welcome message about what you are currently working on, and ask if the user is interested.",
      "Assume your name is Oliver, a financial advisor. Ask for the user's name and a specific question about their financial needs.",
      "Assume your name is Oliver, a financial advisor. Pick a recent financial news item and ask for the user's opinion on it."
    )
  ),
  zh = list(
    title = "Oliver金融理财顾问",
    language_label = "语言",
    user_input = "输入你的消息：",
    send_button = "发送",
    you = "你:",
    ai_name = paste0(AI_NAME, ":"),
    response_format = "请只给我对话的文字，不用给我其他任何内容。",
    update_user_db_prompt = '你是Oliver,根据以上Oliver与客户(you)的聊天记录，按下列json格式回复客户信息(gender: c("男","女"); age: c("25岁及以下","25岁到35岁","35岁到45岁","45岁到55岁","55岁到65岁","65岁以上"); wealth: c("小于10万美元","大于等于10万美元且小于100万美元","大于等于100万美元且小于1000万美元","大于等于1000万美元"); risk_tolerance: 1:10; financial_knowledge: 1:10; trust_on_Oliver: 1:10)，不用返回其他内容: 
    {
      "gender": null,
      "age": null,
      "occupation": null,
      "wealth": null,
      "top3_major_concerns": [null, null, null],
      "top3_major_interested_topic": [null, null, null],
      "risk_tolerance": 5,
      "financial_knowledge": 5,
      "trust_on_Oliver": 5
    }',
    greetings = c(
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的自我介绍欢迎词，并询问对方称呼以及能否给对方帮助。。",
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的关于你最近正在做的事情的欢迎词，并询问对方称呼以及是否对你做的事情感兴趣。",
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的询问对方称呼以及理财方面需求的开场词，问题要具体并容易回答。",
      "假设你叫Oliver，是一个金融理财顾问，随机选择一则最近有关个人理财的新闻，并询问对方称呼以及对该新闻的看法。"
    )
  )
)

# Key translation for zh
key_translation_zh <- c(
  gender = "性别",
  age = "年龄",
  occupation = "职业",
  wealth = "财富",
  top3_major_concerns = "前三大关注点",
  top3_major_interested_topic = "前三大兴趣话题"
)

# Default user database
user_db_default <- list(
  gender = NULL,
  age = NULL,
  occupation = NULL,
  wealth = NULL,
  top3_major_concerns = c(NULL, NULL, NULL),
  top3_major_interested_topic = c(NULL, NULL, NULL),
  risk_tolerance = 5,
  financial_knowledge = 5,
  trust_on_me = 3
)

# Gemini API call
gemini_request <- function(prompt) {
  payload <- list(
    contents = list(list(role = "user", parts = list(list(text = prompt))))
  )
  response <- request(paste0(GEMINI_URL, GEMINI_MODEL, ":", GEMINI_ACTION)) %>%
    req_url_query(key = GEMINI_API_KEY) %>%
    req_body_json(payload) %>%
    req_perform() %>%
    resp_body_json()
  response$candidates[[1]]$content$parts[[1]]$text
}

# Generate opening greeting
get_opening_greeting <- function(lang) {
  prompt <- paste0(
    sample(lang_dict[[lang]]$greetings, 1),
    "\n\n",
    lang_dict[[lang]]$response_format
  )
  gemini_request(prompt)
}

# Convert chat history list to a single text block
process_chat_history <- function(history_list) {
  sapply(history_list, function(msg) {
    role <- if (msg$role == "model") "Oliver" else msg$role
    paste0(role, ": ", msg$parts[[1]]$text)
  }) |> paste(collapse = "\n")
}

# Convert raw JSON string (possibly wrapped in ```json ... ```) to R list
safe_json_to_list <- function(txt) {
  cleaned <- gsub("```json\\n|\\n```", "", txt)
  fromJSON(cleaned)
}

# Identify keys still NULL in user data
get_null_keys <- function(data_list) {
  keys <- c("gender", "age", "occupation", "wealth", 
            "top3_major_concerns", "top3_major_interested_topic")
  is_null_or_na <- function(x) is.null(x) || (is.vector(x) && all(is.na(x)))
  names(data_list)[sapply(data_list[keys], is_null_or_na)]
}

# Update user info from chat history
update_client_data <- function(lang, history) {
  prompt <- paste0(history, "\n\n", lang_dict[[lang]]$update_user_db_prompt)
  response_json <- gemini_request(prompt)
  safe_json_to_list(response_json)
}

# Build next prompt based on trust level
build_next_prompt <- function(user_data, null_field_label, history_str) {
  base_prompt <- paste0(
    "假设你叫Oliver，是一个金融理财顾问。\n\n",
    "# 客户背景\n", paste(user_data, collapse = "\n"), 
    "\n\n# 历史对话\n", history_str, "\n\n"
  )
  
  trust <- if (!is.null(user_data$trust_on_Oliver)) {
    user_data$trust_on_Oliver
  } else if (!is.null(user_data$trust_on_me)) {
    user_data$trust_on_me
  } else {
    3
  }
  
  if (trust < 3) {
    return(paste0(
      base_prompt,
      "请生成一句有助于增加客户对你信任的话语。",
      lang_dict[["zh"]]$response_format
    ))
  } else if (trust < 7) {
    return(paste0(
      base_prompt,
      "请生成一句能够询问客户", null_field_label, "方面信息的话语。",
      lang_dict[["zh"]]$response_format
    ))
  } else {
    return(paste0(
      base_prompt,
      "请生成一句能够自然转化话题引起客户焦虑并推荐你的理财服务的话语。",
      lang_dict[["zh"]]$response_format
    ))
  }
}

# Convert Markdown to HTML
convert_md_to_html <- function(md) {
  HTML(markdownToHTML(text = md, fragment.only = TRUE))
}

# Shiny UI
ui <- fluidPage(
  titlePanel(textOutput("title")),
  sidebarLayout(
    sidebarPanel(
      selectInput("language", textOutput("language_label"),
                  choices = c("English" = "en", "中文" = "zh"), selected = "zh"),
      width = 2
    ),
    mainPanel(
      tags$head(
        tags$style(HTML("
          .chat-container {
            max-height: 400px; overflow-y: auto; padding: 10px;
            border: 1px solid #ddd; border-radius: 5px; background-color: #f8f9fa;
          }
          .chat-bubble {
            display: inline-block; padding: 10px; border-radius: 15px; max-width: 75%;
            margin: 5px; word-wrap: break-word;
          }
          .chat-user {
            background-color: #007bff; color: white; text-align: right; float: right; clear: both;
          }
          .chat-ai {
            background-color: #e9ecef; color: black; text-align: left; float: left; clear: both;
          }
        "))
      ),
      div(class = "chat-container", uiOutput("chat_history")),
      textAreaInput("user_input", "", ""),
      actionButton("send", "")
    )
  )
)

# Shiny server
server <- function(input, output, session) {
  
  chat_history <- reactiveVal(list())
  
  # Initialize chat in Chinese
  observe({
    init_msg <- list(role = "model", parts = list(list(text = get_opening_greeting("zh"))))
    chat_history(list(init_msg))
  })
  
  # Regenerate opening greeting when language changes
  observeEvent(input$language, {
    msg <- list(role = "model", parts = list(list(text = get_opening_greeting(input$language))))
    chat_history(list(msg))
  }, ignoreInit = TRUE)
  
  # Send button logic
  observeEvent(input$send, {
    req(input$user_input)
    
    # Append user message
    user_msg <- list(role = "user", parts = list(list(text = input$user_input)))
    updated <- append(chat_history(), list(user_msg))
    chat_history(updated)
    
    # Update user info based on entire conversation
    hist_str <- process_chat_history(updated)
    user_data <- update_client_data(input$language, hist_str)
    
    # Identify a random NULL field (translated)
    null_keys <- get_null_keys(user_data)
    null_key_label <- if (length(null_keys) == 0) {
      "" 
    } else {
      # pick one random null field label in Chinese
      sample(as.character(na.omit(key_translation_zh[null_keys])), 1)
    }
    
    # Build and get next model response
    next_prompt <- build_next_prompt(user_data, null_key_label, hist_str)
    model_response <- gemini_request(next_prompt)
    updated <- append(updated, list(list(role = "model", parts = list(list(text = model_response)))))
    chat_history(updated)
    
    # Clear user input
    updateTextInput(session, "user_input", value = "")
  })
  
  # Dynamic UI labels
  observe({
    lang <- input$language
    updateTextInput(session, "user_input", label = lang_dict[[lang]]$user_input)
    updateActionButton(session, "send", label = lang_dict[[lang]]$send_button)
  })
  
  # Render chat history
  output$chat_history <- renderUI({
    lapply(chat_history(), function(msg) {
      role_label <- if (msg$role == "user") lang_dict[[input$language]]$you 
                    else lang_dict[[input$language]]$ai_name
      bubble_class <- if (msg$role == "user") "chat-bubble chat-user" 
                      else "chat-bubble chat-ai"
      div(class = bubble_class, HTML(
        paste0("<b>", role_label, "</b> ", convert_md_to_html(msg$parts[[1]]$text))
      ))
    }) |> tagList()
  })
  
  # Titles
  output$title <- renderText({ lang_dict[[input$language]]$title })
  output$language_label <- renderText({ lang_dict[[input$language]]$language_label })
}

shinyApp(ui, server)
