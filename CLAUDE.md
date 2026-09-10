## Documentation

- **No hard wrapping.** Write each paragraph, list item, and blockquote as one long line and let the renderer soft-wrap. Hard wraps make diffs noisy — a word added early reflows every following line. Code blocks, tables, and shell comments keep their own formatting.
- **README stays short.** It gets install, usage, and the short version of each topic. Everything long lives in `docs/` and the README links to it.

## Commits

- **Code comments in English. Documentation in Korean** (`docs/*.ko.md`), with both `README.md` and `README.ko.md`.
- **One line.** Subject only, no body. The reasoning belongs in `docs/`, not in the log.
- **Split by topic**, not one commit per session. A rename, a behaviour fix, and a docs rewrite are three commits even when they touch the same files — reconstruct intermediate states if you have to.
- No commit should reference a path that does not exist yet at that commit.
- `Co-Authored-By: Claude <noreply@anthropic.com>` is added automatically via the `attribution.commit` setting; the `Claude-Session` link trailer is off (`attribution.sessionUrl: false`) because this repo is public.
