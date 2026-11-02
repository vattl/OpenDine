#include "crash_handler.h"

#include <windows.h>
#include <DbgHelp.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kAppDirectoryName[] = L"LaofeiCashier";
constexpr wchar_t kLogsDirectoryName[] = L"logs";
constexpr wchar_t kPendingCrashFileName[] = L"pending_native_crash.json";
constexpr wchar_t kSessionStateFileName[] = L"session_state.json";
constexpr size_t kRetainedDumpCount = 5;
constexpr size_t kNativeUiEventCount = 48;
constexpr UINT kAccessibilityGuardStateMessage = WM_APP + 0x4C1;

LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
volatile LONG g_handling_crash = 0;
volatile LONG g_accessibility_guard_active = 0;
volatile LONG64 g_native_ui_sequence = 0;

struct NativeUiEvent {
  volatile LONG64 sequence = 0;
  ULONGLONG tick_count_ms = 0;
  DWORD thread_id = 0;
  UINT message = 0;
  uintptr_t window = 0;
  uintptr_t wparam = 0;
  intptr_t lparam = 0;
  char phase[40] = {};
};

NativeUiEvent g_native_ui_events[kNativeUiEventCount] = {};

bool ShouldRecordWindowMessage(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_ACTIVATE:
    case WM_SETFOCUS:
    case WM_KILLFOCUS:
    case WM_GETOBJECT:
    case WM_SIZE:
    case WM_SHOWWINDOW:
    case WM_ENABLE:
    case WM_WINDOWPOSCHANGING:
    case WM_WINDOWPOSCHANGED:
    case WM_CLIPBOARDUPDATE:
    case WM_PASTE:
      return true;
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
      return wparam == 'V' || wparam == VK_CONTROL || wparam == VK_SHIFT ||
             wparam == VK_INSERT;
    default:
      return message == kAccessibilityGuardStateMessage;
  }
}

const char* WindowMessageName(UINT message) {
  switch (message) {
    case WM_ACTIVATE:
      return "WM_ACTIVATE";
    case WM_SETFOCUS:
      return "WM_SETFOCUS";
    case WM_KILLFOCUS:
      return "WM_KILLFOCUS";
    case WM_GETOBJECT:
      return "WM_GETOBJECT";
    case WM_SIZE:
      return "WM_SIZE";
    case WM_SHOWWINDOW:
      return "WM_SHOWWINDOW";
    case WM_ENABLE:
      return "WM_ENABLE";
    case WM_WINDOWPOSCHANGING:
      return "WM_WINDOWPOSCHANGING";
    case WM_WINDOWPOSCHANGED:
      return "WM_WINDOWPOSCHANGED";
    case WM_CLIPBOARDUPDATE:
      return "WM_CLIPBOARDUPDATE";
    case WM_PASTE:
      return "WM_PASTE";
    case WM_KEYDOWN:
      return "WM_KEYDOWN";
    case WM_KEYUP:
      return "WM_KEYUP";
    case WM_SYSKEYDOWN:
      return "WM_SYSKEYDOWN";
    case WM_SYSKEYUP:
      return "WM_SYSKEYUP";
    default:
      return message == kAccessibilityGuardStateMessage
                 ? "ACCESSIBILITY_GUARD_STATE"
                 : "UNKNOWN";
  }
}

void StoreNativeUiEvent(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam, const char* phase) noexcept {
  if (!ShouldRecordWindowMessage(message, wparam)) {
    return;
  }
  const LONG64 sequence = ::InterlockedIncrement64(&g_native_ui_sequence);
  NativeUiEvent& slot =
      g_native_ui_events[static_cast<size_t>(sequence) % kNativeUiEventCount];
  ::InterlockedExchange64(&slot.sequence, 0);
  slot.tick_count_ms = ::GetTickCount64();
  slot.thread_id = ::GetCurrentThreadId();
  slot.message = message;
  slot.window = reinterpret_cast<uintptr_t>(window);
  slot.wparam = static_cast<uintptr_t>(wparam);
  slot.lparam = static_cast<intptr_t>(lparam);
  strncpy_s(slot.phase, phase != nullptr ? phase : "unknown", _TRUNCATE);
  ::MemoryBarrier();
  ::InterlockedExchange64(&slot.sequence, sequence);
}

