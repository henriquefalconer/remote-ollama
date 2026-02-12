# Ollama Anthropic API Compatibility Specification (v2.0.0)

## Overview

Ollama (version 0.5.0+) provides compatibility with the Anthropic Messages API to enable Claude Code and other Anthropic-compatible tools to work with local models. This specification documents the compatibility layer as implemented by Ollama and its limitations.

**Note**: This specification is implementation-agnostic. For v2 architecture (WireGuard + DMZ), clients access via `http://192.168.100.10:11434` instead of Tailscale hostname.

## Architecture

### Implementation

- **Built into Ollama** - No additional server or proxy required
- **Same port** - Served on port 11434 alongside OpenAI API
- **Same models** - Uses the same model pool as OpenAI API
- **Translation layer** - Ollama translates Anthropic API requests to internal inference format

### Dual API Support

```
┌─────────────────────────────────────┐
│   Ollama Server (Port 11434)        │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  OpenAI API (/v1/*)            │ │ ← Aider, Continue
│  │  - /v1/chat/completions        │ │
│  │  - /v1/models                  │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Anthropic API (/v1/messages)  │ │ ← Claude Code
│  │  - POST /v1/messages           │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Ollama Native API (/api/*)    │ │ ← Ollama CLI, metadata tools
│  │  - /api/show                   │ │
│  │  - /api/tags                   │ │
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
```

All three APIs coexist on the same server with no conflicts.

## Endpoint Specification

### POST /v1/messages

**Purpose**: Create a message with Claude-style models

**Request format** (follows Anthropic Messages API):
```json
{
  "model": "qwen3-coder",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": "Hello, how are you?"
    }
  ],
  "system": "You are a helpful assistant.",
  "stream": false,
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 40,
  "stop_sequences": ["Human:", "AI:"],
  "tools": [
    {
      "name": "get_weather",
      "description": "Get weather for a location",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  ]
}
```

**Response format** (non-streaming):
```json
{
  "id": "msg_abc123",
  "type": "message",
  "role": "assistant",
  "model": "qwen3-coder",
  "content": [
    {
      "type": "text",
      "text": "I'm doing well, thank you for asking!"
    }
  ],
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 12,
    "output_tokens": 10
  }
}
```

**Streaming format** (Server-Sent Events):
```
event: message_start
data: {"type":"message_start","message":{"id":"msg_abc123","type":"message","role":"assistant","model":"qwen3-coder","content":[],"stop_reason":null,"usage":{"input_tokens":12,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I'm"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" doing"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","usage":{"output_tokens":10}}}

event: message_stop
data: {"type":"message_stop"}
```

## Supported Features

### ✅ Messages

**Standard message format**:
- ✅ `role` (user, assistant)
- ✅ `content` (text string or array of content blocks)

**Content types**:
- ✅ Text content
- ✅ Image content (base64 encoded)
- ✅ Array of content blocks
- ✅ Tool use blocks
- ✅ Tool result blocks
- ✅ Thinking blocks

### ✅ Streaming

