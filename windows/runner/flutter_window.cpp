#include "flutter_window.h"
#include "resource.h"

#include <optional>
#include <shellapi.h>
#include <uxtheme.h>
#include <vssym32.h>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/encodable_value.h>
#include <flutter/standard_message_codec.h>
#include <dwmapi.h>
#include <psapi.h>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <gdiplus.h>
#include <vector>
#include <fstream>
#include <string>
#include <winrt/base.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;

using namespace Gdiplus;

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "gdiplus.lib")

#define WM_TRAYICON (WM_USER + 1)
#define ID_TRAYICON 1001

static FlutterWindow* g_flutter_window = nullptr;
bool g_isDark = false;

#pragma pack(push, 2)
typedef struct {
    BYTE bWidth;
    BYTE bHeight;
    BYTE bColorCount;
    BYTE bReserved;
    WORD wPlanes;
    WORD wBitCount;
    DWORD dwBytesInRes;
    WORD nID;
} GRPICONDIRENTRY, * LPGRPICONDIRENTRY;

typedef struct {
    WORD idReserved;
    WORD idType;
    WORD idCount;
    GRPICONDIRENTRY idEntries[1];
} GRPICONDIR, * LPGRPICONDIR;
#pragma pack(pop)

#include "notification_manager.h"

extern "C" __declspec(dllexport)
bool ShowWindowsNotification(
        const wchar_t* title,
        const wchar_t* body) {
    if (!title || !body) {
        return false;
    }

    return NotificationManager::Show(title, body);
}

static int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
    UINT num = 0, size = 0;
    GetImageEncodersSize(&num, &size);
    if (size == 0) return -1;
    ImageCodecInfo* pImageCodecInfo = (ImageCodecInfo*)(malloc(size));
    if (pImageCodecInfo == NULL) return -1;
    GetImageEncoders(num, size, pImageCodecInfo);
    for (UINT j = 0; j < num; ++j) {
        if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
            *pClsid = pImageCodecInfo[j].Clsid;
            free(pImageCodecInfo);
            return j;
        }
    }
    free(pImageCodecInfo);
    return -1;
}

static bool SaveIconToPng(BYTE* pData, DWORD dwSize, const wchar_t* savePath) {
    if (dwSize > 8 && pData[0] == 0x89 && pData[1] == 'P' && pData[2] == 'N' && pData[3] == 'G') {
        std::ofstream file(savePath, std::ios::binary);
        if (!file.is_open()) return false;
        file.write((char*)pData, dwSize);
        return true;
    }

    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

    bool success = false;
    {
        HICON hIcon = CreateIconFromResourceEx(pData, dwSize, TRUE, 0x00030000, 0, 0, LR_DEFAULTCOLOR);
        if (hIcon) {
            Bitmap* bitmap = new Bitmap(hIcon);
            if (bitmap && bitmap->GetLastStatus() == Ok) {
                CLSID pngClsid;
                if (GetEncoderClsid(L"image/png", &pngClsid) != -1) {
                    Status s = bitmap->Save(savePath, &pngClsid, NULL);
                    success = (s == Ok);
                }
            }
            delete bitmap;
            DestroyIcon(hIcon);
        }
    }

    GdiplusShutdown(gdiplusToken);
    return success;
}

struct EnumParam {
    const wchar_t* savePath;
    bool found;
};

static BOOL CALLBACK EnumResNameCallback(HMODULE hModule, LPCWSTR lpszType, LPWSTR lpszName, LONG_PTR lParam) {
    EnumParam* param = (EnumParam*)lParam;
    HRSRC hResGroup = FindResourceW(hModule, lpszName, RT_GROUP_ICON);
    if (!hResGroup) return TRUE;

    HGLOBAL hResData = LoadResource(hModule, hResGroup);
    LPGRPICONDIR pIconDir = (LPGRPICONDIR)LockResource(hResData);
    if (!pIconDir) return TRUE;

    int bestIndex = -1;
    int maxQuality = -1;

    for (int i = 0; i < pIconDir->idCount; i++) {
        GRPICONDIRENTRY& entry = pIconDir->idEntries[i];
        int width = entry.bWidth == 0 ? 256 : entry.bWidth;
        int bitCount = entry.wBitCount;
        int quality = width * 1000 + bitCount;
        if (quality > maxQuality) {
            maxQuality = quality;
            bestIndex = i;
        }
    }

    if (bestIndex != -1) {
        WORD nID = pIconDir->idEntries[bestIndex].nID;
        HRSRC hResIcon = FindResourceW(hModule, MAKEINTRESOURCEW(nID), RT_ICON);
        if (hResIcon) {
            DWORD dwSize = SizeofResource(hModule, hResIcon);
            HGLOBAL hData = LoadResource(hModule, hResIcon);
            BYTE* pBytes = (BYTE*)LockResource(hData);
            if (pBytes) {
                param->found = SaveIconToPng(pBytes, dwSize, param->savePath);
            }
        }
    }
    return !param->found;
}

