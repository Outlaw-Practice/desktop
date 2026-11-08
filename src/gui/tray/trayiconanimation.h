/*
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <QIcon>
#include <QObject>
#include <QTimeLine>

class QSystemTrayIcon;

namespace OCC
{

/** Keeps a syncing tray icon rotating until another state replaces it. */
class TrayIconAnimation : public QObject
{
    Q_OBJECT

public:
    static constexpr auto revolutionDurationMs = 4200;
    static constexpr auto frameIntervalMs = 40;

    explicit TrayIconAnimation(QSystemTrayIcon &tray);

    void setIcon(const QIcon &icon, bool syncing);
    void setReducedMotion(bool reducedMotion);

private:
    void updateAnimation();
    void renderFrame(qreal angle);

    QSystemTrayIcon &_tray;
    QTimeLine _timeline{revolutionDurationMs, this};
    QIcon _icon;
    bool _syncing = false;
    bool _reducedMotion = false;
};

}
