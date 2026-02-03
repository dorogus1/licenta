#pragma once
#include <string>
#include <windows.h>

// Return base64-encoded PNG bytes for the icon at `path` (may be an .exe/.ico path).
// Returns empty string on failure.
std::string ExtractIconAsPngBase64(const std::string& iconPath);
