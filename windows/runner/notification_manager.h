#pragma once

#include <string>

class NotificationManager {
public:
    static bool Show(
            const std::wstring& title,
            const std::wstring& body);

private:
    static bool EnsureShortcut();
};