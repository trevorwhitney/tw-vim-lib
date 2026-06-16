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
- `generate(buf, callback)` - Async function to generate description for a buffer. Calls callback(description_or_error) when complete.
- `get(buf)` - Synchronous lookup returning current state (nil, "loading", string, or "error")
- `invalidate(buf)` - Clear cached description

**Internal State:**
- `descriptions = {}` - Cache mapping buffer number to description string or "error"
- `loading = {}` - Set of buffer numbers currently generating descriptions

**State Transitions:**
- `nil` → not yet requested (not in cache, not in loading set)
- `"loading"` → async generation in progress (in loading set, not yet in cache)
- `string` → successfully generated description (in cache)
- `"error"` → generation failed (in cache)

**Implementation Note:** The `get(buf)` function checks both the cache and loading set:
```lua
function M.get(buf)
  if loading[buf] then
    return "loading"
  end
  return descriptions[buf]  -- nil, string, or "error"
end
```

**Implementation Details:**

1. **Text Extraction:**
   - Read first 75 lines from terminal buffer (balance between context and API cost)
   - Strip ANSI escape codes using pattern similar to `status.lua:strip_ansi()`
   - Join lines into single text block

2. **API Request:**
   - Check for `ANTHROPIC_API_KEY` environment variable at module load time
   - If not set, all `generate()` calls are no-ops (skip request, don't set loading state)
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
       "max_tokens": 30,
       "messages": [{
         "role": "user",
         "content": "Summarize what this agent/terminal is doing in 4-5 words:\n\n<terminal output>"
       }]
     }
     ```
   - Timeout: 10 seconds
   - **API Key Guard:** The `description.lua` module owns the API key check. If no key is present, `generate()` returns immediately without setting loading state or making a request.

3. **Response Handling:**
   - Parse JSON response
   - Extract description from `response.content[0].text`
   - Trim whitespace
   - Truncate to 30 characters with "..." if longer (using `vim.str_utf_pos()` to respect UTF-8 boundaries)
   - Store in cache: `descriptions[buf] = trimmed_description`
   - Remove from loading set: `loading[buf] = nil`
   - Call callback with description string

4. **Error Handling:**
   - Network timeout → set `descriptions[buf] = "error"`, remove from loading set, call callback with "error"
   - Invalid API key (401/403) → set `descriptions[buf] = "error"`, remove from loading set, call callback with "error"
   - Rate limits (429) → remove from loading set WITHOUT caching error, call callback with nil (allows retry on next refresh)
   - HTTP errors (other 4xx, 5xx) → set `descriptions[buf] = "error"`, remove from loading set, call callback with "error"
   - Malformed JSON response → set `descriptions[buf] = "error"`, remove from loading set, call callback with "error"
   - Missing expected fields in response → set `descriptions[buf] = "error"`, remove from loading set, call callback with "error"
   - Missing `ANTHROPIC_API_KEY` → `generate()` returns immediately, no loading state, no request, no callback invocation

5. **Cleanup:**
   - Register `TermClose` autocmd (pattern `agent://*`) to invalidate cache when agent terminal exits
   - Consistent with existing `sidebar.lua` lifecycle management
   - Prevent memory leaks from long-running Neovim sessions

#### Modified Module: `lua/tw/agent/sidebar.lua`

**Changes to `collect_entries()`:**
- Add `description` field to each entry
- Call `description.get(inst.buf)` to retrieve current state
- Store result in entry (will be nil, "loading", string, or "error")

**Changes to `render_lines()`:**
- Current format: `"  oc#0  waiting"`
- New format with description: `"  oc#0  waiting  fixing tests"`
- Loading state: `"  oc#0  waiting  ⋯ loading..."`
- Error state: `"  oc#0  waiting  ⚠ failed"`
- No description (nil/missing key): `"  oc#0  waiting"`
- Use two spaces between status and description for separation

**Changes to `refresh()`:**
- After `collect_entries()`, loop through entries
- For each entry where `entry.description` is `nil` (not yet requested):
  - Call `description.generate(buf, callback)` to start async generation
  - The `description` module handles the API key check internally
  - If key is present, generates description and calls callback
  - If key is missing, no-op (stays nil, no loading state)
- Callback for async completion:
  ```lua
  function(result)
    vim.schedule(function()
      M.refresh()  -- Update sidebar with new description
    end)
  end
  ```
- **Module Dependency:** This creates a callback from `description.lua` → `sidebar.lua`. Acknowledged as acceptable coupling since description feature exists solely to serve the sidebar.

**Width Considerations:**
- Current default width: 20 (too narrow with descriptions)
- **Required change:** Update `DEFAULTS.width = 45` in sidebar.lua
- Format: `"  oc#0  waiting  fixing tests"` is ~35-45 chars typical
- User can still configure via `setup({ width = ... })` to override
- Description truncation at 30 chars ensures maximum line length ~50 chars

### Data Flow

1. User opens sidebar → `M.open()` → `refresh()` called
2. `collect_entries()` builds entry list:
   - For each agent instance, calls `description.get(buf)`
   - First time: returns `nil` (not in cache, not loading)
   - Stores result in `entry.description`
3. `refresh()` detects `entry.description == nil`:
   - Calls `description.generate(buf, callback)`
   - If API key present: request starts, buffer added to loading set
   - If API key absent: no-op, stays `nil`
