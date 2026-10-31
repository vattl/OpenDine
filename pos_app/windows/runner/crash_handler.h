#pragma once

#include <windows.h>

// Installs a last-resort Windows SEH handler that writes a minidump and a
// small JSON handoff file for the Dart crash reporter to import on next start.
void InstallNativeCrashHandler();

// Clears Dart's running-session marker after a normal Windows message-loop exit.
void MarkNativeProcessCleanExit();

// Records a bounded, content-free trace of high-risk Windows UI messages.
// The trace is kept in memory and copied into the next native crash report.
void RecordNativeWindowMessage(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam, const char* phase) noexcept;

// Records whether the receipt-template accessibility workaround is active.
void SetNativeAccessibilityGuardState(bool enabled,
                                      const char* reason) noexcept;
