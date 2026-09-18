---
name: humanize-comments
description: Rewrite review/doc/issue comments so they read like a person wrote them — short, plain, non-prescriptive. Use when drafting or revising outward-facing comments (PR reviews, Google Doc comments, Linear comments), or when asked to "humanize", "make this human readable", "shorten", or "make it less prescriptive".
---

# Humanize Comments

Comments land better when they sound like a colleague, not a report generator. Apply three passes, in order. Each pass has a test.

## Pass 1: Shorten

Test: could the author act on this with half the words?

- One issue per comment. If a draft covers two, split it or cut one.
- 2-3 short sentences, not 4: one for mechanism+impact, one for the ask. If you're still at 4 sentences, you're explaining, not stating — cut one.
- One connector per sentence. If a sentence needs two of "which / so / because / and", split it or drop a clause. This is what makes a comment feel convoluted even when it's technically short.
- Cut background the author doesn't need to act. Cut anything that restates what the code or doc already shows.
- Cut the evidence trail: no "I tested this against X", "verified by grepping Y", "I compared Z". State the conclusion only. If the author wants proof, they'll ask.

## Pass 2: Make it sound human

Test: would a busy senior engineer type this?

- No severity labels ([Must Fix], [Should Fix], [Nit]). The content conveys seriousness.
- No em dashes. Use commas, parentheses, or a new sentence.
- No headers, bullet lists, or bold-lede structure inside a comment body. Plain sentences.
- No stock idioms or engineering-culture jargon ("footgun", "booby trap", "land in the same train", "now is the cheap moment"). Say the concrete thing.
- No "note that" / "it's worth noting" / "importantly". Just say it.
- No exact code locations in the body (file:line goes stale; put the anchor OUTSIDE the body — the quoted doc text or the PR line the comment attaches to). Refer to code by function or symbol name.
- Hedge like a person, only where genuinely unsure: "I think", "FWIW", "as far as I can tell". Not everywhere — hedging everything reads as evasive, hedging nothing reads as a bot.
- Openers that work: "Heads-up:", "FWIW", "I don't think X does Y", "One thing to double-check:". Openers that don't: "This violates...", "Issue:", "Problem:".

## Pass 3: Make it non-prescriptive

Test: does the comment leave the decision with the author?

- Convert directives into questions or observations:
  - "We need to configure X" → "X could handle this. Was that part of the plan?"
  - "Add an error-response test" → "Would it make sense to include an error-response case?"
  - "The stream interceptor should set headers before the handler" → "Setting them as trailers might not have the intended effect."
- State the fact and its consequence; stop before the instruction. The author can derive the fix — that's the point.
- Exception: comments addressed to bots/automation get direct imperatives instead ("Add a span here."). Bots don't have feelings or context; questions waste a round-trip.

## Worked examples

Draft (before):

> **[Should Fix]** `gateway.go:214` — The doc claims metadata is forwarded as HTTP headers with zero configuration. This is incorrect: the default outgoing header matcher prefixes every key with `Grpc-Metadata-` (verified in v2.27.2 runtime/mux.go:153-155), so RFC-aware tooling will not recognize the headers. **Fix:** configure `runtime.WithOutgoingHeaderMatcher` to pass the five keys through unprefixed, add a checklist item, and extend validation to assert unprefixed arrival.

After all three passes:

> I don't think the gateway does this by default. It prefixes all outgoing metadata, so these would arrive as `Grpc-Metadata-Deprecation` etc., which the RFC-aware tooling won't recognize. The mux does accept a custom header matcher that could pass these keys through unprefixed. Was that part of the plan?

---

Still too long, even after three passes (this is the failure mode Pass 1's connector rule exists to catch):

> Tested this against go-git v5.19.2: a deadline during the /info/refs advertisement classifies as transport, but one during the actual upload-pack transfer, the phase that stalls during GitHub degradation, comes back wrapped in plumbing.UnexpectedError, which has no Unwrap. Neither errors.Is nor the substring list catches it, so it falls through to pullCorrupt: the 5-minute grace and a reclone against the same degraded remote, instead of the 30-minute transport grace this is meant to get. Checking fctx.Err() directly, or adding the deadline string to isTransportError, would probably close it, worth a test case alongside TestIsTransportErrorEOFIsNotTransport too.

Cut the evidence trail ("Tested this against...") and split the stacked clauses — this is the target length and shape:

> A deadline during the actual upload-pack transfer comes back as plumbing.UnexpectedError, which has no Unwrap, so isTransportError won't catch it. That means this reclones instead of getting the 30-minute transport grace. Worth also checking fctx.Err() directly, or adding a case to isTransportError's substring list.

A question-form finding, same target shape — mechanism-and-impact in one sentence, the ask as its own short sentence:

> This only guards this instance's own pushes — mainPushGen doesn't track other instances, so a fetch that stalls past another instance's push+apply could still reset main backward past a commit it already landed. Is that ruled out some other way, or does it need its own guard?

## Anchors

Present each comment to the user with its anchor separate from the body:

- PR review: `path/to/file.go` + line (goes in the review payload, never in the body).
- Google Doc: quote the exact sentence or table cell the comment attaches to.
- Linear/issue: the section heading or quoted text.
