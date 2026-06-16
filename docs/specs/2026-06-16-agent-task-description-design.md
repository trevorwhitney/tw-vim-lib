# Agent Task Description Column - Design Specification

**Date:** 2026-06-16  
**Status:** Approved

## Overview

Add a task description column to the agent sidebar that displays a brief AI-generated summary of what each agent is working on. Descriptions are generated lazily using the Anthropic API when the sidebar first displays an agent.

## Requirements

- Display 4-5 word description next to each agent in the sidebar
- Generate descriptions using Anthropic Claude API
- Show loading state while description generates
- Show error state if generation fails
- Cache descriptions (static, not dynamic updates)
- Lazy generation: only when sidebar first displays the agent
- No external dependencies beyond existing plenary.nvim

## Architecture

### Module Structure

#### New Module: `lua/tw/agent/description.lua`

Manages LLM-based description generation and caching.

**Public API:**
- `generate(buf)` - Async function to generate description for a buffer
- `get(buf)` - Synchronous lookup returning current state (nil, "loading", string, or "error")
- `invalidate(buf)` - Clear cached description

**Internal State:**
- `descriptions = {}` - Cache mapping buffer number to description string
- `loading = {}` - Set of buffer numbers currently generating descriptions

**State Transitions:**
- `nil` → not yet requested
- `"loading"` → async generation in progress
- `string` → successfully generated description
- `"error"` → generation failed

**Implementation Details:**

1. **Text Extraction:**
   - Read first 75 lines from terminal buffer (balance between context and API cost)
   - Strip ANSI escape codes using pattern similar to `status.lua:strip_ansi()`
   - Join lines into single text block

2. **API Request:**
   - Use `plenary.curl` for async HTTP POST
   - Endpoint: `https://api.anthropic.com/v1/messages`
   - Model: `claude-3-haiku-20240307` (fast, cheap)
   - Headers:
     - `x-api-key`: from `ANTHROPIC_API_KEY` environment variable
     - `anthropic-version`: `2023-06-01`
     - `content-type`: `application/json`
   - Request body:
     ```json
     {
       "model": "claude-3-haiku-20240307",
       "max_tokens": 20,
       "messages": [{
         "role": "user",
         "content": "Summarize what this agent/terminal is doing in exactly 4-5 words:\n\n<terminal output>"
       }]
     }
     ```
   - Timeout: 10 seconds

3. **Response Handling:**
   - Parse JSON response
   - Extract description from `response.content[0].text`
   - Truncate to 30 characters with "..." if longer
   - Store in cache
   - Trigger sidebar refresh to update display

4. **Error Handling:**
   - Network timeout → set to `"error"`
   - Invalid API key → set to `"error"`
   - Rate limits → set to `"error"`
   - Malformed response → set to `"error"`
   - Missing `ANTHROPIC_API_KEY` → skip generation, return `nil`

5. **Cleanup:**
   - Register `BufWipeout` autocmd to invalidate cache when buffer closes
   - Prevent memory leaks from long-running Neovim sessions

#### Modified Module: `lua/tw/agent/sidebar.lua`

**Changes to `collect_entries()`:**
- Add `description` field to each entry
- Call `description.get(inst.buf)` to retrieve current state
- Store result in entry

**Changes to `render_lines()`:**
- Current format: `"  oc#0  waiting"`
- New format with description: `"  oc#0  waiting  fixing tests"`
- Loading state: `"  oc#0  waiting  ⋯ loading..."`
- Error state: `"  oc#0  waiting  ⚠ failed"`
- No description (nil/missing key): `"  oc#0  waiting"`
- Use two spaces between status and description for separation

**Changes to `refresh()`:**
- After `collect_entries()`, loop through entries
- For each entry where `description.get(buf)` returns `nil`:
  - Check if `ANTHROPIC_API_KEY` is set
  - If set, call `description.generate(buf)` to start async generation
  - Mark as "loading" immediately
- When async generation completes, trigger another `refresh()` to update display

