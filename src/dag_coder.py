"""
dag_coder.py — code free-text answers into causal DAGs with an LLM.

Derived from narrative_gpt.py (Climate Change Narratives project). The domain
enters only through two files: a prompt template and a taxonomy. The template
may contain the placeholders {TAXONOMY_TEXT} and {OUTCOME};
they are filled with str.replace, never str.format, because the prompts contain
literal braces in their JSON examples.

Every output record carries a `coding_version`: a hash of the filled system
prompt and the model name. Any change to the prompt, the taxonomy or the model
changes the hash, so results produced under different instruments cannot be
mixed silently.

The OpenAI API key is read from the environment variable OPENAI_API_KEY.

Examples (from the repository root):
    # one answer
    py -3.14 src/dag_coder.py --prompt prompts/generic_cause_agent.md \\
        --taxonomy taxonomies/turnover_taxonomy_illustrative.txt \\
        --outcome "employee turnover" --text-file examples/turnover/response.txt

    # a CSV with columns participant_code (or participant.label) and narrative
    py -3.14 src/dag_coder.py --prompt prompts/generic_cause_agent.md \\
        --taxonomy taxonomies/turnover_taxonomy_illustrative.txt \\
        --outcome "employee turnover" --input examples/turnover/responses.csv \\
        --output outputs/turnover_dags.json [--batch]
"""

import argparse
import csv
import hashlib
import json
import os
import time
from pathlib import Path

DEFAULT_MODEL = "gpt-6.1-terra"
MAX_OUTPUT_TOKENS = int(os.getenv("OPENAI_MAX_OUTPUT_TOKENS", "4000"))
RETRY_MAX_OUTPUT_TOKENS = int(os.getenv("OPENAI_RETRY_MAX_OUTPUT_TOKENS", "10000"))


# ── Instrument ─────────────────────────────────────────────────────────────────
def build_system_prompt(prompt_path: Path, taxonomy_path: Path, outcome: str | None) -> str:
    template = prompt_path.read_text(encoding="utf-8")
    taxonomy = taxonomy_path.read_text(encoding="utf-8")
    prompt = template.replace("{TAXONOMY_TEXT}", taxonomy)
    if "{OUTCOME}" in prompt:
        if not outcome:
            raise SystemExit("This prompt contains {OUTCOME}: pass --outcome.")
        prompt = prompt.replace("{OUTCOME}", outcome)
    return prompt


def coding_version(system_prompt: str, model: str) -> str:
    return hashlib.sha256((system_prompt + model).encode("utf-8")).hexdigest()[:12]


def _is_reasoning_model(model: str) -> bool:
    """Models that accept a reasoning-effort parameter (o-series, gpt-5 and later)."""
    return model.startswith("o") or model.startswith(("gpt-5", "gpt-6"))


def _make_user_prompt(text: str) -> str:
    return (
        "Analyze the following answer to the open-ended question according to the taxonomy:\n\n"
        f'"""{text}"""\n\n'
    )


def _prepare_json_text(output_text: str) -> str:
    text = output_text.strip()
    if text.startswith("```"):
        lines = text.splitlines()[1:]
        while lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end > start:
        text = text[start : end + 1]
    return text


# ── API ────────────────────────────────────────────────────────────────────────
def get_client():
    if not os.getenv("OPENAI_API_KEY"):
        raise SystemExit("Set the environment variable OPENAI_API_KEY first.")
    import openai
    return openai.OpenAI()


def _responses_request(system_prompt, user_prompt, model, effort, max_tokens) -> dict:
    req = {
        "model": model,
        "input": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "max_output_tokens": max_tokens,
    }
    if _is_reasoning_model(model):
        req["reasoning"] = {"effort": effort}
    return req


def _chat_request(system_prompt, user_prompt, model, effort, max_tokens) -> dict:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "max_completion_tokens": max_tokens,
    }
    if _is_reasoning_model(model):
        body["reasoning_effort"] = effort
    return body


def code_one(client, system_prompt: str, text: str, model: str, effort: str) -> dict:
    """Code a single answer; retries once with a larger budget if output is truncated."""
    user_prompt = _make_user_prompt(text)
    resp = client.responses.create(**_responses_request(system_prompt, user_prompt, model, effort, MAX_OUTPUT_TOKENS))
    if getattr(resp, "status", None) == "incomplete":
        resp = client.responses.create(**_responses_request(system_prompt, user_prompt, model, effort, RETRY_MAX_OUTPUT_TOKENS))
    out = getattr(resp, "output_text", "") or ""
    try:
        return json.loads(_prepare_json_text(out))
    except json.JSONDecodeError:
        raise ValueError(f"Failed to parse JSON: {out[:500]}")