4. Next `refresh()` (periodic, or triggered by user):
   - `description.get(buf)` now returns `"loading"` (in loading set)
   - Renders "⋯ loading..." in sidebar
5. Async request completes:
   - Success: stores description string in cache, removes from loading set
   - Rate limit (429): removes from loading set only, stays `nil` (will retry)
   - Other failure: stores `"error"` in cache, removes from loading set
   - Callback invokes `vim.schedule(sidebar.refresh)` to update UI
6. Next `refresh()`:
   - `description.get(buf)` returns actual string or `"error"` from cache
   - Renders final state in sidebar

### Concurrency & Deduplication

- Track in-flight requests using `loading` set (Lua table used as set: `loading[buf] = true`)
- In `generate(buf, callback)`:
  1. If `buf` already in `loading` set → return immediately (no-op, no callback)
  2. If API key missing → return immediately (no-op, no callback)
  3. Otherwise: add `buf` to loading set, make API request
- Remove from `loading` set when request completes (success, error, or timeout)
- Prevents duplicate API calls if `refresh()` runs multiple times before async completes
- **Edge case:** If sidebar closes while request is in-flight, the callback still fires and updates the cache. This is intentional: the description will be available immediately if the sidebar reopens before the terminal closes.

## Error Handling

### API Failures

Most API failures display `"⚠ failed"` in the description column:

- Network timeout (>10s) → `"error"` → displays `"⚠ failed"`
- Invalid API key (401/403) → `"error"` → displays `"⚠ failed"`
- HTTP errors (other 4xx, 5xx) → `"error"` → displays `"⚠ failed"`
- Malformed JSON response → `"error"` → displays `"⚠ failed"`
- Missing expected fields in response → `"error"` → displays `"⚠ failed"`

**Exception:** Rate limits (429) are treated as transient:
- Do NOT cache `"error"`
- Remove from loading set only
- Next `refresh()` will retry the request
- Rationale: Rate limits are temporary and resolve with time; permanent error state is inappropriate

### Edge Cases

**Missing API Key:**
- If `ANTHROPIC_API_KEY` not set: skip generation entirely
- Description remains empty/blank (no error indicator)
- Allows users to opt out of feature

**Buffer Lifecycle:**
- When agent terminal exits: `TermClose` autocmd calls `description.invalidate(buf)` to clear cache
- When same agent index reopens: new buffer ID, treated as new terminal, regenerates description
- Prevents stale descriptions from persisting across terminal sessions

**Sidebar Lifecycle:**
- If sidebar closes while async request is in-flight, callback still updates cache
- When sidebar reopens, cached description displays immediately (no re-generation)
- This is intentional: descriptions are static snapshots, not dynamic

**Long Descriptions:**
- LLM may return more than requested 4-5 words
- Truncate to 30 characters with "..." suffix
- Use `vim.str_utf_pos()` to respect UTF-8 character boundaries (avoids breaking multi-byte sequences)
- Ensures predictable sidebar layout

**Concurrent Requests:**
- Use `loading` set to track in-flight requests
- `generate(buf)` checks loading set and returns immediately if already in-flight
- Prevents duplicate API calls for same buffer when `refresh()` runs quickly

## Testing Strategy

### Unit Tests (Standalone Lua)

Test description module logic:
- Cache operations (get, set, invalidate)
- State transitions (nil → loading → string/error)
- `get()` returns "loading" when buffer in loading set
- `get()` returns cached value when buffer in descriptions table
- Text truncation logic (30 chars with UTF-8 safety)
- ANSI stripping
- Concurrency: calling `generate(buf)` twice before first completes → only one request
- API key guard: missing key → `generate()` is no-op

### Integration Tests (Plenary)

Test sidebar integration:
- Description rendering in sidebar (actual description string)
- Loading state display ("⋯ loading...")
- Error state display ("⚠ failed")
- Lazy generation trigger (nil → calls generate())
- Buffer cleanup on `TermClose` (description cache cleared)
- Rate limit retry behavior (429 → removes from loading, next refresh retries)
- Sidebar close during in-flight request (cache still updates, available on reopen)

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
  width = 45,  -- Default increased from 20 to accommodate descriptions
  -- ... other existing options
})
```

No new configuration options added. Feature works automatically if API key is present. Users can override width as before.

## Implementation Checklist

1. Create `lua/tw/agent/description.lua` module
   - Implement cache (`descriptions`) and loading set (`loading`)
   - Implement `get(buf)` that checks loading set first, then cache
   - Implement `generate(buf, callback)` with API key guard and deduplication
   - Implement text extraction (75 lines) and ANSI stripping
   - Implement Anthropic API integration with plenary.curl
   - Implement async completion handler (stores result, calls callback)
   - Handle rate limits specially (don't cache error, allow retry)
   - Use UTF-8-safe truncation for descriptions
   - Add `TermClose` autocmd (pattern `agent://*`) for cleanup

2. Update `lua/tw/agent/sidebar.lua`
   - Add description field to entries in `collect_entries()` via `description.get()`
   - Update `render_lines()` to include description column with loading/error states
   - Add lazy generation trigger in `refresh()` for nil descriptions
   - Pass callback to `description.generate()` that calls `vim.schedule(M.refresh)`
   - Update `DEFAULTS.width` from 20 to 45

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
