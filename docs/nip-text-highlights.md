NIP-XX
======

Text Highlights
---------------

`draft` `optional`

This NIP defines an `hl` tag that lets the author of a text note mark spans of
their own text to be shown with a coloured background, the way a highlighter
pen marks words on paper.

The note's `content` is left untouched. Clients that do not implement this NIP
display the note exactly as before.

## Motivation

Authors sometimes want to draw the eye to a few words in a note without
changing the words themselves. Inline markup (`==like this==`) would show up as
noise in every client that does not understand it. Carrying the highlight in a
tag keeps the content clean everywhere and lets clients opt in.

## Tag

```json
["hl", "<color>", "<text>"]
```

- `<color>` is one of `yellow` or `pink`. Clients MAY support additional
  colour names; unknown colours SHOULD be rendered as `yellow`.
- `<text>` is the exact text to highlight, as it appears in `content`.

A note MAY carry several `hl` tags. The same text MAY appear in more than one
tag; the last one wins.

Example:

```json
{
  "kind": 1,
  "content": "shipped text highlights in my damus fork today, feels nice",
  "tags": [
    ["hl", "yellow", "text highlights"],
    ["hl", "pink", "feels nice"]
  ]
}
```

## Client behaviour

### Rendering

For each `hl` tag, the client finds every occurrence of `<text>` in the
rendered note content and draws a background in the given colour behind it.
Matching is on the plain rendered text (after mentions are replaced by display
names, URLs by previews, etc.), not on the raw `content`.

Clients SHOULD cap the number of `hl` tags they process per note (20 is
suggested) and SHOULD ignore tags whose `<text>` is empty.

Highlights are presentational only. They carry no meaning for search,
threading, or notifications.

### Composing

A client that supports authoring highlights lets the user select text in the
composer and pick a colour. On publish, each highlighted span becomes one `hl`
tag. Adjacent spans with the same colour SHOULD be merged into one tag.
Leading and trailing whitespace SHOULD be trimmed from `<text>`.

### Scope

`hl` applies to the note's own text. It is distinct from NIP-84 highlights
(kind 9802), which are separate events a *reader* publishes about someone
else's content.

## Security considerations

`<text>` is matched literally and never interpreted, so a malicious tag can at
most colour some words. The per-note cap keeps rendering cost bounded.

## Reference implementation

Damus fork: https://github.com/hasky00/damus (branch `feature/halloween-profile`),
`damus/Features/Posting/Models/TextHighlight.swift`.
