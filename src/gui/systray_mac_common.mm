/*
 * SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include <QPointer>
#include <QWindow>

#import <Cocoa/Cocoa.h>

#include "systray.h"
#include "tray/trayiconanimation.h"

static_assert(__has_feature(objc_arc), "systray_mac_common requires ARC.");

Q_LOGGING_CATEGORY(lcMacSystrayCommon, "nextcloud.gui.macsystraycommon")

namespace OCC {

void connectMacOSTrayMotionPreference(TrayIconAnimation *animation)
{
    const auto updatePreference = [animation = QPointer<TrayIconAnimation>(animation)] {
        if (animation) {
            animation->setReducedMotion(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion);
        }
    };
    updatePreference();
    auto *center = NSWorkspace.sharedWorkspace.notificationCenter;
    const auto observer = [center addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                              object:nil
                                               queue:NSOperationQueue.mainQueue
                                          usingBlock:^(NSNotification *) { updatePreference(); }];
    QObject::connect(animation, &QObject::destroyed, [center, observer] {
        [center removeObserver:observer];
    });
}

double menuBarThickness()
{
    NSMenu * const mainMenu = [[NSApplication sharedApplication] mainMenu];

    if (mainMenu == nil) {
        // Return this educated guess if something goes wrong.
        // As of macOS 12.4 this will always return 22, even on notched Macbooks.
        qCWarning(lcMacSystrayCommon) << "Got nil for main menu. "
                                      << "Going with reasonable menu bar height guess.";
        return NSStatusBar.systemStatusBar.thickness;
    }

    return mainMenu.menuBarHeight;
}

void setTrayWindowLevelAndVisibleOnAllSpaces(QWindow *const window)
{
    NSView * const nativeView = (__bridge NSView *)reinterpret_cast<void *>(window->winId());
    NSWindow * const nativeWindow = (NSWindow *)(nativeView.window);
    [nativeWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorIgnoresCycle |
                  NSWindowCollectionBehaviorTransient];
    [nativeWindow setLevel:NSMainMenuWindowLevel];
}

bool osXInDarkMode()
{
    NSString * const osxMode = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleInterfaceStyle"];
    return [osxMode containsString:@"Dark"];
}

}
