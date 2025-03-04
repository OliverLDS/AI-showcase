library(shiny)
library(httr2)
library(markdown)
library(jsonlite)

# ---- Configuration ----
AI_NAME <- "Oliver"
GEMINI_API_KEY <- "[Input Your API Key Here]"
GEMINI_URL <- "https://generativelanguage.googleapis.com/v1beta/models/"
GEMINI_MODEL <- "gemini-2.0-flash"
GEMINI_ACTION <- "generateContent"

# ---- Language dictionary ----
lang_dict <- list(
  en = list(
    title = "Oliver (Wealth management planner)",
    language_label = "Language",
    user_input = "Type your message:",
    send_button = "Send",
    you = "You:",
    ai_name = paste0(AI_NAME, ":"),
    response_format = "Please provide me only the dialogue text, no other content.",
    update_user_db_prompt = paste0(
      "You are Oliver. Based on the chat records between Oliver and the client ",
      '(marked as "you"), respond with the client’s information in the following ',
      "JSON format:\n",
      "gender: One of [\"Male\", \"Female\"], representing the client’s gender.\n",
      "age: One of [\"25 and below\", \"25 to 35\", \"35 to 45\", \"45 to 55\", ",
      "\"55 to 65\", \"Above 65\"], representing the client’s age group.\n",
      "wealth: One of [\"Less than $100,000\", \"$100,000 to $1,000,000\", ",
      "\"$1,000,000 to $10,000,000\", \"Above $10,000,000\"], representing the client’s net worth.\n",
      "risk_tolerance: An integer between 1 and 10 (default is 5), where a higher ",
      "number indicates a greater tolerance for risk.\n",
      "financial_knowledge: An integer between 1 and 10 (default is 5), where a ",
      "higher number indicates greater financial knowledge.\n",
      "trust_on_Oliver: An integer between 1 and 10 (default is 3), where a ",
      "higher number indicates greater trust in Oliver.\n",
      "Return only the JSON object without any additional content.\n",
      "```json\n",
      "{\n",
      '  "gender": null,',
      '  "age": null,',
      '  "occupation": null,',
      '  "wealth": null,',
      '  "top3_major_worries": [null, null, null],',
      '  "top3_major_interested_topic": [null, null, null],',
      '  "risk_tolerance": 5,',
      '  "financial_knowledge": 5,',
      '  "trust_on_Oliver": 3',
      "}\n",
      "```"
    ),
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
    update_user_db_prompt = paste0(
      "你是Oliver, 根据以上Oliver与客户(标注为you)的聊天记录，按下列json格式回复客户信息",
      "(gender: c(\"男\",\"女\"),客户性别; age: c(\"25岁及以下\",\"25岁到35岁\",\"35岁到45岁\",\"45岁到55岁\",",
      "\"55岁到65岁\",\"65岁以上\"); wealth: c(\"小于10万美元\",\"大于等于10万美元且小于100万美元\",",
      "\"大于等于100万美元且小于1000万美元\",\"大于等于1000万美元\"); risk_tolerance: 1到10,默认5; ",
      "financial_knowledge: 1到10,默认5; trust_on_Oliver: 1到10,默认3)，不返回其他内容:\n",
      "```json\n",
      "{\n",
      '  "gender": null,',
      '  "age": null,',
      '  "occupation": null,',
      '  "wealth": null,',
      '  "top3_major_worries": [null, null, null],',
      '  "top3_major_interested_topic": [null, null, null],',
      '  "risk_tolerance": 5,',
      '  "financial_knowledge": 5,',
      '  "trust_on_Oliver": 3',
      "}\n",
      "```"
    ),
    greetings = c(
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的自我介绍欢迎词，并询问对方称呼以及能否给对方帮助。",
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的关于你最近正在做的事情的欢迎词，并询问对方称呼以及是否对你做的事情感兴趣。",
      "假设你叫Oliver，是一个金融理财顾问，返回一句简单的询问对方称呼以及理财方面需求的开场词，问题要具体并容易回答。",
      "假设你叫Oliver，是一个金融理财顾问，随机选择一则最近有关个人理财的新闻，并询问对方称呼以及对该新闻的看法。"
    )
  )
)

# ---- Key translations ----
key_translation <- list(
  en = c(
    gender = "Gender",
    age = "Age",
    occupation = "Occupation",
    wealth = "Wealth",
    top3_major_worries = "Top 3 Major Worries",
    top3_major_interested_topic = "Top 3 Major Interested Topics"
  ),
  zh = c(
    gender = "性别",
    age = "年龄",
    occupation = "职业",
    wealth = "财富",
    top3_major_worries = "前三大担忧话题",
    top3_major_interested_topic = "前三大兴趣话题"
  )
)