std::wstring JoinPath(const std::wstring& left, const std::wstring& right) {
  if (left.empty()) {
    return right;
  }
  if (left.back() == L'\\') {
    return left + right;
  }
  return left + L"\\" + right;
}

std::wstring GetLogsDirectory() {
  std::vector<wchar_t> buffer(32768);
  DWORD length = ::GetEnvironmentVariableW(
      L"LOCALAPPDATA", buffer.data(), static_cast<DWORD>(buffer.size()));
  std::wstring root;
  if (length > 0 && length < buffer.size()) {
    root.assign(buffer.data(), length);
  } else {
    length = ::GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
    if (length > 0 && length < buffer.size()) {
      root.assign(buffer.data(), length);
    }
  }
  if (root.empty()) {
    return {};
  }

  const std::wstring app_directory = JoinPath(root, kAppDirectoryName);
  ::CreateDirectoryW(app_directory.c_str(), nullptr);
  const std::wstring logs_directory =
      JoinPath(app_directory, kLogsDirectoryName);
  ::CreateDirectoryW(logs_directory.c_str(), nullptr);
  return logs_directory;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int length = ::WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (length <= 0) {
    return {};
  }
  std::string result(static_cast<size_t>(length), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), length,
                        nullptr, nullptr);
  return result;
}

std::string EscapeJson(const std::string& value) {
  std::string result;
  result.reserve(value.size() + 16);
  for (const unsigned char character : value) {
    switch (character) {
      case '\\':
        result += "\\\\";
        break;
      case '"':
        result += "\\\"";
        break;
      case '\n':
        result += "\\n";
        break;
      case '\r':
        result += "\\r";
        break;
      case '\t':
        result += "\\t";
        break;
      default:
        if (character < 0x20) {
          char escaped[7] = {};
          sprintf_s(escaped, "\\u%04x", character);
          result += escaped;
        } else {
          result.push_back(static_cast<char>(character));
        }
    }
  }
  return result;
}

std::wstring TimestampForFileName(const SYSTEMTIME& time) {
  wchar_t value[32] = {};
  swprintf_s(value, L"%04u%02u%02u_%02u%02u%02u_%03u", time.wYear,
             time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
             time.wMilliseconds);
  return value;
}

std::string TimestampForJson(const SYSTEMTIME& time) {
  char value[40] = {};
  sprintf_s(value, "%04u-%02u-%02uT%02u:%02u:%02u.%03u", time.wYear,
            time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
            time.wMilliseconds);
  return value;
}

void WriteUtf8File(const std::wstring& path, const std::string& content) {
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                              nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  ::WriteFile(file, content.data(), static_cast<DWORD>(content.size()),
              &written, nullptr);
  ::FlushFileBuffers(file);
  ::CloseHandle(file);
}

void RetainNewestDumps(const std::wstring& logs_directory) {
  struct DumpEntry {
    std::wstring path;
    FILETIME modified;
  };
  std::vector<DumpEntry> dumps;
  WIN32_FIND_DATAW data = {};
  const std::wstring pattern = JoinPath(logs_directory, L"native_crash_*.dmp");
  HANDLE search = ::FindFirstFileW(pattern.c_str(), &data);
  if (search == INVALID_HANDLE_VALUE) {
    return;
  }
  do {
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      dumps.push_back(
          {JoinPath(logs_directory, data.cFileName), data.ftLastWriteTime});
    }
  } while (::FindNextFileW(search, &data));
  ::FindClose(search);

  std::sort(dumps.begin(), dumps.end(), [](const DumpEntry& left,
                                           const DumpEntry& right) {
    return ::CompareFileTime(&left.modified, &right.modified) < 0;
  });
  while (dumps.size() > kRetainedDumpCount) {
    ::DeleteFileW(dumps.front().path.c_str());
    dumps.erase(dumps.begin());
  }
}

