#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// KDS is an always-on kitchen display: it must keep receiving WS pushes and
// sending heartbeats even when the window is unfocused, occluded, or
// minimized. Windows 11 EcoQoS ("efficiency mode") and timer throttling can
// stall timers and network callbacks of unfocused processes, which shows up
// as "board stops refreshing until the window is clicked".
// Opt the process out of both throttling classes at startup (Win8+).
void DisableProcessPowerThrottling() {
  PROCESS_POWER_THROTTLING_STATE throttling = {};
  throttling.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;

  // Opt out of EcoQoS execution-speed throttling.
  throttling.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED;
  throttling.StateMask = 0;
  ::SetProcessInformation(::GetCurrentProcess(), ProcessPowerThrottling,
                          &throttling, sizeof(throttling));

  // Opt out of timer-resolution throttling so the 15s WS ping / 60s
  // heartbeat timers fire on schedule.
  throttling.ControlMask = PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
  throttling.StateMask = 0;
  ::SetProcessInformation(::GetCurrentProcess(), ProcessPowerThrottling,
                          &throttling, sizeof(throttling));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  DisableProcessPowerThrottling();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"kds_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
