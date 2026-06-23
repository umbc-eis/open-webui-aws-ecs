# Open WebUI Tools

Source-of-truth Python files for Open WebUI Tools deployed in this stack. Each file is a self-contained Open WebUI tool — the LLM calls a tool method during chat, the backend executes it, and the result (typically a generated file) appears in the conversation.

Tools run inside the Open WebUI backend container. Any pip dependency a tool needs must be installed in the deployed image (see `docker/requirements-extras.txt` and `scripts/build-and-push.sh`) — Open WebUI's per-tool `requirements:` frontmatter is not used here.

## Current tools

| File | Method | Output | Library |
|---|---|---|---|
| `word_document.py` | `create_word_document(title, sections)` | `.docx` | python-docx (overlay) |
| `powerpoint.py` | `create_powerpoint(title, slides)` | `.pptx` | python-pptx (upstream) |
| `spreadsheet.py` | `create_spreadsheet(sheets, filename)` | `.xlsx` | openpyxl (upstream) |
| `pdf_document.py` | `create_pdf(title, sections)` | `.pdf` | reportlab (overlay) |
| `_template.py` | — | — | template only; do not install |

"overlay" = added by `docker/requirements-extras.txt`. "upstream" = ships in the base Open WebUI image.

## Installing a tool

Tools are stored in the Open WebUI database. There is no automated import in this stack — admins paste each tool through the UI:

1. Sign in as an admin user.
2. Navigate to **Workspace → Tools**.
3. Click **➕ Create Tool** (or the equivalent "new tool" button).
4. Paste the entire content of the `.py` file. The docstring frontmatter (`title`, `description`, `version`) auto-populates the form.
5. Save.
6. The tool now appears in the registry. Per-user enable: in any chat, click the tools icon and toggle the tool on. Per-model enable: in **Workspace → Models**, edit the model and attach the tool.

To update a tool, edit the saved entry in the UI and paste the new file content. Bump the `version:` line in the docstring so the version surfaces in the list.

## Adding a new tool

1. Copy `_template.py` to `tools/<your_tool_name>.py`.
2. Edit the docstring frontmatter (`title`, `description`, `version`).
3. Rename the `Tools.example_method` to your tool's actual method name. The method docstring is the description shown to the LLM — keep it precise. Each parameter's type annotation and the docstring `Args:` block become the JSON schema for the LLM tool call.
4. Replace the body with the actual generation logic. Use `io.BytesIO` to build files in memory rather than writing to disk.
5. Hand the bytes to `_attach_file()` — that helper handles file registration with Open WebUI and emits the chat event.
6. **If the tool needs new pip dependencies:**
   - Pin them in `docker/requirements-extras.txt` (only add libs *not already* in the upstream Open WebUI image — check upstream `backend/requirements.txt` first).
   - Rebuild and push the image: `./scripts/build-and-push.sh --tag-suffix extrasN` (bump `N`).
   - Update `terraform.tfvars` `open_webui_image_url` to the new tag.
   - `terraform apply` — ECS rolls onto the new image.
7. Install via the UI as above.

## Pattern notes

Each tool is **fully self-contained**. Open WebUI stores tools as individual Python files in the database and does not provide module-sharing across tools, so the `_safe_filename` and `_attach_file` helpers are duplicated in every file. When the helper changes, update all tool files.

Special parameters available on tool methods (Open WebUI injects them automatically if declared):

| Parameter | Type | Use |
|---|---|---|
| `__event_emitter__` | callable | Send events to the chat (status, files, citations) |
| `__event_call__` | callable | Blocking RPC to the client |
| `__user__` | dict | The calling user's record (`id`, `email`, `name`, `role`, ...) |
| `__metadata__` | dict | Chat metadata (chat_id, message_id, session_id, files, ...) |
| `__request__` | FastAPI Request | The active HTTP request |
| `__model__` | dict | The model record |
| `__chat_id__` | str | Convenience accessor |
| `__message_id__` | str | Convenience accessor |

Only declare the special params the tool actually uses — Open WebUI filters injection to the method's signature.

## Risk reminders

- Tools execute in the main backend process **as root**, with full container privileges (env has DB credentials, OAuth secrets, the WEBUI_SECRET_KEY). A tool that takes an LLM-supplied path and `open()`s it = LLM-driven path traversal.
- Always use `io.BytesIO` to build outputs in memory; never write files at LLM-controlled paths.
- Cap input sizes via `Valves` so an LLM can't request a 10-million-row spreadsheet that exhausts memory.
- Generation-only is much safer than parsing user uploads. Pure generators (these four) avoid lxml XXE / zip-bomb surface that would matter if we were *reading* `.docx`/`.xlsx` files. If you ever add a parser, use `defusedxml` or the library's safe-parse mode and cap input size.
- Pin upstream dependency versions in `docker/requirements-extras.txt` — unpinned installs land surprising versions into prod.

## Testing a new tool

1. **Static check** (locally):
   ```sh
   python -c "import ast; ast.parse(open('tools/<file>.py').read())"
   ```
   The libraries themselves aren't installed in the local venv, so a full import check happens inside the deployed container.
2. **In Open WebUI**: enable the tool on a test user, prompt the LLM with a request that should trigger it (e.g. *"Create a Word document titled 'Test' with three sections..."*). Confirm:
   - The LLM invokes the tool (visible in the collapsed tool-call block).
   - The tool returns a confirmation message.
   - A downloadable file attachment appears in the chat.
   - The downloaded file opens in the corresponding application without warnings.
3. **Refusal paths**: ask for an absurdly large output and confirm the size guard rejects it gracefully.
