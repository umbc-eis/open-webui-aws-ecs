"""
title: Tool Template
author: open-webui-aws-fargate
version: 1.0.0
description: Skeleton for new document-generation tools. Copy to a new file, rename Tools class methods, and replace the build_file logic.
required_open_webui_version: 0.9.0
"""

import io
import re
import uuid
from typing import Optional

from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        max_size_mb: int = Field(
            default=10,
            description="Refuse to attach files larger than this many megabytes.",
        )

    def __init__(self):
        self.valves = self.Valves()
        self.citation = False

    async def example_method(
        self,
        title: str,
        body: str,
        __event_emitter__=None,
        __user__: Optional[dict] = None,
    ) -> str:
        """
        Example tool method. Replace with the real generator.

        Args:
            title: Title of the artifact (used in the filename).
            body: Plain-text body content.
        """
        data = body.encode("utf-8")
        filename = f"{_safe_filename(title)}.txt"

        return await _attach_file(
            __event_emitter__,
            __user__,
            data=data,
            filename=filename,
            content_type="text/plain",
            max_size_mb=self.valves.max_size_mb,
        )


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
        return (
            f"Refusing to attach: {filename} is "
            f"{len(data) / 1e6:.1f} MB (limit {max_size_mb} MB)."
        )

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
            meta={
                "name": filename,
                "content_type": content_type,
                "size": len(data),
            },
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

    return (
        f"Created **{filename}** ({len(data):,} bytes). "
        "The file is now attached to the chat."
    )
