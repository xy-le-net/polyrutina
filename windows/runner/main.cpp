#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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

  constexpr double kWindowAspectWidth = 9.0;
  constexpr double kWindowAspectHeight = 16.0;
  constexpr double kMaxWindowWidth = Win32Window::kMaxWindowWidth;
  const HMONITOR monitor =
      MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return EXIT_FAILURE;
  }

  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = (dpi == 0 ? 96 : dpi) / 96.0;
  const double work_width =
      (monitor_info.rcWork.right - monitor_info.rcWork.left) / scale;
  const double work_height =
      (monitor_info.rcWork.bottom - monitor_info.rcWork.top) / scale;
  const double height = std::min(
      {work_height, work_width * kWindowAspectHeight / kWindowAspectWidth,
       kMaxWindowWidth * kWindowAspectHeight / kWindowAspectWidth});
  const double width = height * kWindowAspectWidth / kWindowAspectHeight;
  const int left = static_cast<int>(
      (monitor_info.rcWork.left / scale) + (work_width - width) / 2);
  const int top = static_cast<int>(
      (monitor_info.rcWork.top / scale) + (work_height - height) / 2);
  Win32Window::Point origin(left, top);
  Win32Window::Size size(static_cast<unsigned int>(width),
                         static_cast<unsigned int>(height));
  if (!window.Create(L"polyrutina", origin, size)) {
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