extern "C" __declspec(dllexport) int ExtractHighResIcon(const wchar_t* exePath, const wchar_t* savePath) {
    HMODULE hModule = LoadLibraryExW(exePath, NULL, LOAD_LIBRARY_AS_DATAFILE);
    if (!hModule) return 1;
    EnumParam param = { savePath, false };
    EnumResourceNamesW(hModule, RT_GROUP_ICON, EnumResNameCallback, (LONG_PTR)&param);
    FreeLibrary(hModule);
    return param.found ? 0 : 2;
}

extern "C" __declspec(dllexport) void SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (g_flutter_window) g_flutter_window->SetTaskbarProgress(completed, total);
}

extern "C" __declspec(dllexport) void SetTaskbarState(int state) {
  if (g_flutter_window) g_flutter_window->SetTaskbarState(static_cast<TBPFLAG>(state));
}

extern "C" __declspec(dllexport) void SetTrayTheme(bool is_dark) {
  if (g_flutter_window) SetWindowTheme(g_flutter_window->GetHandle(), is_dark ? L"DarkMode_Explorer" : L"Explorer", NULL);
}

typedef enum {
    BDefault = 0,
    AllowDark = 1,
    ForceDark = 2,
    ForceLight = 3
} PreferredAppMode;


void SetWinMenuTheme(bool dark)
{
  HMODULE hUxTheme = LoadLibraryW(L"uxtheme.dll");

  if (!hUxTheme)
    return;

  using SetPreferredAppModeFunc = PreferredAppMode(WINAPI*)(PreferredAppMode);

  auto func = (SetPreferredAppModeFunc)GetProcAddress(
          hUxTheme,
          MAKEINTRESOURCEA(135)
  );

  if (func)
  {
    func(dark ? ForceDark : ForceLight);
  }

  FreeLibrary(hUxTheme);
}

extern "C" __declspec(dllexport) void ShowTrayMenu(bool is_dark) {
  SetWinMenuTheme(is_dark);
  HMENU hMenu = CreatePopupMenu();
  AppendMenu(hMenu, MF_STRING, 1, L"访问 BBBS");
  AppendMenu(hMenu, MF_STRING, 2, L"访问 Bloret Passport");
  AppendMenu(hMenu, MF_STRING, 3, L"访问 百络图床");
  AppendMenu(hMenu, MF_SEPARATOR, 0, NULL);
  if (g_flutter_window && ::IsWindowVisible(g_flutter_window->GetHandle())) {
    AppendMenu(hMenu, MF_STRING, 4, L"隐藏窗口");
  } else {
    AppendMenu(hMenu, MF_STRING, 4, L"显示窗口");
  }
  AppendMenu(hMenu, MF_STRING, 5, L"退出程序");

  POINT pt;
  GetCursorPos(&pt);
  HWND hwnd = g_flutter_window->GetHandle();
  SetForegroundWindow(hwnd);
  TrackPopupMenu(hMenu, TPM_RIGHTALIGN | TPM_BOTTOMALIGN, pt.x, pt.y, 0, g_flutter_window->GetHandle(), NULL);
  DestroyMenu(hMenu);
}

extern "C" __declspec(dllexport) void c_terminate_process() {
  TerminateProcess(GetCurrentProcess(), 0);
}

typedef LONG (NTAPI *pNtSuspendProcess)(HANDLE ProcessHandle);
typedef LONG (NTAPI *pNtResumeProcess)(HANDLE ProcessHandle);

extern "C" __declspec(dllexport) void SuspendProcess(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
  if (hProcess) {
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (hNtdll) {
      auto NtSuspendProcess = (pNtSuspendProcess)GetProcAddress(hNtdll, "NtSuspendProcess");
      if (NtSuspendProcess) NtSuspendProcess(hProcess);
    }
    CloseHandle(hProcess);
  }
}

