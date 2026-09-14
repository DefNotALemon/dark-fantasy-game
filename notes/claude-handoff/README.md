# notes/claude-handoff/

Where the in-game Claude chat (F4) drops what it noticed while you played.

Each file is one play session: `YYYY-MM-DD-HHMM.md` — the note-taker's notes
(bugs, ideas, requests, decisions, observations — Haiku reads every exchange and
writes down only what is durable), the chat transcript, and the game state at the
moment it was sent. Written by the card's **Send up the line** button, or on the
way out if notes were still unsent.

The Cowork Claude session that edits this repo reads these at the start of a
round. Nothing here is code; commit them or don't, as you like. Running notes as
they happen (before they are sent) live outside the repo in
`user://claude_notes/<date>.md`.