bool WriteMiniDump(const std::wstring& dump_path,
                   EXCEPTION_POINTERS* exception) {
  HMODULE dbghelp = ::LoadLibraryW(L"dbghelp.dll");
  if (dbghelp == nullptr) {
    return false;
  }
  using MiniDumpWriteDumpFunction = decltype(&::MiniDumpWriteDump);
  const auto write_dump = reinterpret_cast<MiniDumpWriteDumpFunction>(
      ::GetProcAddress(dbghelp, "MiniDumpWriteDump"));
  if (write_dump == nullptr) {
    ::FreeLibrary(dbghelp);
    return false;
  }

  HANDLE file = ::CreateFileW(dump_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                              nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    ::FreeLibrary(dbghelp);
    return false;
  }
  MINIDUMP_EXCEPTION_INFORMATION exception_information = {};
  exception_information.ThreadId = ::GetCurrentThreadId();
  exception_information.ExceptionPointers = exception;
  exception_information.ClientPointers = FALSE;
  const MINIDUMP_TYPE dump_type = static_cast<MINIDUMP_TYPE>(
      MiniDumpNormal | MiniDumpWithThreadInfo |
      MiniDumpWithIndirectlyReferencedMemory | MiniDumpWithUnloadedModules |
      MiniDumpWithProcessThreadData | MiniDumpWithFullMemoryInfo);
  const BOOL succeeded = write_dump(
      ::GetCurrentProcess(), ::GetCurrentProcessId(), file, dump_type,
      &exception_information, nullptr, nullptr);
  ::FlushFileBuffers(file);
  ::CloseHandle(file);
  ::FreeLibrary(dbghelp);
  if (!succeeded) {
    ::DeleteFileW(dump_path.c_str());
  }
  return succeeded == TRUE;
}

void AppendExceptionDiagnostics(std::string& json,
                                EXCEPTION_POINTERS* exception) {
  if (exception == nullptr || exception->ExceptionRecord == nullptr) {
    return;
  }
  const EXCEPTION_RECORD* record = exception->ExceptionRecord;
  if ((record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION ||
       record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) &&
      record->NumberParameters >= 2) {
    const ULONG_PTR operation = record->ExceptionInformation[0];
    const char* operation_name =
        operation == 0 ? "read" : (operation == 1 ? "write" : "execute");
    char target[32] = {};
    sprintf_s(target, "0x%p",
              reinterpret_cast<void*>(record->ExceptionInformation[1]));
    json += "  \"access_operation\": \"" +
            std::string(operation_name) + "\",\n";
    json += "  \"access_target\": \"" + std::string(target) + "\",\n";
  }

  HMODULE module = nullptr;
  const auto exception_address = record->ExceptionAddress;
  if (::GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(exception_address), &module) != FALSE &&
      module != nullptr) {
    wchar_t module_path[MAX_PATH] = {};
    ::GetModuleFileNameW(module, module_path, MAX_PATH);
    const uintptr_t module_offset =
        reinterpret_cast<uintptr_t>(exception_address) -
        reinterpret_cast<uintptr_t>(module);
    char offset[32] = {};
    sprintf_s(offset, "0x%llX",
              static_cast<unsigned long long>(module_offset));
    json += "  \"fault_module\": \"" +
            EscapeJson(WideToUtf8(module_path)) + "\",\n";
    json += "  \"fault_module_offset\": \"" + std::string(offset) +
            "\",\n";
  }
}

void AppendNativeUiDiagnostics(std::string& json) {
  json += std::string("  \"accessibility_guard_active\": ") +
          (::InterlockedCompareExchange(&g_accessibility_guard_active, 0, 0)
               ? "true"
               : "false") +
          ",\n";
  json += "  \"window_messages\": [\n";
  const LONG64 newest =
      ::InterlockedCompareExchange64(&g_native_ui_sequence, 0, 0);
  const LONG64 first =
      std::max<LONG64>(1, newest - static_cast<LONG64>(kNativeUiEventCount) + 1);
  bool wrote_event = false;
  for (LONG64 sequence = first; sequence <= newest; ++sequence) {
    const NativeUiEvent& event = g_native_ui_events[
        static_cast<size_t>(sequence) % kNativeUiEventCount];
    if (::InterlockedCompareExchange64(
            const_cast<volatile LONG64*>(&event.sequence), 0, 0) != sequence) {
      continue;
    }
    char window[32] = {};
    char wparam[32] = {};
    char lparam[32] = {};
    sprintf_s(window, "0x%llX",
              static_cast<unsigned long long>(event.window));
    sprintf_s(wparam, "0x%llX",
              static_cast<unsigned long long>(event.wparam));
    sprintf_s(lparam, "0x%llX",
              static_cast<unsigned long long>(event.lparam));
    if (wrote_event) {
      json += ",\n";
    }
    wrote_event = true;
    json += "    {\"sequence\": " + std::to_string(sequence) +
            ", \"tick_ms\": " + std::to_string(event.tick_count_ms) +
            ", \"thread_id\": " + std::to_string(event.thread_id) +
            ", \"message\": " + std::to_string(event.message) +
            ", \"message_name\": \"" + WindowMessageName(event.message) +
            "\", \"phase\": \"" + EscapeJson(event.phase) +
            "\", \"window\": \"" + window + "\", \"wparam\": \"" +
            wparam + "\", \"lparam\": \"" + lparam + "\"}";
  }
  json += "\n  ],\n";
}

