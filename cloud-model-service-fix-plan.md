# CloudModelService Fix Plan

## Current Issues Identified

1. **AppleScript Syntax Error**: String interpolation issues in AppleScript commands
2. **macOS Authorization Error**: Error -1743 when trying to run Shortcuts via AppleScript
3. **URL Scheme Reliability**: Need to improve URL scheme approach for running shortcuts

## Proposed Solution

### Phase 1: Fix AppleScript Syntax
- [ ] Fix string interpolation in AppleScript commands
- [ ] Add proper text escaping for special characters
- [ ] Test AppleScript execution

### Phase 2: Handle Authorization Issues
- [ ] Implement URL scheme fallback for macOS
- [ ] Add proper error handling for authorization errors
- [ ] Provide user-friendly error messages

### Phase 3: Improve URL Scheme Approach
- [ ] Use x-callback-url for better integration
- [ ] Add timeout handling
- [ ] Implement clipboard monitoring for results

### Phase 4: Testing & Validation
- [ ] Test on macOS with different authorization states
- [ ] Test on iOS devices
- [ ] Verify error handling works correctly

## Technical Details

### AppleScript Fix
The current AppleScript has syntax issues with string interpolation. Need to properly escape quotes and handle special characters.

### URL Scheme Implementation
For macOS, we'll use:
```
shortcuts://run-shortcut?name=RSS%20Reader%20Cloud%20Summary&input=text&text=[encoded_text]
```

For iOS, we'll use x-callback-url:
```
shortcuts://x-callback-url/run-shortcut?name=RSS%20Reader%20Cloud%20Summary&input=text&text=[encoded_text]&x-success=webbrowser://success&x-error=webbrowser://error
```

### Error Handling
- Add proper timeout handling (2 minutes)
- Add clipboard monitoring for results
- Provide clear error messages to users

## Implementation Steps

1. **Fix AppleScript string interpolation** (lines 80-120)
2. **Add URL scheme fallback** (lines 45-75)
3. **Improve error handling** (lines 315-330)
4. **Add timeout mechanism** (lines 150-180)
5. **Test clipboard monitoring** (lines 200-250)

## Testing Checklist

- [ ] Test with simple text input
- [ ] Test with special characters in text
- [ ] Test with long text input
- [ ] Test authorization denied scenario
- [ ] Test shortcuts app not installed
- [ ] Test network timeout scenarios