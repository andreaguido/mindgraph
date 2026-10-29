library(shiny)
library(shinyjs)
library(visNetwork)
library(dplyr)
library(readr)
library(DT)

# ── Data ──────────────────────────────────────────────────────────────────────
nodes_df <- read_csv("nodes.csv", show_col_types = FALSE)

out_dir <- normalizePath("outputs", mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── Factor choices (cause annotation) ─────────────────────────────────────────
make_choices <- function(include_outcome = TRUE) {
  df <- if (include_outcome) nodes_df else filter(nodes_df, ID != 999)
  groups <- unique(df$Group)
  setNames(
    lapply(groups, function(g) {
      sub_df <- filter(df, Group == g)
      setNames(as.character(sub_df$ID),
               paste0("#", sub_df$ID, " — ", sub_df$Name))
    }),
    groups
  )
}

src_choices <- make_choices(include_outcome = FALSE)
tgt_choices <- make_choices(include_outcome = TRUE)

# ── Policy taxonomy (A1–A7 multi-label) ───────────────────────────────────────
pol_codes_df <- data.frame(
  Code = c("A1", "A2", "A3", "A4", "A5", "A6", "A7"),
  Name = c("Restrict / Regulate", "Price / Incentivize", "Invest / Build",
           "Inform / Educate", "Adapt / Protect", "International / Coordinate",
           "Skeptical / No action"),
  Hint = c(
    "ban, fine, mandatory, quota, oblige, standards",
    "carbon tax, subsidy, rebate, cheaper / more expensive",
    "invest, build, fund, plant trees, R&D, infrastructure",
    "awareness campaign, school curriculum, public communication",
    "sea walls, drought-resistant crops, early warning systems",
    "UN agreement, COP, lead by example, pressure other countries",
    "natural cycle, hoax, markets/tech will fix it, no intervention"
  ),
  Boundary = c(
    "vs A2: a fine enforcing a standard → A1; a tax changing a price signal → A2 (can co-occur). vs A3: “government plants trees” → A3, “companies must replant trees” → A1.",
    "vs A1: subsidy to a private actor → A2, government directly building infrastructure → A3 (can co-occur with either).",
    "vs A4: R&D to deploy technology → A3, R&D whose primary output is public knowledge → A4. vs A1: see A1.",
    "Awareness/education as the primary lever — distinct from R&D for public knowledge (also A4 boundary) vs deployment (A3).",
    "Coping with impacts already occurring/projected, not preventing them. Can legitimately co-occur with A7 (adapt while rejecting mitigation).",
    "Requires a substantive proposal for international action — a passing “climate change is global” remark does not qualify. Co-occurs freely with A1–A5.",
    "Mutually exclusive with A1–A4 and A6. The only valid co-occurrence is with A5 (adapt while rejecting mitigation)."
  ),
  stringsAsFactors = FALSE
)

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  useShinyjs(),

  tags$head(tags$style(HTML("
    body { font-family: 'Helvetica Neue', Arial, sans-serif; background: #f4f6f8; }

    #start-card {
      max-width: 520px; margin: 80px auto;
      background: white; padding: 40px; border-radius: 8px;
      box-shadow: 0 2px 16px rgba(0,0,0,.10);
    }

    #topbar-cause, #topbar-policy {
      background: white; border-bottom: 1px solid #dee2e6;
      padding: 10px 20px; margin-bottom: 16px;
      display: flex; align-items: center; justify-content: space-between;
    }

    .nar-box {
      background: white; border: 1px solid #dee2e6; border-radius: 6px;
      padding: 18px; height: 380px; overflow-y: auto;
      font-size: 15px; line-height: 1.75; color: #212529;
    }

    .ann-card {
      background: white; border: 1px solid #dee2e6; border-radius: 6px;
      padding: 16px; max-height: 82vh; overflow-y: auto;
    }

    .sec-label {
      font-weight: 600; font-size: 13px; color: #495057;
      margin: 12px 0 4px; text-transform: uppercase; letter-spacing: .03em;
    }

    .sub-label {
      font-weight: 600; font-size: 11px; color: #6c757d;
      margin: 8px 0 2px; text-transform: uppercase; letter-spacing: .03em;
    }

    .edge-item {
      display: flex; align-items: center; gap: 8px;
      background: #e9ecef; border-radius: 4px;
      padding: 5px 10px; margin-bottom: 4px; font-size: 13px;
    }

    .no-fac-note {
      background: #fff3cd; border: 1px solid #ffc107;
      border-radius: 4px; padding: 8px 12px; font-size: 13px;
    }

    .arr { font-size: 18px; color: #6c757d; margin-top: 28px; text-align: center; }

    .dim-block { border-left: 3px solid #dee2e6; padding-left: 10px; margin-bottom: 10px; }
    .dim-block.codes { border-color: #40916c; }
  "))),

  # ── Startup screen ──────────────────────────────────────────────────────────
  div(id = "start-screen",
    div(id = "start-card",
      h3("Narrative Annotation Tool", style = "margin-top:0; color:#1d3557"),
      p("Climate Change Narratives · Human Annotation", style = "color:#6c757d"),
      hr(),
      textInput("annotator_id", "Your name or annotator ID:", placeholder = "e.g. Andrea"),

      div(class = "sec-label", style = "margin-top:16px", "Task:"),
      radioButtons("task_mode", label = NULL,
                   choices = c("Cause narratives (DAG)"  = "cause",
                               "Policy narratives"        = "policy"),
                   selected = "cause"),

      div(class = "sec-label", style = "margin-top:12px", "File:"),
      uiOutput("ui_file_choice"),
      br(),
      actionButton("btn_start", "Start annotating →",
                   class = "btn-primary",
                   style = "width:100%; font-size:16px; padding:10px")
    )
  ),

  # ── Cause main screen ────────────────────────────────────────────────────────
  hidden(div(id = "main-cause",

    div(id = "topbar-cause",
      div(
        strong(textOutput("txt_annotator_cause")),
        actionButton("btn_back_cause", "← Back", class = "btn-sm btn-outline-secondary",
                     style = "margin-left:12px")
      ),
      strong(textOutput("txt_progress_cause")),
      actionButton("btn_glossary", "\U0001F4D6 Factor Glossary",
                   class = "btn-sm btn-outline-secondary")
    ),

    fluidRow(
      column(7, style = "padding-left:24px; padding-right:12px",
        div(style = "display:flex; justify-content:space-between; align-items:baseline; margin-bottom:6px",
          h6(strong("Cause narrative"), style = "margin:0"),
          tags$small(textOutput("txt_pid_cause"), style = "color:#6c757d")
        ),
        div(class = "nar-box", uiOutput("ui_narrative_cause")),
        br(),
        div(style = "display:flex; gap:8px",
          actionButton("btn_prev_cause", "← Previous", class = "btn-sm btn-outline-secondary"),
          actionButton("btn_skip_cause", "Skip →",     class = "btn-sm btn-outline-secondary")
        )
      ),
      column(5, style = "padding-left:12px; padding-right:24px",
        div(class = "ann-card",
          div(class = "sec-label", "Add a causal edge:"),
          fluidRow(
            column(5, selectInput("src", "Source (cause):", choices = src_choices, selectize = TRUE)),
            column(2, div(class = "arr", HTML("&rarr;"))),
            column(5, selectInput("tgt", "Target (effect):", choices = tgt_choices,
                                  selected = "999", selectize = TRUE))
          ),
          div(style = "display:flex; gap:8px; flex-wrap:wrap",
            actionButton("btn_add",   "＋ Add edge",             class = "btn-success btn-sm"),
            actionButton("btn_nofac", "∅ No factors identified", class = "btn-sm btn-warning")
          ),
          div(class = "sec-label", style = "margin-top:16px", "Edges for this narrative:"),
          uiOutput("ui_edges"),
          div(class = "sec-label", style = "margin-top:16px", "DAG preview:"),
          visNetworkOutput("dag_preview", height = "175px"),
          hr(style = "margin:12px 0"),
          textAreaInput("cause_comment", "Comment (optional):",
                        placeholder = "Notes or doubts about this annotation…",
                        rows = 2, width = "100%"),
          actionButton("btn_save_cause", "✓ Save & next →",
                       class = "btn-primary", style = "width:100%; font-size:15px; padding:8px")
        )
      )
    )
  )),

  # ── Policy main screen ───────────────────────────────────────────────────────
  hidden(div(id = "main-policy",

    div(id = "topbar-policy",
      div(
        strong(textOutput("txt_annotator_policy")),
        actionButton("btn_back_policy", "← Back", class = "btn-sm btn-outline-secondary",
                     style = "margin-left:12px")
      ),
      strong(textOutput("txt_progress_policy"))
    ),

    fluidRow(
      column(7, style = "padding-left:24px; padding-right:12px",
        div(style = "display:flex; justify-content:space-between; align-items:baseline; margin-bottom:6px",
          h6(strong("Policy narrative"), style = "margin:0"),
          tags$small(textOutput("txt_pid_policy"), style = "color:#6c757d")
        ),
        div(class = "nar-box", uiOutput("ui_narrative_policy")),
        br(),
        div(style = "display:flex; gap:8px",
          actionButton("btn_prev_policy", "← Previous", class = "btn-sm btn-outline-secondary"),
          actionButton("btn_skip_policy", "Skip →",     class = "btn-sm btn-outline-secondary")
        )
      ),

      column(5, style = "padding-left:12px; padding-right:24px",
        div(class = "ann-card",

          div(style = "display:flex; justify-content:space-between; align-items:baseline",
            div(class = "sec-label", style = "margin-top:0", "Policy codes (A1–A7) — select all that apply"),
            actionButton("btn_policy_glossary", "\U0001F4D6 Taxonomy Glossary",
                         class = "btn-sm btn-outline-secondary")
          ),
          div(class = "dim-block codes",
            checkboxGroupInput("pol_codes", label = NULL,
              choiceNames = lapply(seq_len(nrow(pol_codes_df)), function(i) {
                tagList(
                  strong(paste0(pol_codes_df$Code[i], " — ", pol_codes_df$Name[i])),
                  br(),
                  tags$small(pol_codes_df$Hint[i], style = "color:#6c757d")
                )
              }),
              choiceValues = pol_codes_df$Code
            )
          ),
          p("Leave all unchecked if no instrument is mentioned (a vague/non-committal response is a valid zero-vector output).",
            style = "color:#adb5bd; font-size:12px; margin:-8px 0 12px"),

          hr(style = "margin:12px 0"),
          textAreaInput("pol_comment", "Comment (optional):",
                        placeholder = "Notes or doubts about this annotation…",
                        rows = 2, width = "100%"),
          actionButton("btn_save_policy", "✓ Save & next →",
                       class = "btn-primary", style = "width:100%; font-size:15px; padding:8px")
        )
      )
    )
  ))
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  rv <- reactiveValues(
    narratives        = NULL,
    annotator_id      = "",
    task_mode         = "cause",

    # Cause annotation state
    cur_idx_cause     = 1L,
    cause_edges       = list(),
    cause_no_factors  = FALSE,
    cause_done_codes  = character(0),
    cause_annotations = list(),
    cause_out_file    = NULL,

    # Policy annotation state
    cur_idx_policy    = 1L,
    pol_done_codes    = character(0),
    pol_annotations   = list(),
    pol_out_file      = NULL
  )

  # ── File selection ───────────────────────────────────────────────────────────
  output$ui_file_choice <- renderUI({
    files <- list.files("benchmark", pattern = "\\.csv$", full.names = FALSE)
    if (length(files) == 0)
      return(p("No CSV files found in the benchmark folder.",
               style = "color:#dc3545; font-size:13px;"))
    radioButtons("chosen_file", label = NULL,
                 choices  = setNames(files, gsub("\\.csv$", "", files)),
                 selected = character(0))
  })

  sanitize_comment <- function(x) {
    if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(trimws(x))) return("")
    gsub("[;\n\r\t]", " ", trimws(as.character(x)))
  }

  # ── Helpers ──────────────────────────────────────────────────────────────────
  safe_stem <- function(annotator, filename)
    paste0(gsub("[^A-Za-z0-9_-]", "_", annotator), "_", gsub("\\.csv$", "", filename))

  load_cause_ann <- function(code) {
    ann <- rv$cause_annotations[[code]]
    rv$cause_edges      <- if (!is.null(ann)) ann$edges      else list()
    rv$cause_no_factors <- if (!is.null(ann)) ann$no_factors else FALSE
    updateTextAreaInput(session, "cause_comment",
      value = if (!is.null(ann) && !is.null(ann$comment)) ann$comment else "")
  }

  load_pol_ann <- function(code) {
    ann <- rv$pol_annotations[[code]]
    if (!is.null(ann)) {
      updateCheckboxGroupInput(session, "pol_codes", selected = ann$codes)
      updateTextAreaInput(session, "pol_comment",
        value = if (!is.null(ann$comment)) ann$comment else "")
    } else {
      updateCheckboxGroupInput(session, "pol_codes", selected = character(0))
      updateTextAreaInput(session, "pol_comment", value = "")
    }
  }

  write_cause_file <- function() {
    lines <- "participant_code;source;target;comment"
    for (code in names(rv$cause_annotations)) {
      ann     <- rv$cause_annotations[[code]]
      comment <- sanitize_comment(ann$comment)
      if (ann$no_factors) {
        lines <- c(lines, paste0(code, ";;;", comment))
      } else {
        for (i in seq_along(ann$edges)) {
          e           <- ann$edges[[i]]
          comment_col <- if (i == 1) comment else ""
          lines <- c(lines, paste0(code, ";", e[1], ";", e[2], ";", comment_col))
        }
      }
    }
    writeLines(lines, rv$cause_out_file)
  }

  write_pol_file <- function() {
    lines <- "participant_code;A1;A2;A3;A4;A5;A6;A7;comment"
    for (code in names(rv$pol_annotations)) {
      ann     <- rv$pol_annotations[[code]]
      comment <- sanitize_comment(ann$comment)
      flags   <- as.integer(pol_codes_df$Code %in% ann$codes)
      lines <- c(lines, paste0(code, ";", paste(flags, collapse = ";"), ";", comment))
    }
    writeLines(lines, rv$pol_out_file)
  }

  # ── Start ─────────────────────────────────────────────────────────────────────
  observeEvent(input$btn_start, {
    ann <- trimws(input$annotator_id)
    if (!nzchar(ann)) {
      showNotification("Please enter your annotator ID.", type = "error"); return()
    }
    if (is.null(input$chosen_file) || !nzchar(input$chosen_file)) {
      showNotification("Please select a file.", type = "error"); return()
    }

    df <- tryCatch(
      read_delim(file.path("benchmark", input$chosen_file), delim = ";",
                 show_col_types = FALSE, locale = locale(encoding = "UTF-8")),
      error = function(e) NULL
    )
    if (is.null(df)) {
      showNotification("Could not read file. Check semicolon delimiter.", type = "error"); return()
    }
    if ("participant.label" %in% names(df) && !"participant_code" %in% names(df))
      df <- rename(df, participant_code = `participant.label`)

    mode <- input$task_mode
    rv$task_mode    <- mode
    rv$narratives   <- df
    rv$annotator_id <- ann
    stem            <- safe_stem(ann, input$chosen_file)

    # ── Cause mode ────────────────────────────────────────────────────────────
    if (mode == "cause") {
      if (!all(c("participant_code", "narrative") %in% names(df))) {
        showNotification("File must have 'participant_code' and 'narrative' columns.",
                         type = "error"); return()
      }
      rv$cause_annotations <- list()
      rv$cause_done_codes  <- character(0)
      rv$cause_out_file <- file.path(out_dir, paste0("narrative_edges_", stem, ".csv"))

      if (file.exists(rv$cause_out_file)) {
        prev <- tryCatch(
          read_delim(rv$cause_out_file, delim = ";", show_col_types = FALSE),
          error = function(e) NULL
        )
        if (!is.null(prev) && !"comment" %in% names(prev)) prev$comment <- ""
        if (!is.null(prev) && nrow(prev) > 0) {
          rv$cause_done_codes <- unique(prev$participant_code)
          anns <- list()
          for (code in rv$cause_done_codes) {
            rows <- filter(prev, participant_code == code)
            comment_val <- if ("comment" %in% names(rows)) {
              v <- rows$comment[!is.na(rows$comment) & nzchar(rows$comment)]
              if (length(v) > 0) v[1] else ""
            } else ""
            if (nrow(rows) == 1 && (is.na(rows$source[1]) || rows$source[1] == "")) {
              anns[[code]] <- list(edges = list(), no_factors = TRUE, comment = comment_val)
            } else {
              anns[[code]] <- list(
                edges = lapply(seq_len(nrow(rows)), function(i)
                  c(as.integer(rows$source[i]), as.integer(rows$target[i]))),
                no_factors = FALSE,
                comment    = comment_val
              )
            }
          }
          rv$cause_annotations <- anns
          remaining        <- which(!df$participant_code %in% rv$cause_done_codes)
          rv$cur_idx_cause <- if (length(remaining) > 0) remaining[1] else nrow(df)
          load_cause_ann(df$participant_code[rv$cur_idx_cause])
          showNotification(paste0("Resuming: ", length(rv$cause_done_codes),
                                  " already annotated."), type = "message", duration = 5)
        }
      } else {
        writeLines("participant_code;source;target", rv$cause_out_file)
        rv$cur_idx_cause <- 1L
      }
      hideElement("start-screen"); showElement("main-cause")

    # ── Policy mode ───────────────────────────────────────────────────────────
    } else {
      if (!all(c("participant_code", "policy_narrative") %in% names(df))) {
        showNotification("File must have 'participant_code' and 'policy_narrative' columns.",
                         type = "error"); return()
      }
      rv$pol_annotations <- list()
      rv$pol_done_codes  <- character(0)
      rv$pol_out_file    <- file.path(out_dir, paste0("policy_annotations_", stem, ".csv"))

      if (file.exists(rv$pol_out_file)) {
        prev <- tryCatch(
          read_delim(rv$pol_out_file, delim = ";", show_col_types = FALSE),
          error = function(e) NULL
        )
        if (!is.null(prev) && !"comment" %in% names(prev)) prev$comment <- ""
        if (!is.null(prev) && nrow(prev) > 0 && all(pol_codes_df$Code %in% names(prev))) {
          rv$pol_done_codes <- unique(prev$participant_code)
          anns <- list()
          for (code in rv$pol_done_codes) {
            row         <- filter(prev, participant_code == code)[1, ]
            comment_val <- if ("comment" %in% names(row)) {
              v <- as.character(row$comment); if (!is.na(v)) v else ""
            } else ""
            anns[[code]] <- list(
              codes   = pol_codes_df$Code[as.logical(as.integer(unlist(row[1, pol_codes_df$Code])))],
              comment = comment_val
            )
          }
          rv$pol_annotations <- anns
          remaining         <- which(!df$participant_code %in% rv$pol_done_codes)
          rv$cur_idx_policy <- if (length(remaining) > 0) remaining[1] else nrow(df)
          load_pol_ann(df$participant_code[rv$cur_idx_policy])
          showNotification(paste0("Resuming: ", length(rv$pol_done_codes),
                                  " already annotated."), type = "message", duration = 5)
        } else if (!is.null(prev) && nrow(prev) > 0) {
          showNotification(
            "Existing output file uses an old policy schema and will be overwritten from scratch under the new A1–A7 taxonomy.",
            type = "warning", duration = 8)
          writeLines("participant_code;A1;A2;A3;A4;A5;A6;A7;comment", rv$pol_out_file)
          rv$cur_idx_policy <- 1L
        }
      } else {
        writeLines("participant_code;A1;A2;A3;A4;A5;A6;A7;comment", rv$pol_out_file)
        rv$cur_idx_policy <- 1L
      }
      hideElement("start-screen"); showElement("main-policy")
    }
  })

  # ── Back buttons ─────────────────────────────────────────────────────────────
  observeEvent(input$btn_back_cause,  { hideElement("main-cause");  showElement("start-screen") })
  observeEvent(input$btn_back_policy, { hideElement("main-policy"); showElement("start-screen") })

  # ── Current rows ──────────────────────────────────────────────────────────────
  cur_cause_row  <- reactive({ req(rv$narratives); rv$narratives[rv$cur_idx_cause,  ] })
  cur_policy_row <- reactive({ req(rv$narratives); rv$narratives[rv$cur_idx_policy, ] })

  # ── Topbars ───────────────────────────────────────────────────────────────────
  output$txt_annotator_cause  <- renderText(paste("Annotator:", rv$annotator_id))
  output$txt_annotator_policy <- renderText(paste("Annotator:", rv$annotator_id))

  output$txt_progress_cause <- renderText({
    req(rv$narratives)
    paste0("Narrative ", rv$cur_idx_cause, " / ", nrow(rv$narratives),
           "  ·  ", length(rv$cause_done_codes), " saved")
  })
  output$txt_progress_policy <- renderText({
    req(rv$narratives)
    paste0("Narrative ", rv$cur_idx_policy, " / ", nrow(rv$narratives),
           "  ·  ", length(rv$pol_done_codes), " saved")
  })

  output$txt_pid_cause  <- renderText(paste("Participant:", cur_cause_row()$participant_code))
  output$txt_pid_policy <- renderText(paste("Participant:", cur_policy_row()$participant_code))

  # ── Narrative displays ────────────────────────────────────────────────────────
  output$ui_narrative_cause  <- renderUI(p(cur_cause_row()$narrative))
  output$ui_narrative_policy <- renderUI(p(cur_policy_row()$policy_narrative))

  # ── Cause annotation logic ────────────────────────────────────────────────────
  observeEvent(input$btn_add, {
    req(input$src, input$tgt)
    rv$cause_no_factors <- FALSE
    src <- as.integer(input$src); tgt <- as.integer(input$tgt)
    if (src == tgt) {
      showNotification("Source and target must differ.", type = "warning"); return()
    }
    if (any(sapply(rv$cause_edges, function(e) e[1] == src && e[2] == tgt))) {
      showNotification("Edge already added.", type = "warning"); return()
    }
    rv$cause_edges <- c(rv$cause_edges, list(c(src, tgt)))
  })

  observeEvent(input$btn_nofac, {
    rv$cause_edges      <- list()
    rv$cause_no_factors <- TRUE
  })

  lapply(seq_len(50), function(i) {
    observeEvent(input[[paste0("del_", i)]], {
      if (i <= length(rv$cause_edges)) rv$cause_edges <- rv$cause_edges[-i]
    }, ignoreInit = TRUE)
  })

  output$ui_edges <- renderUI({
    if (rv$cause_no_factors)
      return(div(class = "no-fac-note", "∅  No causal factors identified."))
    if (length(rv$cause_edges) == 0)
      return(p("No edges yet.", style = "color:#adb5bd; font-size:13px; margin:0"))
    tagList(lapply(seq_along(rv$cause_edges), function(i) {
      e <- rv$cause_edges[[i]]
      div(class = "edge-item",
        span(style = "flex:1",
          strong(paste0("#", e[1])), " ", nodes_df$Name[nodes_df$ID == e[1]],
          HTML(" &rarr; "),
          strong(paste0("#", e[2])), " ", nodes_df$Name[nodes_df$ID == e[2]]
        ),
        actionButton(paste0("del_", i), "×",
                     style = paste("padding:0 6px; min-height:20px; line-height:1;",
                                   "font-size:12px; background:transparent;",
                                   "border:none; color:#dc3545; cursor:pointer"))
      )
    }))
  })

  output$dag_preview <- renderVisNetwork({
    empty_graph <- function() {
      vn <- data.frame(id = 999, label = "Climate\nChange",
                       color.background = "#212529", color.border = "#212529",
                       font.color = "white", shape = "ellipse", stringsAsFactors = FALSE)
      visNetwork(vn, data.frame(from = integer(0), to = integer(0))) %>%
        visOptions(height = "175px") %>%
        visInteraction(dragNodes = FALSE, zoomView = FALSE)
    }
    if (rv$cause_no_factors || length(rv$cause_edges) == 0) return(empty_graph())
    all_ids <- unique(unlist(rv$cause_edges))
    vn <- nodes_df %>%
      filter(ID %in% all_ids) %>%
      transmute(
        id               = ID,
        label            = paste0("#", ID, "\n",
                                  ifelse(nchar(Name) > 18, paste0(substr(Name,1,16),"…"), Name)),
        color.background = Color, color.border = Color,
        font.color       = ifelse(Color %in% c("#212529","#1d3557","#6a0572"), "white", "black"),
        shape            = ifelse(ID == 999, "ellipse", "box"),
        title            = paste0("<b>#", ID, " ", Name, "</b><br><br>", Description)
      )
    ve <- data.frame(from = sapply(rv$cause_edges, `[`, 1),
                     to   = sapply(rv$cause_edges, `[`, 2),
                     arrows = "to", stringsAsFactors = FALSE)
    visNetwork(vn, ve) %>%
      visEdges(arrows = list(to = list(enabled = TRUE, scaleFactor = 0.7))) %>%
      visLayout(randomSeed = 42) %>%
      visOptions(height = "175px") %>%
      visInteraction(dragNodes = TRUE, zoomView = FALSE)
  })

  observeEvent(input$btn_save_cause, {
    req(rv$cause_out_file, cur_cause_row())
    if (!rv$cause_no_factors && length(rv$cause_edges) == 0) {
      showNotification("Add an edge or click '∅ No factors identified'.",
                       type = "warning"); return()
    }
    code <- cur_cause_row()$participant_code
    anns <- rv$cause_annotations
    anns[[code]] <- list(edges = rv$cause_edges, no_factors = rv$cause_no_factors,
                         comment = trimws(input$cause_comment))
    rv$cause_annotations <- anns
    rv$cause_done_codes  <- unique(c(rv$cause_done_codes, code))
    write_cause_file()
    remaining <- which(!rv$narratives$participant_code %in% rv$cause_done_codes)
    if (length(remaining) == 0) {
      showModal(modalDialog(
        title = "Annotation complete!",
        p(paste0("All ", nrow(rv$narratives), " narratives annotated.")),
        p(strong("Output: "), code(rv$cause_out_file)),
        footer = modalButton("Close")
      ))
    } else {
      rv$cur_idx_cause <- remaining[1]
      load_cause_ann(rv$narratives$participant_code[rv$cur_idx_cause])
    }
  })

  observeEvent(input$btn_prev_cause, {
    if (rv$cur_idx_cause > 1) {
      rv$cur_idx_cause <- rv$cur_idx_cause - 1L
      load_cause_ann(rv$narratives$participant_code[rv$cur_idx_cause])
    }
  })
  observeEvent(input$btn_skip_cause, {
    req(rv$narratives)
    if (rv$cur_idx_cause < nrow(rv$narratives)) {
      rv$cur_idx_cause <- rv$cur_idx_cause + 1L
      load_cause_ann(rv$narratives$participant_code[rv$cur_idx_cause])
    }
  })

  # ── Glossary ─────────────────────────────────────────────────────────────────
  observeEvent(input$btn_glossary, {
    showModal(modalDialog(title = "Factor Taxonomy Glossary", size = "xl",
                          easyClose = TRUE, footer = modalButton("Close"),
                          DT::dataTableOutput("dt_glossary")))
  })
  output$dt_glossary <- DT::renderDataTable(
    nodes_df %>% filter(ID != 999) %>%
      select(ID, Name, Group, Description) %>%
      rename(`#` = ID, Factor = Name, Level = Group),
    options  = list(pageLength = 10, dom = "ftp", scrollX = TRUE),
    rownames = FALSE, escape = FALSE
  )

  # ── Policy annotation logic ───────────────────────────────────────────────────
  observeEvent(input$btn_policy_glossary, {
    showModal(modalDialog(title = "Policy Taxonomy Glossary", size = "xl",
                          easyClose = TRUE, footer = modalButton("Close"),
                          DT::dataTableOutput("dt_policy_glossary")))
  })
  output$dt_policy_glossary <- DT::renderDataTable(
    pol_codes_df %>%
      rename(Field = Name, `Signal words` = Hint, `Boundaries / notes` = Boundary),
    options  = list(pageLength = 7, dom = "ftp", scrollX = TRUE),
    rownames = FALSE, escape = FALSE
  )

  observeEvent(input$pol_codes, {
    codes <- input$pol_codes
    if ("A7" %in% codes && length(intersect(codes, c("A1", "A2", "A3", "A4", "A6"))) > 0) {
      showNotification(
        "A7 (Skeptical/No action) with A1/A2/A3/A4/A6 is almost always an error — please double-check. A7 normally only co-occurs with A5.",
        type = "warning", duration = 6)
    }
  }, ignoreNULL = FALSE)

  observeEvent(input$btn_save_policy, {
    req(rv$pol_out_file, cur_policy_row())
    code <- cur_policy_row()$participant_code
    anns <- rv$pol_annotations
    anns[[code]] <- list(
      codes   = input$pol_codes,
      comment = trimws(input$pol_comment)
    )
    rv$pol_annotations <- anns
    rv$pol_done_codes  <- unique(c(rv$pol_done_codes, code))
    write_pol_file()
    remaining <- which(!rv$narratives$participant_code %in% rv$pol_done_codes)
    if (length(remaining) == 0) {
      showModal(modalDialog(
        title = "Annotation complete!",
        p(paste0("All ", nrow(rv$narratives), " policy narratives annotated.")),
        p(strong("Output: "), code(rv$pol_out_file)),
        footer = modalButton("Close")
      ))
    } else {
      rv$cur_idx_policy <- remaining[1]
      load_pol_ann(rv$narratives$participant_code[rv$cur_idx_policy])
    }
  })

  observeEvent(input$btn_prev_policy, {
    if (rv$cur_idx_policy > 1) {
      rv$cur_idx_policy <- rv$cur_idx_policy - 1L
      load_pol_ann(rv$narratives$participant_code[rv$cur_idx_policy])
    }
  })
  observeEvent(input$btn_skip_policy, {
    req(rv$narratives)
    if (rv$cur_idx_policy < nrow(rv$narratives)) {
      rv$cur_idx_policy <- rv$cur_idx_policy + 1L
      load_pol_ann(rv$narratives$participant_code[rv$cur_idx_policy])
    }
  })
}

shinyApp(ui, server)
