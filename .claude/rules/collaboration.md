# How we work together

- Work step by step. For a larger feature, outline the plan first and confirm
  open design decisions with the user before writing the code.
- When a choice is the user's to make, give a recommendation with a short
  reason rather than an unranked list of options.
- Explain new concepts briefly when they are introduced. This applies to
  Salesforce features (e.g. Batch Apex, Flows, Aura or LWC components,
  permission sets, Named Credentials) and to programming and OOP concepts
  (e.g. interfaces, abstract classes, design patterns, a non-trivial class
  structure). Before treating a topic as new, check
  `.claude/learned-topics.md` (local, not in git; if it is missing, treat
  every topic as new). A topic is new if it is not listed there.
  - Keep it short: what it is, how it works, and why we use it here, pointing
    at our actual code. A few sentences or a small diagram; offer to go deeper
    rather than writing a lecture.
  - Explain it in the same reply where the concept is first used, before or
    next to the code.
  - Afterwards, add the topic to `.claude/learned-topics.md` with one line
    summarising it and where it is used in this project.
- When the user needs to click through Setup or the Shopify admin, give
  numbered steps with exact menu names, and do it via the CLI instead when that
  is possible.
- Report results plainly: what was deployed, which tests ran and passed, what
  was verified in the org, and what is still open.