**Fully supported**:
- ✅ Server-Sent Events (SSE) protocol
- ✅ All event types (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`)
- ✅ `ping` events
- ✅ `error` events
- ✅ Text streaming (`text_delta`)
- ✅ Tool use streaming (`input_json_delta`)
- ✅ Thinking streaming (`thinking_delta`)

### ✅ System Prompts

**Supported formats**:
- ✅ String: `"system": "You are a helpful assistant"`
- ✅ Array: `"system": [{"type": "text", "text": "..."}]`

### ✅ Multi-turn Conversations

**Full conversation history**:
- ✅ Multiple messages in `messages` array
- ✅ Alternating user/assistant roles
- ✅ Context maintained across turns (within request)

**Limitation**: No stateful conversation memory across requests (same as OpenAI API).

### ✅ Vision (Images)

**Base64 images supported**:
```json
{
  "role": "user",
  "content": [
    {
      "type": "image",
      "source": {
        "type": "base64",
        "media_type": "image/png",
        "data": "iVBORw0KGgoAAAANS..."
      }
    },
    {
      "type": "text",
      "text": "What's in this image?"
    }
  ]
}
```

**Limitation**: URL-based images (`{"type": "url", "url": "https://..."}`) NOT supported.

### ✅ Tools (Function Calling)

**Tool definition**:
```json
{
  "tools": [
    {
      "name": "get_weather",
      "description": "Get current weather",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  ]
}
```

**Tool use in response**:
```json
{
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_abc123",
      "name": "get_weather",
      "input": {"location": "San Francisco"}
    }
  ]
}
```

**Tool results in follow-up**:
```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "toolu_abc123",
      "content": "Sunny, 72°F"
    }
  ]
}
```

### ✅ Thinking Blocks

**Request**:
```json
{
  "thinking": {
    "type": "enabled",
    "budget_tokens": 1000
  }
}
```

**Response**:
```json
{
  "content": [
    {
      "type": "thinking",
      "thinking": "Let me analyze this step by step..."
    },
    {
      "type": "text",
      "text": "Based on my analysis..."
    }
  ]
}
```

**Limitation**: `budget_tokens` is accepted but not enforced (models may use more or fewer tokens).

## Unsupported Features

### ❌ tool_choice

**What it does** (in real Anthropic API):
- Forces model to use a specific tool
- Or disables tool use entirely

**Why not supported**:
- Ollama's inference layer doesn't implement tool selection control
- Models decide autonomously whether to call tools

**Impact**:
- Cannot force Claude Code to use specific tools at specific times
- May affect reliability of tool orchestration
- Workaround: Use prompt engineering to encourage tool use

### ❌ Prompt Caching

**What it does** (in real Anthropic API):
- Cache frequently-used prompt prefixes
- Dramatically faster responses on cache hits
- Reduced token costs

**Why not supported**:
- Ollama doesn't implement prompt caching mechanism
- Each request processes full context from scratch

**Impact**:
- **Major performance hit** for Ralph loops (60-80% cache hit rate lost)
- ~2-3x slower on workloads with repeated context
- Higher computational cost per request

**This is the single biggest limitation** for Claude Code with Ralph loops.

### ❌ metadata

**What it does** (in real Anthropic API):
- Pass user_id and other metadata for tracking

**Why not supported**:
- Ollama has no user tracking system
- Not needed for local server use case

**Impact**: Minimal (analytics handled separately)

### ❌ /v1/messages/count_tokens

**What it does** (in real Anthropic API):
- Count tokens in a message before sending

**Why not supported**:
- Ollama provides no token counting endpoint for Anthropic format

**Impact**: Cannot pre-check token counts; rely on max_tokens validation errors

**Workaround**: Use approximate counting (1 token ≈ 4 characters)

### ❌ Batches API

**What it does** (in real Anthropic API):
- Process multiple requests asynchronously
- Cost-effective for large batches

**Why not supported**:
- Ollama is synchronous request-response only
- No batch queuing system

**Impact**: Cannot optimize for batch workloads

### ❌ Citations

**What it does** (in real Anthropic API):
- Structured citations in responses

**Why not supported**:
- Ollama models don't generate citation blocks

**Impact**: No structured source attribution

### ❌ PDF Support

**What it does** (in real Anthropic API):
- Upload PDF documents directly
- Extract and analyze PDF content

**Why not supported**:
- Ollama doesn't implement document parsing

**Impact**: Must extract text from PDFs separately before passing to Ollama

**Workaround**: Use `pdftotext` or similar to pre-process PDFs

## Behavioral Differences from Real Anthropic API

### Authentication

**Real Anthropic API**:
- Requires valid API key
- Validates `anthropic-version` header
- Returns 401 on auth failure

**Ollama**:
- Accepts any API key (ignored)
- Accepts `anthropic-version` header (ignored)
- No authentication (relies on network perimeter security - router firewall + VPN)

### Token Counting

**Real Anthropic API**:
- Precise token counts based on Claude tokenizer
- Consistent across models

**Ollama**:
- Approximate token counts
- Varies by underlying model's tokenizer
- May not match reported counts exactly

### Model Names

**Real Anthropic API**:
- Fixed model names (`claude-3-5-sonnet-20241022`, etc.)
- Version strings included

**Ollama**:
- Arbitrary model names (whatever is installed locally)
- No version enforcement
- Can alias any model to any name (e.g., `ollama cp qwen3-coder claude-3-5-sonnet`)

### Error Responses

**Real Anthropic API**:
- Detailed error messages
- Error codes and types
- Streaming errors via `error` events

**Ollama**:
- Simpler error messages
- HTTP status codes only (no detailed error types)
- Streaming errors return HTTP status (not via SSE)

## Performance Characteristics

### Compared to Real Anthropic API

| Aspect | Anthropic Cloud | Ollama Local |
|--------|----------------|--------------|
| **Latency (simple)** | ~1-2s | ~2-5s |
| **Latency (with cache)** | ~0.5s | ~2-5s (no caching) |
| **Throughput** | High (distributed) | Limited (single server) |
| **Concurrency** | Unlimited | Queued (~5-10 concurrent) |
| **Model quality** | ⭐⭐⭐⭐⭐ (Opus/Sonnet) | ⭐⭐⭐ (qwen3-coder, glm-4.7) |
| **Streaming smoothness** | Excellent | Good |
| **Tool use reliability** | Excellent | Good |

### Cache Impact

**With Anthropic cloud** (typical Ralph loop):
- First iteration: 100% cache miss (34k tokens processed)
- Second iteration: 72% cache hit (only 10k tokens processed)
- Third iteration: 80% cache hit (only 7k tokens processed)

**With Ollama local** (same Ralph loop):
- First iteration: No cache (34k tokens processed)
- Second iteration: No cache (34k tokens processed)
- Third iteration: No cache (34k tokens processed)

**Impact**: ~2-3x total latency increase across multi-iteration workflows.

## Recommended Models

### For Coding Tasks

**Best overall**: `qwen3-coder`
- Excellent code generation
- Strong tool use
- 30B parameters (requires 24GB+ VRAM)

**Fast alternative**: `glm-4.7:cloud`
- Cloud-hosted via Ollama
- No local VRAM required
- Good general-purpose performance

**Lightweight**: `qwen3-coder:7b`
- Smaller footprint (7B parameters)
- Faster inference
- Lower quality than 30B

### For General Tasks

**Best overall**: `gpt-oss:20b`
- Strong general reasoning
- Good tool use
- Moderate resource requirements

**Cloud option**: `minimax-m2.1:cloud`
- Cloud-hosted via Ollama
- Fast responses
- Good general performance

## Setup and Configuration

### Server Side (No Configuration Needed)

Anthropic API compatibility is built into Ollama 0.5.0+. No configuration required:

```bash
# Just install and run Ollama normally
brew install ollama
ollama serve  # or use LaunchAgent per server/specs/SCRIPTS.md
```

The `/v1/messages` endpoint is automatically available.

### Client Side

See `client/specs/CLAUDE_CODE.md` for complete Claude Code setup.

**Quick test**:
```bash
curl -X POST http://localhost:11434/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ollama" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "qwen3-coder",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Version Requirements