extern "C" __declspec(dllexport) void ResumeProcess(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
  if (hProcess) {
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (hNtdll) {
      auto NtResumeProcess = (pNtResumeProcess)GetProcAddress(hNtdll, "NtResumeProcess");
      if (NtResumeProcess) NtResumeProcess(hProcess);
    }
    CloseHandle(hProcess);
  }
}

extern "C" __declspec(dllexport) void SetEfficiencyMode(uint32_t pid, bool enable) {
  HANDLE hProcess = OpenProcess(PROCESS_SET_INFORMATION, FALSE, pid);
  if (hProcess) {
    PROCESS_POWER_THROTTLING_STATE powerThrottling = {0};
    powerThrottling.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
    powerThrottling.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED;
    powerThrottling.StateMask = enable ? PROCESS_POWER_THROTTLING_EXECUTION_SPEED : 0;

    SetProcessInformation(hProcess, ProcessPowerThrottling, &powerThrottling, sizeof(powerThrottling));
    SetPriorityClass(hProcess, enable ? IDLE_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS);

    CloseHandle(hProcess);
  }
}

extern "C" __declspec(dllexport) void CleanProcessRAM(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA, FALSE, pid);
  if (hProcess) {
    EmptyWorkingSet(hProcess);
    CloseHandle(hProcess);
  }
}

extern "C" __declspec(dllexport) uint64_t GetProcessMemoryUsage(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
  if (hProcess) {
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(hProcess, &pmc, sizeof(pmc))) {
      CloseHandle(hProcess);
      return pmc.WorkingSetSize;
    }
    CloseHandle(hProcess);
  }
  return 0;
}

extern "C" __declspec(dllexport) uint64_t GetProcessCpuTime(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);
  if (hProcess) {
    FILETIME ftCreation, ftExit, ftKernel, ftUser;
    if (GetProcessTimes(hProcess, &ftCreation, &ftExit, &ftKernel, &ftUser)) {
      CloseHandle(hProcess);
      ULARGE_INTEGER kernel, user;
      kernel.LowPart = ftKernel.dwLowDateTime;
      kernel.HighPart = ftKernel.dwHighDateTime;
      user.LowPart = ftUser.dwLowDateTime;
      user.HighPart = ftUser.dwHighDateTime;
      return kernel.QuadPart + user.QuadPart;
    }
    CloseHandle(hProcess);
  }
  return 0;
}

extern "C" __declspec(dllexport) int GetCpuCoreCount() {
  SYSTEM_INFO sysInfo;
  GetSystemInfo(&sysInfo);
  return sysInfo.dwNumberOfProcessors;
}

extern "C" __declspec(dllexport) bool IsProcessAlive(uint32_t pid) {
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (hProcess == NULL) return false;

  DWORD exitCode = 0;
  if (GetExitCodeProcess(hProcess, &exitCode)) {
    CloseHandle(hProcess);
    return exitCode == STILL_ACTIVE;
  }

  CloseHandle(hProcess);
  return false;
}

extern "C" __declspec(dllexport) void DestroyApp() { c_terminate_process(); }
extern "C" __declspec(dllexport) void HideApp() { if (g_flutter_window) g_flutter_window->Hide(); }

static struct {
    WINDOWPLACEMENT placement = { sizeof(WINDOWPLACEMENT) };
    DWORD style = 0;
} g_prev_window_state;
static bool g_is_fullscreen = false;

extern "C" __declspec(dllexport)
void SetFullscreen(bool fullscreen) {
    if (!g_flutter_window) return;
    HWND hwnd = g_flutter_window->GetHandle();
    if (fullscreen == g_is_fullscreen) return;

    if (fullscreen) {
        g_prev_window_state.style = GetWindowLong(hwnd, GWL_STYLE);
        GetWindowPlacement(hwnd, &g_prev_window_state.placement);

        MONITORINFO mi = { sizeof(mi) };
        if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &mi)) {
            SetWindowLong(hwnd, GWL_STYLE, g_prev_window_state.style & ~WS_OVERLAPPEDWINDOW);
            SetWindowPos(hwnd, HWND_TOP,
                mi.rcMonitor.left, mi.rcMonitor.top,
                mi.rcMonitor.right - mi.rcMonitor.left,
                mi.rcMonitor.bottom - mi.rcMonitor.top,
                SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        }
        g_is_fullscreen = true;
    } else {
        SetWindowLong(hwnd, GWL_STYLE, g_prev_window_state.style);
        SetWindowPlacement(hwnd, &g_prev_window_state.placement);
        SetWindowPos(hwnd, NULL, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
            SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        g_is_fullscreen = false;
    }
}