# ---- Gemini API call ----
gemini_request <- function(prompt) {
  payload <- list(
    contents = list(
      list(role = "user", parts = list(list(text = prompt)))
    )
  )
  response <- request(paste0(GEMINI_URL, GEMINI_MODEL, ":", GEMINI_ACTION)) %>%
    req_url_query(key = GEMINI_API_KEY) %>%
    req_body_json(payload) %>%
    req_perform() %>%
    resp_body_json()
  # Return the text from the first candidate
  response$candidates[[1]]$content$parts[[1]]$text
}

# ---- Get opening greeting ----
get_opening_greeting <- function(lang) {
  greeting <- sample(lang_dict[[lang]]$greetings, 1)
  prompt <- paste0(greeting, "\n\n", lang_dict[[lang]]$response_format)
  gemini_request(prompt)
}

# ---- Convert chat history list to a single text block ----
process_chat_history <- function(history_list) {
  sapply(history_list, function(msg) {
    role <- if (msg$role == "model") "Oliver" else msg$role
    paste0(role, ": ", msg$parts[[1]]$text)
  }) |> paste(collapse = "\n")
}

# ---- Convert raw JSON string (possibly wrapped in ```json ... ```) to R list ----
safe_json_to_list <- function(txt) {
  cleaned <- gsub("```json\\n|\\n```", "", txt)
  fromJSON(cleaned)
}

# ---- Update user info from chat history ----
update_client_data <- function(lang, history) {
  prompt <- paste0(history, "\n\n", lang_dict[[lang]]$update_user_db_prompt)
  response_json <- gemini_request(prompt)
  safe_json_to_list(response_json)
}

# ---- Build the next prompt based on trust and missing fields ----
compute_priority_scores <- function(user_data, state_data, conversation_round) {
  
  is_null_or_na <- function(x) {
    if (is.null(x)) return(TRUE)
    if (is.vector(x)) return(all(is.na(x)))
    FALSE
  }
  
  worry_is_unknown <- ifelse(is_null_or_na(user_data$top3_major_worries), 1, 0)
  interest_is_unknown <- ifelse(is_null_or_na(user_data$top3_major_interested_topic), 1, 0)
  
  # Define a multiplier based on conversation round
  round_multiplier <- 1 + conversation_round / 5
  trust <- user_data$trust_on_Oliver * round_multiplier
  
  tell_case_score <- rbeta(1, worry_is_unknown*interest_is_unknown*2, trust)
  info_collecting_score <- rbeta(1, worry_is_unknown*2, 1/trust)
  praise_client_score <- ifelse((!interest_is_unknown) & worry_is_unknown, 1, 0)
  raise_worry_score <- ifelse((!worry_is_unknown) & (!state_data$worry_raised), 1, 0)
  introduce_product_score <- ifelse(state_data$worry_raised & (!state_data$product_introduced), 1, 0)
  high_end_service_score <- ifelse(state_data$product_introduced & (!state_data$high_end_pitch_done), 1, 0)
  
  # Return a named numeric vector
  c(
    tell_case      = tell_case_score,
    praise_client  = praise_client_score,
    info_collecting     = info_collecting_score,
    raise_worry         = raise_worry_score,
    introduce_product   = introduce_product_score,
    high_end_service    = high_end_service_score
  )
}