**Minimum Ollama version**: 0.5.0
- Anthropic compatibility added in 0.5.0
- Earlier versions return 404 for `/v1/messages`

**Recommended**: 0.5.4+
- Bug fixes and improvements
- Better streaming support

**Check version**:
```bash
curl http://localhost:11434/api/version
```

## Limitations Summary

For Claude Code usage, key limitations:

1. **No prompt caching** - Biggest performance impact (~2-3x slower)
2. **No tool_choice** - Cannot force specific tools
3. **Single server queuing** - Limited parallelism (~5-10 concurrent)
4. **Model quality gap** - Local models < Opus/Sonnet
5. **No PDF support** - Must pre-process documents
6. **Base64 images only** - Cannot use image URLs
7. **Experimental status** - API may change in future Ollama versions

Despite limitations, suitable for:
- ✅ Interactive coding sessions
- ✅ Simple file operations
- ✅ Privacy-critical work
- ✅ Offline development

Not recommended for:
- ❌ Ralph loops (no caching, quality gap)
- ❌ Production autonomous agents (experimental stability)
- ❌ High-parallelism workflows (>20 concurrent)
- ❌ Complex multi-step planning (quality critical)

## Stability and Future

**Current status**: Experimental
- API may change without notice
- No backward compatibility guarantees
- May diverge from Anthropic's API over time

**Risk mitigation**:
- Pin Ollama version (see `client/specs/VERSION_MANAGEMENT.md`)
- Pin Claude Code version
- Test updates in staging first
- Maintain fallback to Anthropic cloud API

**Monitoring**:
- Watch Ollama releases: https://github.com/ollama/ollama/releases
- Filter for "anthropic" keyword
- Test compatibility before upgrading

## See Also

- `client/specs/CLAUDE_CODE.md` - Claude Code integration
- `client/specs/API_CONTRACT.md` - Full API contract (OpenAI + Anthropic)
- `client/specs/VERSION_MANAGEMENT.md` - Version compatibility management
- `client/specs/ANALYTICS.md` - Performance measurement tools
- Official Ollama docs: https://docs.ollama.com/llms/anthropic-compatibility