extern "C" __declspec(dllexport)
void SetAcrylic(bool enabled) {
  if (g_flutter_window) {
    g_flutter_window->SetAcrylic(enabled);
  }
}

extern "C" __declspec(dllexport)
void SetDarkMode(HWND hwnd, bool dark)
{
  BOOL value = dark ? TRUE : FALSE;
  g_isDark = dark;
  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &value, sizeof(value));
  SetWinMenuTheme(dark);
}

extern "C" __declspec(dllexport)
void SetIconTheme(bool dark)
{
  if (!g_flutter_window) return;
  HWND hwnd = g_flutter_window->GetHandle();

  SetDarkMode(hwnd, dark);

  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  std::wstring path(exePath);
  auto pos = path.find_last_of(L"\\/");
  if (pos != std::wstring::npos) path = path.substr(0, pos + 1);

  path += L"data\\flutter_assets\\assets\\";
  path += dark ? L"bloret_dark.ico" : L"bloret_light.ico";

  HICON hIcon = (HICON)LoadImageW(nullptr, path.c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
  if (!hIcon) return;

  SendMessageW(hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
  SendMessageW(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);

  SetWindowPos(hwnd, nullptr, 0,0,0,0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(NOTIFYICONDATA);
  nid.hWnd = g_flutter_window->GetHandle();
  nid.uID = ID_TRAYICON;
  nid.uFlags = NIF_ICON;
  nid.hIcon = hIcon;
  Shell_NotifyIcon(NIM_MODIFY, &nid);
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {
  g_flutter_window = this;
}

FlutterWindow::~FlutterWindow() {
  g_flutter_window = nullptr;
  if (taskbar_list_) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
}

void FlutterWindow::SetupTrayIcon() {
  NOTIFYICONDATA nid = { sizeof(NOTIFYICONDATA) };
  nid.hWnd = GetHandle();
  nid.uID = ID_TRAYICON;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = WM_TRAYICON;
  nid.hIcon = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(nid.szTip, L"Blora Launcher");
  Shell_NotifyIcon(NIM_ADD, &nid);
}

void FlutterWindow::Show() {
  ::ShowWindow(GetHandle(), SW_SHOW);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::Hide() {
  ::ShowWindow(GetHandle(), SW_HIDE);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_list_));

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;

  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (taskbar_list_) taskbar_list_->SetProgressValue(GetHandle(), completed, total);
}

void FlutterWindow::SetTaskbarState(TBPFLAG state) {
  if (taskbar_list_) taskbar_list_->SetProgressState(GetHandle(), state);
}

void FlutterWindow::OnDestroy() {
  NOTIFYICONDATA nid = { sizeof(NOTIFYICONDATA) };
  nid.hWnd = GetHandle();
  nid.uID = ID_TRAYICON;
  Shell_NotifyIcon(NIM_DELETE, &nid);

  if (flutter_controller_) flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COMMAND:
      switch(wparam) {
        case 1: {
          flutter::EncodableValue val("bbbs");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 2: {
          flutter::EncodableValue val("passport");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 3: {
          flutter::EncodableValue val("img_host");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 4:
          if (::IsWindowVisible(hwnd)) Hide(); else Show();
          break;
        case 5: {
          std::string msg = "on_quit";
          flutter_controller_->engine()->messenger()->Send(
              "bloret/window_event",
              reinterpret_cast<const uint8_t*>(msg.c_str()),
              msg.size(),
              nullptr);
          break;
        }
      }
      break;
    case WM_TRAYICON:
      if (lparam == WM_LBUTTONUP) {
        if (::IsWindowVisible(hwnd)) Hide(); else Show();
      } else if (lparam == WM_RBUTTONUP) {
        ShowTrayMenu(g_isDark);
      }
      break;
    case WM_CLOSE: {
      std::string msg = "on_close";
      flutter_controller_->engine()->messenger()->Send(
          "bloret/window_event",
          reinterpret_cast<const uint8_t*>(msg.c_str()),
          msg.size(),
          nullptr);
      return 0;
    }
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
