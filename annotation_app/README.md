> **Note (OrgSci prototype repository).** Copied unchanged from the Climate Change Narratives project. The app is configured for the climate instrument: the 25-factor node list is `nodes.csv` and the outcome node 999 is labelled "Climate Change" in `app.R`; the policy codes A1-A7 are defined in `pol_codes_df` in `app.R`. To use another taxonomy, replace `nodes.csv` (columns ID, Name, Group, Color, Description) and the outcome label. Put the CSV to annotate in `benchmark/` (semicolon-delimited: participant_code;narrative;policy_narrative). `benchmark/example_synthetic.csv` holds two invented answers for testing. Paths such as `inputs/narratives.csv` below refer to the original project.

# Narrative Annotation App

R Shiny app for human annotation of climate change narratives, covering both tasks (selectable at startup):
- **Cause narratives** — annotators identify causal edges between factors from a pre-defined taxonomy, producing a DAG per narrative.
- **Policy narratives** — annotators code each response against a 7-field multi-label taxonomy (A1–A7).

Output is directly compatible with the LLM annotation pipeline (`narrative_gpt.py` / `policy_gpt.py`), enabling human-vs-LLM agreement comparison.

## Install dependencies (once)

```r
install.packages(c("shiny", "shinyjs", "visNetwork", "dplyr", "readr", "DT"))
```

## Launch

```r
shiny::runApp("path/to/annotation_app")
```

Or open `app.R` in RStudio and click **Run App**.

## Usage — Cause narratives

1. **Enter your annotator ID** (your name or initials — used to name the output file)
2. **Load a narratives CSV** — must be semicolon-delimited with columns `participant_code` (or `participant.label`) and `narrative`
   - Use `inputs/narratives.csv` for the full dataset, or `inputs/test_narratives.csv` for testing
3. For each narrative:
   - Read the text on the left
   - **Add causal edges**: select Source → Target from the dropdowns, click **＋ Add edge**
     - Source: any of the 25 causal factors
     - Target: any factor OR **#999 Climate Change** (the outcome node)
   - Use **📖 Factor Glossary** to look up factor definitions and examples
   - If no causal factors are identifiable, click **∅ No factors identified**
   - Click **✓ Save & next** to save and move forward
4. Progress auto-saves. If you close and relaunch with the same annotator ID and narrative file, the app resumes where you left off.

## Output — Cause narratives

Saved to `outputs/narrative_edges_[annotator_id]_[file].csv`

Format (semicolon-delimited, matches LLM output):
```
participant_code;source;target
abc123;8;6
abc123;6;999
def456;;
```

- Each row is one directed edge: `source → target`
- Rows with `;;` mean no causal factors were identified in that narrative
- Multiple rows per participant = multiple edges in their DAG

## Usage — Policy narratives

1. **Enter your annotator ID**, choose **Policy narratives** as the task, and load a CSV with columns `participant_code` (or `participant.label`) and `policy_narrative`.
2. For each response:
   - Read the text on the left.
   - **Check all A1–A7 codes that apply** — they are independent multi-label flags, not mutually exclusive (except A7, see below). Each checkbox shows a short signal-word hint; use **📖 Taxonomy Glossary** for the full boundary rules and worked examples.
   - Leave all boxes unchecked if no policy instrument is mentioned — an all-zero vector is a valid output for vague/non-committal responses.
   - A7 (Skeptical/No action) is mutually exclusive with A1–A4 and A6; the app shows a warning (not a hard block) if you check A7 together with any of those, since A7 should normally only co-occur with A5 (adapting while rejecting mitigation).
   - Click **✓ Save & next**.
3. Progress auto-saves and resumes the same way as cause annotation.

## Output — Policy narratives

Saved to `outputs/policy_annotations_[annotator_id]_[file].csv`

Format (semicolon-delimited, matches LLM output):
```
participant_code;A1;A2;A3;A4;A5;A6;A7;comment
abc123;1;0;1;0;0;0;0;
def456;0;0;0;0;0;0;0;
```

- One row per participant; each of A1–A7 is `0` or `1`.
- An all-zero row is a valid, legitimate code (no instrument mentioned).

## Policy taxonomy

7 binary codes, non-mutually exclusive except A7:

| Code | Field | Notes |
|---|---|---|
| A1 | Restrict / Regulate | legal compulsion or prohibition |
| A2 | Price / Incentivize | tax, subsidy, rebate — price signal |
| A3 | Invest / Build | direct government provision/funding |
| A4 | Inform / Educate | awareness, education, public knowledge |
| A5 | Adapt / Protect | coping with impacts, not preventing them |
| A6 | International / Coordinate | requires a substantive international-action proposal |
| A7 | Skeptical / No action | mutually exclusive with A1–A4, A6; can co-occur with A5 |

Full definitions, signal words, boundary rules, and worked examples are in `documents/policy_taxonomy.txt` and `agents/policy_agent.Md`, and accessible in-app via the **📖 Taxonomy Glossary** button.

## Factor taxonomy

25 factors (IDs #1–#22, #24–#26; no #23) organised into 5 levels:

| Level | IDs | Colour |
|---|---|---|
| Natural Causes | 1–5 | Green |
| Human-caused (I) Structural | 6–12 | Dark blue |
| Human-caused (II) Personal | 13–17 | Red |
| Political and Institutional | 18–22 | Purple |
| Skepticism & Misinformation | 24–26 | Grey |
| Climate Change (outcome) | 999 | Black |

Full definitions with examples are in `nodes.csv` and accessible in-app via the **📖 Factor Glossary** button.

Source document: `documents/factor_taxonomy.txt`