**Width Considerations:**
- Current default width: 20 (will be tight with descriptions)
- Recommendation: increase default to 45-50 for better readability
- User can still configure via `setup({ width = ... })`
- Description truncation at 30 chars ensures it doesn't overflow excessively

### Data Flow

1. User opens sidebar → `M.open()` → `refresh()` called
2. `collect_entries()` builds entry list:
   - For each agent instance, calls `description.get(buf)`
   - First time: returns `nil`
3. `refresh()` detects `nil` descriptions:
   - Checks for `ANTHROPIC_API_KEY` environment variable
   - If present, triggers `description.generate(buf)` async
   - Marks buffer as "loading"
   - Renders "⋯ loading..." in sidebar
4. Async request completes:
   - Success: stores description string in cache
   - Failure: stores `"error"` in cache
   - Calls `vim.schedule(sidebar.refresh)` to update UI
5. Next `refresh()`:
   - `description.get(buf)` returns actual string or `"error"`
   - Renders final state in sidebar

### Concurrency & Deduplication

- Track in-flight requests using `loading` set
- Before starting `generate(buf)`, check if `buf` already in `loading`
- If already loading, skip duplicate request
- Remove from `loading` set when request completes (success or error)
- Prevents duplicate API calls if `refresh()` runs multiple times quickly

## Error Handling

### API Failures

All API failures display `"⚠ failed"` in the description column:

- Network timeout (>10s)
- Invalid/missing API key
- Rate limit exceeded
- HTTP errors (4xx, 5xx)
- Malformed JSON response
- Missing expected fields in response

### Edge Cases

**Missing API Key:**
- If `ANTHROPIC_API_KEY` not set: skip generation entirely
- Description remains empty/blank (no error indicator)
- Allows users to opt out of feature

**Buffer Lifecycle:**
- When agent terminal closes: `description.invalidate(buf)` clears cache
- When same agent index reopens: treated as new terminal, regenerates description
- Prevents stale descriptions from persisting

**Long Descriptions:**
- LLM may return more than requested 4-5 words
- Truncate to 30 characters with "..." suffix
- Ensures predictable sidebar layout

**Concurrent Requests:**
- Use `loading` set to track in-flight requests
- Prevents duplicate API calls for same buffer

## Testing Strategy

### Unit Tests (Standalone Lua)

Test description module logic:
- Cache operations (get, set, invalidate)
- State transitions (nil → loading → string/error)
- Text truncation logic
- ANSI stripping

### Integration Tests (Plenary)

Test sidebar integration:
- Description rendering in sidebar
- Loading state display
- Error state display
- Lazy generation trigger
- Buffer cleanup on terminal close

### Manual Testing

- Verify API calls with real Anthropic key
- Test error states (invalid key, network issues)
- Verify layout with various description lengths
- Confirm performance with multiple agents

## Configuration

### Environment Variables

- `ANTHROPIC_API_KEY` - Required for description generation. If not set, feature is disabled.

### Sidebar Configuration

```lua
require("tw.agent.sidebar").setup({
  width = 45,  -- Increased from 20 to accommodate descriptions
  -- ... other existing options
})
```

No new configuration options needed. Feature works automatically if API key is present.

## Implementation Checklist

1. Create `lua/tw/agent/description.lua` module
   - Implement cache and state management
   - Implement text extraction and ANSI stripping
   - Implement Anthropic API integration with plenary.curl
   - Implement async completion handler
   - Add BufWipeout autocmd for cleanup

2. Update `lua/tw/agent/sidebar.lua`
   - Add description field to entries in `collect_entries()`
   - Update `render_lines()` to include description column
   - Add lazy generation trigger in `refresh()`
   - Update default width to 45

3. Add tests
   - Unit tests for description module
   - Integration tests for sidebar rendering
   - Manual API testing

4. Update documentation
   - Add feature description to README
   - Document ANTHROPIC_API_KEY requirement
   - Add troubleshooting section

## Future Enhancements (Out of Scope)

- Dynamic description updates (refresh periodically while agent works)
- Configurable update frequency
- Alternative LLM providers (OpenAI, local models)
- Configurable context lines
- Retry logic for failed requests
- Description history/changelog
