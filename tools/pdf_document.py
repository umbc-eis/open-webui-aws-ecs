"""
title: PDF Document Creator
author: open-webui-aws-fargate
version: 2.0.0
description: Generate a PDF document from a Markdown string. Headings, paragraphs, bullet lists, and numbered lists are supported, with bold/italic inline formatting. The file is delivered as a chat attachment.
required_open_webui_version: 0.9.0
"""

import io
import re
import uuid
from typing import Optional

from pydantic import BaseModel, Field

from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer


class Tools:
    class Valves(BaseModel):
        max_size_mb: int = Field(default=10, description="Refuse to attach files larger than this many megabytes.")

    def __init__(self):
        self.valves = self.Valves()
        self.citation = False

    async def create_pdf(
        self,
        title: str,
        markdown: str,
        __event_emitter__=None,
        __user__: Optional[dict] = None,
    ) -> str:
        """
        Create a PDF document and attach it to the chat.

        Args:
            title: Document title. Rendered as a top-level heading and used as the filename.
            markdown: Document body as Markdown text. Supported syntax:
                - Headings: # H1  ## H2  ### H3
                - Paragraphs: plain text separated by blank lines
                - Bullet lists: lines starting with - or *
                - Numbered lists: lines starting with 1. or 1)
                - Bold: **text**   Italic: *text*   Inline code: `text`
        """
        styles = getSampleStyleSheet()
        bullet_style = ParagraphStyle(
            "BulletItem",
            parent=styles["BodyText"],
            leftIndent=20,
            spaceBefore=1,
            spaceAfter=1,
        )
        heading_styles = {
            1: styles["Heading1"],
            2: styles["Heading2"],
            3: styles["Heading3"],
        }

        story = [Paragraph(_inline(_esc(title)), styles["Title"]), Spacer(1, 12)]

        for block in _parse_blocks(markdown):
            kind = block["kind"]
            text = _inline(_esc(block["text"]))

            if kind == "heading":
                level = min(block["level"], 3)
                story.append(Paragraph(text, heading_styles[level]))
                story.append(Spacer(1, 4))
            elif kind == "bullet":
                story.append(Paragraph(f"• {text}", bullet_style))
            elif kind == "numbered":
                story.append(Paragraph(f"{block['number']}. {text}", bullet_style))
            else:
                story.append(Paragraph(text, styles["BodyText"]))
                story.append(Spacer(1, 6))

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=LETTER, title=title)
        doc.build(story)
        data = buffer.getvalue()

        return await _attach_file(
            __event_emitter__,
            __user__,
            data=data,
            filename=f"{_safe_filename(title)}.pdf",
            content_type="application/pdf",
            max_size_mb=self.valves.max_size_mb,
        )


def _parse_blocks(markdown: str) -> list[dict]:
    """Split markdown into semantic block dicts: heading / bullet / numbered / paragraph."""
    blocks = []
    para_lines: list[str] = []

    def _flush():
        text = " ".join(para_lines).strip()
        if text:
            blocks.append({"kind": "paragraph", "text": text})
        para_lines.clear()

    for line in markdown.splitlines():
        stripped = line.strip()

        if not stripped:
            _flush()
            continue

        m = re.match(r"^(#{1,6})\s+(.*)", stripped)
        if m:
            _flush()
            blocks.append({"kind": "heading", "level": len(m.group(1)), "text": m.group(2).strip()})
            continue

        m = re.match(r"^[-*•]\s+(.*)", stripped)
        if m:
            _flush()
            blocks.append({"kind": "bullet", "text": m.group(1).strip()})
            continue

        m = re.match(r"^(\d+)[.)]\s+(.*)", stripped)
        if m:
            _flush()
            blocks.append({"kind": "numbered", "number": m.group(1), "text": m.group(2).strip()})
            continue

        para_lines.append(stripped)

    _flush()
    return blocks


def _esc(text: str) -> str:
    """Escape XML special characters for ReportLab markup."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _inline(text: str) -> str:
    """Convert inline markdown to ReportLab XML markup. Call after _esc."""
    # Bold before italic so **x** isn't parsed as two *x* wrappers.
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"\*(.+?)\*", r"<i>\1</i>", text)
    text = re.sub(r"`(.+?)`", r'<font name="Courier">\1</font>', text)
    return text


def _safe_filename(name: str, fallback: str = "document") -> str:
    name = re.sub(r"[^\w\-. ]", "_", name).strip()
    return name[:120] or fallback


async def _attach_file(
    event_emitter,
    user: Optional[dict],
    *,
    data: bytes,
    filename: str,
    content_type: str,
    max_size_mb: int = 10,
) -> str:
    if event_emitter is None:
        return f"(no event emitter; would attach {filename}, {len(data)} bytes)"
    if len(data) > max_size_mb * 1024 * 1024:
        return f"Refusing to attach: {filename} is {len(data) / 1e6:.1f} MB (limit {max_size_mb} MB)."

    from open_webui.models.files import Files, FileForm
    from open_webui.storage.provider import Storage

    file_id = str(uuid.uuid4())
    user_id = (user or {}).get("id", "")
    storage_filename = f"{file_id}_{filename}"

    _, storage_path = Storage.upload_file(io.BytesIO(data), storage_filename, {})

    record = await Files.insert_new_file(
        user_id,
        FileForm(
            id=file_id,
            filename=filename,
            path=storage_path,
            meta={"name": filename, "content_type": content_type, "size": len(data)},
        ),
    )
    if record is None:
        return f"Failed to register file {filename} with Open WebUI."

    await event_emitter(
        {
            "type": "files",
            "data": {
                "files": [
                    {
                        "type": "file",
                        "id": record.id,
                        "url": f"/api/v1/files/{record.id}",
                        "name": filename,
                        "size": len(data),
                        "status": "uploaded",
                        "error": "",
                        "itemId": str(uuid.uuid4()),
                    }
                ],
            },
        }
    )

    return f"Created **{filename}** ({len(data):,} bytes). The file is now attached to the chat."
