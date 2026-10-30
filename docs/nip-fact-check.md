NIP-XX
======

Fact Checks
-----------

`draft` `optional`

This NIP defines a `fact-check` label namespace for [NIP-32](https://github.com/nostr-protocol/nips/blob/master/32.md)
labels (kind `1985`). A fact check is a verdict that one user (or an agent
acting on a user's request) attaches to someone else's note, optionally with a
source link and a short explanation.

Nothing is central. A fact check is just a signed event like any other. Every
client decides for itself whose verdicts to show; the recommended default is
verdicts from people the viewer follows.

## Motivation

Fact checking on centralised platforms is done by the platform, which readers
may not trust. On Nostr the natural unit of trust is the follow graph: if people
I follow say a note is misleading, that is worth showing me. If strangers say
it, that is worth a collapsed hint at most.

Reusing NIP-32 means any client that already renders labels can display fact
checks without new code, and relays need no changes.

## Event

A fact check is a kind `1985` event with:

```json
{
  "kind": 1985,
  "content": "<optional one-line explanation>",
  "tags": [
    ["L", "fact-check"],
    ["l", "<verdict>", "fact-check"],
    ["e", "<id of the note being checked>"],
    ["p", "<pubkey of that note's author>"],
    ["r", "<source url>"]
  ]
}
```

- `L` / `l` follow NIP-32. The namespace is `fact-check`.
- `<verdict>` MUST be one of:
  - `true` — the claim holds up
  - `false` — the claim does not hold up
  - `misleading` — technically true but gives a false impression
  - `needs-context` — missing information that changes the picture
  - `satire` — the note is a joke or parody and not a factual claim
- `e` points at the checked note. Exactly one `e` tag SHOULD be present.
- `p` points at the author of the checked note so they can be notified.
- `r` is an optional source. Multiple `r` tags MAY be given.
- `content` is an optional short explanation in plain text.

A user who publishes a second fact check on the same note replaces their first;
clients SHOULD show only the newest verdict per author.

## Display

Clients SHOULD show a compact summary under the checked note (for example the
most common verdict and how many people gave it) and let the reader expand it
to see each verdict, its author, explanation and sources.

Clients SHOULD, by default, only count verdicts from pubkeys the reader follows
(plus the reader's own), and MAY offer a way to reveal the rest. Clients MUST
NOT hide or alter the checked note itself because of a fact check.

## Agents

A fact-checking agent (software that reads sources and publishes a verdict)
uses the same event from its own key. Clients MAY mark such verdicts visually.
Agents SHOULD only check a note when a user asks them to, SHOULD include at
least one `r` source tag, and SHOULD state in their kind `0` profile that they
are an agent.

## Example

```json
{
  "kind": 1985,
  "content": "The report says 12%, not 40%.",
  "tags": [
    ["L", "fact-check"],
    ["l", "misleading", "fact-check"],
    ["e", "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"],
    ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
    ["r", "https://example.org/report-2026"]
  ]
}
```
