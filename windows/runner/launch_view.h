#ifndef RUNNER_LAUNCH_VIEW_H_
#define RUNNER_LAUNCH_VIEW_H_

#include <windows.h>

// Native cover for the time before Flutter produces its first frame.
// The parent owns the returned child window; no Flutter assets are needed.
HWND CreateLaunchView(HWND parent);

#endif  // RUNNER_LAUNCH_VIEW_H_