LONG WINAPI HandleUnhandledException(EXCEPTION_POINTERS* exception) {
  if (::InterlockedCompareExchange(&g_handling_crash, 1, 0) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  const std::wstring logs_directory = GetLogsDirectory();
  if (!logs_directory.empty()) {
    SYSTEMTIME time = {};
    ::GetLocalTime(&time);
    const DWORD process_id = ::GetCurrentProcessId();
    const std::wstring dump_name = L"native_crash_" +
                                   TimestampForFileName(time) + L"_" +
                                   std::to_wstring(process_id) + L".dmp";
    const std::wstring dump_path = JoinPath(logs_directory, dump_name);
    const bool dump_written = WriteMiniDump(dump_path, exception);

    const DWORD exception_code =
        exception != nullptr && exception->ExceptionRecord != nullptr
            ? exception->ExceptionRecord->ExceptionCode
            : 0;
    const uintptr_t exception_address =
        exception != nullptr && exception->ExceptionRecord != nullptr
            ? reinterpret_cast<uintptr_t>(
                  exception->ExceptionRecord->ExceptionAddress)
            : 0;
    char code[16] = {};
    char address[32] = {};
    sprintf_s(code, "0x%08lX", exception_code);
    sprintf_s(address, "0x%p", reinterpret_cast<void*>(exception_address));

    std::string json = "{\n";
    json += "  \"captured_at\": \"" + TimestampForJson(time) + "\",\n";
    json += "  \"exception_code\": \"" + std::string(code) + "\",\n";
    json += "  \"exception_address\": \"" + std::string(address) + "\",\n";
    json += "  \"process_id\": " + std::to_string(process_id) + ",\n";
    json += "  \"thread_id\": " + std::to_string(::GetCurrentThreadId()) + ",\n";
    AppendExceptionDiagnostics(json, exception);
    AppendNativeUiDiagnostics(json);
    json += std::string("  \"minidump_written\": ") +
            (dump_written ? "true" : "false") + ",\n";
    if (dump_written) {
      json += "  \"minidump_path\": \"" +
              EscapeJson(WideToUtf8(dump_path)) + "\"\n";
    } else {
      json += "  \"minidump_path\": null\n";
    }
    json += "}\n";
    WriteUtf8File(JoinPath(logs_directory, kPendingCrashFileName), json);
    RetainNewestDumps(logs_directory);
  }

  if (g_previous_filter != nullptr) {
    return g_previous_filter(exception);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void InstallNativeCrashHandler() {
  GetLogsDirectory();
  const LPTOP_LEVEL_EXCEPTION_FILTER previous =
      ::SetUnhandledExceptionFilter(HandleUnhandledException);
  if (previous != nullptr && previous != HandleUnhandledException) {
    g_previous_filter = previous;
  }
}

void MarkNativeProcessCleanExit() {
  const std::wstring logs_directory = GetLogsDirectory();
  if (!logs_directory.empty()) {
    ::DeleteFileW(
        JoinPath(logs_directory, kSessionStateFileName).c_str());
  }
}

void RecordNativeWindowMessage(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam, const char* phase) noexcept {
  StoreNativeUiEvent(window, message, wparam, lparam, phase);
}

void SetNativeAccessibilityGuardState(bool enabled,
                                      const char* reason) noexcept {
  ::InterlockedExchange(&g_accessibility_guard_active, enabled ? 1 : 0);
  StoreNativeUiEvent(nullptr, kAccessibilityGuardStateMessage,
                     enabled ? 1 : 0, 0, reason);
}