build_next_prompt <- function(user_data, state_data, history_str, language, conversation_round) {
  
  # 1) Compute all scores
  scores <- compute_priority_scores(user_data, state_data, conversation_round)
  
  # 2) Pick the highest-scoring prompt type
  chosen_type <- names(scores)[which.max(scores)]
  
  # 3) Define prompt blocks for each type.
  prompt_blocks <- list(
    tell_case = list(
      en = "Based on the conversation history, generate a sentence describing a case you have served. If you have already mentioned a case, generate a sentence detailing its specifics.",
      zh = "请根据对话记录，生成一句描述你服务过案例的文本。假如你已经提过案例，请生成描绘其细节的文本。"
    ),
    praise_client = list(
      en = "Please generate a sentence that naturally praises the client for being different from the average person based on the known customer information.",
      zh = "请生成一句基于已知客户信息自然地称赞客户与常人不同的文本。"
    ),
    info_collecting = list(
      en = "Please generate a sentence that naturally asks the client about a topic they are concerned about.",
      zh = "请生成一句自然地询问客户担忧话题的文本。"
    ),
    raise_worry = list(
      en = "Please generate a sentence based on the information provided by the client that specifically targets their concerns and evokes a strong sense of anxiety.",
      zh = "请根据客户已提供的信息，特别针对客户担忧话题，生成一句能够引起客户强烈焦虑情绪的话语。"
    ),
    introduce_product = list(
      en = "Generate a sentence that naturally introduces your financial advisory services by addressing the client's anxiety about their concerns, ultimately easing their worries.",
      zh = "生成一句文本，从客户担忧话题焦虑切入，自然地介绍你的金融理财服务，让客户的焦虑情绪得到缓解。"
    ),
    high_end_service = list(
      en = "Generate a four-sentence text and merge it into one paragraph. The first sentence should briefly respond to the client's latest information. The second sentence should inform the client that your financial advisory services are expensive, further lowering their emotional state. The third sentence should guide the client to consider that the high price of your service is due to its exceptional quality. The final sentence should encourage the client to take action, driving the conversion.",
      zh = "生成四句话文本并合并成一段，第一句对客户最后一个信息简单回应。第二句告知客户你的金融理财服务价格高，再度降低客户情绪。第三句引导客户思考你的服务价格不菲，是由于你的服务质量好。最后一句你要推动客户行动来转化交易。"
    )
  )
  
  base_intro <- if (language == "en") {
    "Assume your name is Oliver, a financial advisor.\n\n"
  } else {
    "假设你叫Oliver，是一个金融理财顾问。\n\n"
  }
  
  # Then retrieve the text block
  chosen_block <- prompt_blocks[[chosen_type]][[language]]
  response_format <- lang_dict[[language]]$response_format
  
  # Combine everything
  prompt <- paste0(
    base_intro,
    "# Client Background\n", paste(user_data, collapse = "\n"), "\n\n",
    "# Chat History\n", history_str, "\n\n",
    chosen_block, "\n\n",
    response_format
  )
  
  # 4) Return both the chosen prompt type and the text
  list(
    prompt_type = chosen_type,
    prompt_text = prompt
  )
}



# ---- Convert Markdown to HTML ----
convert_md_to_html <- function(md) {
  HTML(markdownToHTML(text = md, fragment.only = TRUE))
}

# ---- Shiny UI ----
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

# ---- Shiny server ----
server <- function(input, output, session) {
  
  chat_history <- reactiveVal(list())
  
  user_data <- list(
    gender = NULL,
    age = NULL,
    occupation = NULL,
    wealth = NULL,
    top3_major_worries = c(NULL, NULL, NULL),
    top3_major_interested_topic = c(NULL, NULL, NULL),
    risk_tolerance = 5,
    financial_knowledge = 5,
    trust_on_me = 3
  )
  
  state_data <- list(
    worry_raised = FALSE,
    product_introduced = FALSE,
    high_end_pitch_done = FALSE
  )
  
  # Conversation round counter
  conversation_round <- reactiveVal(1)
  
  # Initialize chat in Chinese by default
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
    updated_history <- append(chat_history(), list(user_msg))
    
    # Update conversation round
    conversation_round(conversation_round() + 1)
    
    # Update user info based on entire conversation
    hist_str <- process_chat_history(updated_history)
    user_data <<- update_client_data(input$language, hist_str)
    
    # Build prompt and get model response
    res <- build_next_prompt(user_data, state_data, hist_str, input$language, conversation_round())
    chosen_type <- res$prompt_type
    next_prompt <- res$prompt_text
    model_response <- gemini_request(next_prompt)
    
    print(paste0('Round ', conversation_round(), '\n\n'))
    print(paste0(chosen_type, '\n\n'))
    print(paste0(next_prompt, '\n\n'))
    print(user_data)
    
    # Update conversation state flags based on chosen_type
    if (chosen_type == "raise_worry") {
      state_data$worry_raised <<- TRUE
    } else if (chosen_type == "introduce_product") {
      state_data$product_introduced <<- TRUE
    } else if (chosen_type == "high_end_service") {
      state_data$high_end_pitch_done <<- TRUE
    }
    
    # Append model's response
    updated_history <- append(updated_history, 
                              list(list(role = "model", parts = list(list(text = model_response)))))
    chat_history(updated_history)
    
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
      role_label <- if (msg$role == "user") {
        lang_dict[[input$language]]$you
      } else {
        lang_dict[[input$language]]$ai_name
      }
      bubble_class <- if (msg$role == "user") "chat-bubble chat-user" else "chat-bubble chat-ai"
      div(
        class = bubble_class,
        HTML(paste0("<b>", role_label, "</b> ", convert_md_to_html(msg$parts[[1]]$text)))
      )
    }) |> tagList()
  })
  
  # Titles
  output$title <- renderText({
    lang_dict[[input$language]]$title
  })
  output$language_label <- renderText({
    lang_dict[[input$language]]$language_label
  })
}

shinyApp(ui, server)