def load_csv(path: Path, delimiter: str = ",") -> list:
    csv.field_size_limit(10**9)
    items = []
    with path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f, delimiter=delimiter):
            text = (row.get("narrative") or "").strip()
            pid = ((row.get("participant.label") or "") or (row.get("participant_code") or "")).strip()
            if text:
                items.append({"participant_code": pid, "narrative": text})
    return items


def run_sequential(client, items, system_prompt, model, effort) -> list:
    results = []
    for i, item in enumerate(items):
        print(f"Coding {item['participant_code'] or i}...")
        try:
            analysis = code_one(client, system_prompt, item["narrative"], model, effort)
        except Exception as e:
            print(f"  error: {e}")
            analysis = None
        results.append({**item, "analysis": analysis})
        time.sleep(0.2)
    return results


def run_batch(client, items, system_prompt, model, effort) -> list:
    """OpenAI Batch API (asynchronous, about half the price). Polls until done."""
    lines = [
        json.dumps({
            "custom_id": str(i), "method": "POST", "url": "/v1/chat/completions",
            "body": _chat_request(system_prompt, _make_user_prompt(it["narrative"]), model, effort, RETRY_MAX_OUTPUT_TOKENS),
        })
        for i, it in enumerate(items)
    ]
    f = client.files.create(file=("batch.jsonl", "\n".join(lines).encode("utf-8"), "application/jsonl"), purpose="batch")
    batch = client.batches.create(input_file_id=f.id, endpoint="/v1/chat/completions", completion_window="24h")
    print(f"Batch submitted: {batch.id}")
    while batch.status not in ("completed", "failed", "expired", "cancelled"):
        time.sleep(60)
        batch = client.batches.retrieve(batch.id)
        c = batch.request_counts
        print(f"  status={batch.status} completed={c.completed} failed={c.failed} total={c.total}")
    if batch.status != "completed":
        raise RuntimeError(f"Batch ended with status {batch.status}")
    by_id = {json.loads(l)["custom_id"]: json.loads(l) for l in client.files.content(batch.output_file_id).text.splitlines() if l.strip()}
    results = []
    for i, it in enumerate(items):
        analysis = None
        b = by_id.get(str(i))
        if b and not b.get("error"):
            try:
                analysis = json.loads(_prepare_json_text(b["response"]["body"]["choices"][0]["message"]["content"]))
            except Exception as e:
                print(f"Parse error on item {i}: {e}")
        results.append({**it, "analysis": analysis})
    return results


# ── CLI ────────────────────────────────────────────────────────────────────────
def main() -> None:
    p = argparse.ArgumentParser(description="Code free-text answers into causal DAGs with an LLM.")
    p.add_argument("--prompt", required=True, help="Prompt template (.md)")
    p.add_argument("--taxonomy", required=True, help="Taxonomy (.txt)")
    p.add_argument("--outcome", default=None, help="Outcome label, fills {OUTCOME} in generic prompts")
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--text", help="A single answer, inline")
    src.add_argument("--text-file", help="A single answer, from a text file")
    src.add_argument("--input", help="CSV with participant_code (or participant.label) and narrative")
    p.add_argument("--delimiter", default=",", help="CSV delimiter (default ',')")
    p.add_argument("--output", default=None, help="Output JSON (default: print to screen)")
    p.add_argument("--model", default=os.getenv("OPENAI_MODEL", DEFAULT_MODEL), help=f"Model (default {DEFAULT_MODEL})")
    p.add_argument("--effort", default=os.getenv("OPENAI_REASONING_EFFORT", "medium"), help="Reasoning effort (default medium)")
    p.add_argument("--repeats", type=int, default=1, help="Independent calls per answer (single-answer mode)")
    p.add_argument("--batch", action="store_true", help="Use the OpenAI Batch API (CSV mode)")
    args = p.parse_args()

    system_prompt = build_system_prompt(Path(args.prompt), Path(args.taxonomy), args.outcome)
    version = coding_version(system_prompt, args.model)
    print(f"model={args.model} effort={args.effort} coding_version={version}")
    client = get_client()

    if args.input:
        items = load_csv(Path(args.input), args.delimiter)
        print(f"Loaded {len(items)} answers")
        runner = run_batch if args.batch else run_sequential
        results = runner(client, items, system_prompt, args.model, args.effort)
    else:
        text = args.text if args.text is not None else Path(args.text_file).read_text(encoding="utf-8").strip()
        results = [{"participant_code": f"call_{k + 1}", "narrative": text,
                    "analysis": code_one(client, system_prompt, text, args.model, args.effort)}
                   for k in range(args.repeats)]

    for r in results:
        r.update({"coding_version": version, "model": args.model, "reasoning_effort": args.effort})
    out = json.dumps(results, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(out, encoding="utf-8")
        print(f"Saved {len(results)} records to {args.output}")
    else:
        print(out)


if __name__ == "__main__":
    main()
