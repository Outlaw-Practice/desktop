/*
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "trayiconanimation.h"

#include <QEasingCurve>
#include <QPainter>
#include <QSystemTrayIcon>

namespace OCC
{

TrayIconAnimation::TrayIconAnimation(QSystemTrayIcon &tray)
    : QObject(&tray)
    , _tray(tray)
{
    _timeline.setEasingCurve(QEasingCurve::Linear);
    _timeline.setLoopCount(0);
    _timeline.setUpdateInterval(frameIntervalMs);
    connect(&_timeline, &QTimeLine::valueChanged, this, [this](qreal value) {
        if (_syncing && !_reducedMotion && !_icon.isNull()) {
            renderFrame(value * 360);
        }
    });
}

void TrayIconAnimation::setIcon(const QIcon &icon, bool syncing)
{
    _icon = icon;
    _syncing = syncing;
    updateAnimation();
}

void TrayIconAnimation::setReducedMotion(bool reducedMotion)
{
    if (_reducedMotion == reducedMotion) {
        return;
    }
    _reducedMotion = reducedMotion;
    updateAnimation();
}

void TrayIconAnimation::updateAnimation()
{
    if (_syncing && !_reducedMotion && !_icon.isNull()) {
        if (_timeline.state() == QTimeLine::NotRunning) {
            _timeline.start();
        }
        renderFrame(_timeline.currentValue() * 360);
    } else {
        _timeline.stop();
        _tray.setIcon(_icon);
    }
}

void TrayIconAnimation::renderFrame(qreal angle)
{
    auto frame = QIcon{};
    // Fixed canvases avoid changing the menu item's size as the compass turns.
    // Include native menu-bar, Retina and enlarged representations.
    for (const auto size : {18, 36, 72}) {
        auto pixmap = QPixmap(size, size);
        pixmap.fill(Qt::transparent);
        {
            auto painter = QPainter(&pixmap);
            painter.translate(size / 2.0, size / 2.0);
            painter.rotate(angle);
            painter.translate(-size / 2.0, -size / 2.0);
            _icon.paint(&painter, QRect(0, 0, size, size));
        }
        frame.addPixmap(pixmap);
    }
    _tray.setIcon(frame);
}

}
