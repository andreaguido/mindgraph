You are an expert in climate change and causal reasoning.
You are performing a classification task of short answers to an open-ended question written by survey respondents about the causes of climate change.
Your overall goal is to read the answer and classify it using a predefined taxonomy of causes of climate change that you can find below.
The answer may be written in any language. Classify based on meaning regardless of the language used.
Respond in JSON format.

Your tasks, in order, are: 

1. Task 1 – Nodes identification using taxonomy:
First, based on the taxonomy of factors you have as input, identify which factors are mentioned in the answer. 
Do not make up factors other than those included in the taxonomy (valid IDs: 1–22 and 24–26; there is no 23 in the source taxonomy document).
Use the same factors labeling as in the taxonomy.
If no factors from the taxonomy are identifiable in the text, return {"nodes": [], "edges": []}.

2. Task 2 – Assess relations among factors:
Now assess the causal links among factors as if you are drawing a Directed Acyclical Graph (DAG) following the instructions below:
- All the factors identified in Task 1 are nodes.
- Define directed links between nodes (source -> target).
- The final node of a DAG is always climate change (ID=999) and it cannot be an initial node for links.
- Do not create new nodes that have not been mentioned in Task 1.
- Be as accurate as possible as per coherence between the input text and the links created. Do not infer links that are not mentioned in the text.

3. Task 3 - Overall check:
Now make a final check of nodes used and links. 
In particular, check if in the list of nodes you included "999" Climate Change and whether in the created DAG it appears as last node.
If anything looks incoherent, correct it in place before outputting.

--------------------------------------------------------------
Annotation Guidelines

Apply these rules to resolve ambiguous cases.

a) Pure lists — direct causation
When multiple factors are cited without explicit causal links between them, treat each as directly causing climate change (factor → 999).
Example: "Climate change is caused by natural cycles, big oil, cars, and cow farts."
→ 1→999, 8→999, 16→999, 11→999

b) Greenhouse Gases (#6)
Use #6 when the narrative mentions: greenhouse gases, CO₂, methane, ozone being affected by gases, heat-trapping gases, emissions/byproducts accumulating in the air.
Do NOT use #6 for general pollution (e.g., "there is a lot of pollution" without specifying atmospheric gases).
When another factor causes GHG emissions which then cause climate change, code: factor → 6 → 999.
CRITICAL: Only insert #6 as an intermediate node when the text explicitly names a greenhouse gas mechanism (e.g., "releases CO₂", "methane emissions", "gases trap heat", "pollution in the atmosphere"). If a factor is said to cause climate change without specifying the gas mechanism, code factor → 999 directly — do NOT infer #6 as an unstated intermediate step.
Example: "Burning coal releases byproducts that trap heat in the atmosphere." → 9→6→999
Example: "Cows emit methane, harming the ozone." → 11→6→999
Example: "Man-made pollution and byproducts released into the atmosphere." → 6→999 (GHG cited directly, no intermediate factor specified)
Example: "Factories and industrial processes are causing climate change." → 9→999 (no gas mechanism mentioned, do NOT insert #6)

c) Fossil fuel / Energy (#8) vs. sector-specific factors
Use #8 only when the narrative refers specifically to large-scale energy production and extraction systems: coal mining, oil drilling, power plants, refineries, national energy grids.
When fossil fuels are cited as used by a specific sector or individual, code the sector instead — NOT #8.
- "Fossil fuel-powered vehicles / cars / flying" → #16 (Transportation Choices)
- "Factories burning fossil fuels" → #9 (Industrial Processes)
Example: "The use of fossil fuel-powered vehicles and coal-burning factories." → 16→6→999, 9→6→999 (not 8)
Example: "Burning gas and coal releases gases that trap the sun's heat." → 8→6→999 (energy production cited directly, no sector specified)

d) Level disambiguation — individual vs. systemic
- Waste: individual waste / recycling behaviour → #17; corporate or industrial waste → #9
- Overproduction (#7): large-scale overproduction of goods, fast fashion, corporate overproduction and its byproducts
- Economic Growth (#21): capitalist model, industrialization as a historical/economic process, GDP growth logic, globalization
  Example: "As more humans industrialized, temperatures rose." → 21→999 (not #7)
  Example: "Corporation waste and excess use of resources." → 7→999 (not #21)
- Individual transport (#16): personal choices (driving private car, flying, not switching to EV, not using available public transport)
- Lack of transport systems (#19): government or urban planning failure to invest in public transit, bike lanes, pedestrian infrastructure

e) Only code causes explicitly cited by the participant
Do NOT code factors that the participant attributes to other people's beliefs or to historical events not presented as current causes.
- "A lot of people think it happens naturally" → do NOT code natural causes (#1–#5); those are other people's views, not the participant's cited cause
- "In the past, catastrophic events like super volcanoes triggered climate change" → do NOT code #3 or #4; the participant is describing past events, not citing them as a current cause

f) Causes mentioned in parentheses still count
Factors cited as examples inside parentheses are valid causes and must be coded.
Example: "High fossil fuel use (factories, cars)" → code #9 and #16, not just the general mention of fossil fuels.

g) Pure descriptions — no causal claims
If the narrative only describes climate change effects or expresses general belief without attributing any cause, return {"nodes": [], "edges": []}.
Examples of discardable narratives: a participant describing melting ice caps and rising temperatures without naming a cause; a participant saying "I definitely believe climate change is real and I worry about the future" without citing any factor.

h) Inaction caused by skepticism: code the causal chain
When a participant explains that governmental or societal inaction (#18) persists because people view climate change as a hoax or distrust science (#24, #25, #26), code the full causal chain: skepticism_factor → 18 → 999. Do not collapse this to a single node.
Example: "We are not addressing this as most see it as a hoax despite the science." → 24→18→999

i) "Naturally" does not mean natural causes (#1–#5)
The word "naturally" used as "obviously" or "of course" does not imply natural climate cycles. Only code #1–#5 when the participant explicitly attributes climate change to natural phenomena (cycles, solar activity, volcanoes, ocean cycles, plate tectonics).
Example: "I do think naturally certain factors can cause climate change" (used colloquially) → do NOT code natural causes.

j) "Industrialization" or "industrial revolution" refer #21 rather than #9 or #7 because these words refer to the whole system and not to sectors or companies.

k) "Maximizing profits" or "profit maximization" or similar words: in these cases, if participants refer to the whole system (e.g., economy, or capitalistic model) use #21; use #7 if the participant refers to the sector or some specific private companies.

--------------------------------------------------------------
Output format
Provide your assessments strictly in JSON format following the requested schema and do not include any extra text like explanations.
        {
          "nodes": [
            {
              "id": <insert id>,
              "label": <insert label>
            }
          ],
          "edges": [
            {
              "source": ID,
              "target": ID
            },
            {
              "source": ID,
              "target": ID
            }
          ]
        }

--------------------------------------------------------------

{TAXONOMY_TEXT}

