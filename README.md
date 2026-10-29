# Measuring causal mental models at scale with LLMs: prototype

Prototype repository for the Stage-1 proposal "Measuring Causal Mental Models at Scale using AI" (A. Guido, D. Secchi), *Organization Science* special issue "AI-Assisted Frontiers in Organizational Science".

The instrument reads a free-text answer, for example to "In your own words, what causes X, and how are the causes related?", and returns the respondent's causal mental model as a directed acyclic graph (DAG) over the factors of an *a priori* taxonomy. The model is validated as a coder: on a benchmark sample, its agreement with two trained human coders is compared with the agreement between the two humans.

> **Status: proof of concept.** The code, prompts and taxonomies are the ones used in the Climate Change Narratives project. Survey responses, human codings and model outputs from that project are **not** released. All example data in this repository are synthetic.

## Workflow

```
text corpus ──> 1 taxonomy ──> 2 LLM coder ──> 3 validation ──> deployment
                     ^               ^              │ below target:
                     └───────────────┴──────────────┘ diagnose, revise, re-benchmark
```

1. **Taxonomy** (`taxonomies/`). The researcher fixes the factors a respondent may name as causes of the outcome, each with a definition, examples and boundary rules. This is the only domain-specific input.
2. **LLM coder** (`src/dag_coder.py`, `prompts/`). Each answer is coded independently, in its original language, in three ordered tasks: identify the factors named, link them, check coherence. The output is JSON: `{"nodes": [...], "edges": [{"source": i, "target": j}, ...]}`, where node 999 is the outcome. Parsimony rule: a link is coded only when the respondent states it; mechanisms are never inferred.
3. **Validation** (`annotation_app/`, `src/agreement.py`). Two humans code a benchmark sample in an R Shiny app that uses the same taxonomy and output format. Agreement is computed at the node level, over the fixed set of factors, and at the edge level, over directed pairs among the nodes any coder used. The script reports pairwise Cohen's κ with Po, PABAK, PPA and NPA, and three-way Fleiss' κ. The acceptance criterion is model–human agreement at least as high as human–human agreement.

## Contents

| Path | What |
|---|---|
| `src/dag_coder.py` | LLM coder: one answer or a CSV, sequential or OpenAI Batch API, JSON output with `coding_version` |
| `src/agreement.py` | Three-way agreement metrics (cause DAGs and A1–A7 policy codes) |
| `prompts/climate_cause_agent.md` | Live, validated cause prompt (climate application) |
| `prompts/climate_policy_agent.md` | Live, validated policy prompt (seven binary codes A1–A7) |
| `prompts/generic_cause_agent.md` | Domain-neutral cause prompt: the climate rules are removed; `{OUTCOME}` is a parameter |
| `taxonomies/climate_factor_taxonomy.txt` | 25-factor taxonomy of the causes of climate change |
| `taxonomies/climate_policy_taxonomy.txt` | Policy taxonomy A1–A7 |
| `taxonomies/turnover_taxonomy_illustrative.txt` | Illustrative 11-factor taxonomy of employee turnover (**not validated**) |
| `annotation_app/` | R Shiny app for human coding (configured for the climate taxonomy) |
| `examples/turnover/` | Stylized manager's answer (Figure 2 of the proposal), five further invented answers, and a synthetic agreement demo |

## Install

Python 3.10 or later:

```bash
pip install -r requirements.txt
export OPENAI_API_KEY=...        # PowerShell: $env:OPENAI_API_KEY = "..."
```

The key is read only from the environment. Never commit it.

For the annotation app (R): `install.packages(c("shiny", "shinyjs", "visNetwork", "dplyr", "readr", "DT"))`, then `shiny::runApp("annotation_app")`.

## Quickstart

Code the stylized turnover answer three times, as in Figure 2 of the proposal (this makes 3 API calls):

```bash
python src/dag_coder.py --prompt prompts/generic_cause_agent.md \
    --taxonomy taxonomies/turnover_taxonomy_illustrative.txt \
    --outcome "employee turnover" \
    --text-file examples/turnover/response.txt --repeats 3
```

The result reported in the proposal is in `examples/turnover/figure2_output.json`.

Code a CSV of answers (columns `participant_code` and `narrative`); add `--batch` for the asynchronous Batch API:

```bash
python src/dag_coder.py --prompt prompts/generic_cause_agent.md \
    --taxonomy taxonomies/turnover_taxonomy_illustrative.txt \
    --outcome "employee turnover" \
    --input examples/turnover/responses.csv --output outputs/turnover_dags.json
```

Compute agreement on the synthetic demo (no API calls):

```bash
python src/agreement.py \
    --gpt-cause-json examples/turnover/agreement_demo/model.json \
    --h1-cause examples/turnover/agreement_demo/coder_A.csv \
    --h2-cause examples/turnover/agreement_demo/coder_B.csv \
    --h1-label A --h2-label B --out-dir outputs/agreement_demo \
    --taxonomy taxonomies/turnover_taxonomy_illustrative.txt
```

## Using your own taxonomy

1. Write a taxonomy file in the format of `taxonomies/turnover_taxonomy_illustrative.txt`: one `#ID Name` line per factor, followed by a definition and an example. IDs are integers; 999 is reserved for the outcome.
2. Start from `prompts/generic_cause_agent.md`. Add disambiguation rules as recurring disagreements appear in benchmark coding; the climate prompt shows what mature rules look like.
3. Have two people code a benchmark sample (in our application, 30 answers per language), blind to the model output. Run `src/dag_coder.py` on the same answers and compare with `src/agreement.py --taxonomy <your taxonomy>`.
4. Deploy on the full corpus only once model–human agreement reaches the human–human level. Re-benchmark after any change to the prompt, the taxonomy or the model.

## Reproducibility notes

- **Versioned coding.** Every output record stores `coding_version`, a hash of the filled system prompt (template + taxonomy) and the model name, as well as the model and the reasoning effort. Results produced under different instruments cannot be mixed by accident.
- **Model retirement.** The climate application was validated on OpenAI `o4-mini` (medium reasoning effort), which OpenAI retired on 2026-10-23. The benchmark was re-run on four replacement models (see the technical appendix). This is the reason for the rule above: a change of model is a change of instrument and is re-benchmarked. The default model in `dag_coder.py` is `gpt-6.1-terra`; set `--model` or `OPENAI_MODEL` to change it.
- **Non-determinism.** Reasoning models do not return identical output across calls. Use `--repeats` to measure how stable the output is for a given answer.
- **Data.** The benchmark data (60 responses in English and French, two human codings and the model outputs) are not released. Every data file in this repository is synthetic; to validate the coder, annotate a benchmark sample of your own corpus with `annotation_app/` and run `src/agreement.py`.

## Origin

The pipeline was built for the Climate Change Narratives project (Guido, Fares, Dubois, Romaniuc, Sapone). This repository is a curated copy. The climate prompts, taxonomies, annotation app and agreement metrics are unchanged; the coder script is a simplified, domain-neutral version of the project's CLI, without its incremental-run registry.

## License

MIT. See `LICENSE`.
