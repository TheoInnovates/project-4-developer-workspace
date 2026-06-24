"""
title: BC3 Documentation Lookup
author: local
version: 0.1.0
license: MIT
description: Semantic search over the BC3 Documentation knowledge base (BC3-DS server & display install guides, user manuals, VDD).
"""
from pydantic import BaseModel, Field

BC3_COLLECTION_ID = "78660c75-1ff2-4b04-9b9c-8d49220c123c"


class Tools:
    class Valves(BaseModel):
        collection_id: str = Field(
            default=BC3_COLLECTION_ID,
            description="Knowledge collection id to search (BC3 Documentation).",
        )
        top_k: int = Field(default=5, description="Number of passages to return.")

    def __init__(self):
        self.valves = self.Valves()

    async def search_bc3_documentation(
        self, query: str, __request__=None, __user__=None
    ) -> str:
        """
        Search the BC3 Documentation knowledge base and return the most relevant
        passages with their source document and page number. Use whenever the user
        asks about BC3-DS installation, configuration, setup, operation, maintenance,
        or features (covers the server & display install guides, user manuals, and VDD).
        :param query: A natural-language question or keywords about BC3-DS.
        :return: The top matching passages, each with its source file and page.
        """
        try:
            from open_webui.retrieval.utils import query_collection

            result = await query_collection(
                __request__,
                collection_names=[self.valves.collection_id],
                queries=[query],
                embedding_function=lambda q, prefix: __request__.app.state.EMBEDDING_FUNCTION(
                    q, prefix=prefix, user=None
                ),
                k=self.valves.top_k,
            )
            docs = (result or {}).get("documents") or []
            metas = (result or {}).get("metadatas") or []
            docs = docs[0] if docs and isinstance(docs[0], list) else docs
            metas = metas[0] if metas and isinstance(metas[0], list) else metas
            if not docs:
                return "No relevant passages found in the BC3 Documentation knowledge base."

            blocks = []
            for i, (doc, meta) in enumerate(zip(docs, metas), 1):
                meta = meta or {}
                src = meta.get("name") or meta.get("source") or "unknown source"
                page = meta.get("page")
                header = f"[{i}] {src}" + (f" (page {page})" if page is not None else "")
                blocks.append(header + "\n" + (doc or "").strip()[:800])
            return "\n\n".join(blocks)
        except Exception as e:
            return f"BC3 lookup error: {e}"
