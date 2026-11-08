/*
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "tray/trayiconanimation.h"

#include <QPainter>
#include <QPointer>
#include <QSystemTrayIcon>
#include <QTest>

using namespace OCC;

class TestTrayIconAnimation : public QObject
{
    Q_OBJECT

private:
    QIcon directionalIcon(const QColor &color)
    {
        auto image = QPixmap(72, 72);
        image.fill(Qt::transparent);
        {
            auto painter = QPainter(&image);
            painter.fillRect(QRect(31, 4, 10, 30), color);
        }
        return QIcon(image);
    }

private Q_SLOTS:
    void fullTurnTakes4200MillisecondsWithoutChangingCanvasSize()
    {
        auto tray = QSystemTrayIcon{};
        auto animation = TrayIconAnimation(tray);
        const auto source = directionalIcon(Qt::blue);
        animation.setIcon(source, true);
        auto *timeline = animation.findChild<QTimeLine *>();
        QVERIFY(timeline);
        QCOMPARE(timeline->duration(), 4200);
        QCOMPARE(timeline->updateInterval(), 40);
        QCOMPARE(timeline->loopCount(), 0);
        QCOMPARE(timeline->easingCurve().type(), QEasingCurve::Linear);
        QCOMPARE(timeline->state(), QTimeLine::Running);

        const auto rest = tray.icon().pixmap(QSize(36, 36), 1.0).toImage();
        timeline->setCurrentTime(1050);
        QCOMPARE(timeline->currentValue(), 0.25);
        const auto quarterTurn = tray.icon().pixmap(QSize(36, 36), 1.0).toImage();
        QCOMPARE(quarterTurn.size(), rest.size());
        QVERIFY(quarterTurn != rest);
        QVERIFY(quarterTurn.pixelColor(30, 18).alpha() > 0);
        QVERIFY(!tray.icon().isMask());

        timeline->setCurrentTime(2100);
        QCOMPARE(timeline->currentValue(), 0.5);
        const auto halfTurn = tray.icon().pixmap(QSize(36, 36), 1.0).toImage();
        QCOMPARE(halfTurn.size(), rest.size());
        QVERIFY(halfTurn != quarterTurn);
    }

    void repeatedSyncUpdatesAndAppearanceChangesPreservePhase()
    {
        auto tray = QSystemTrayIcon{};
        auto animation = TrayIconAnimation(tray);
        animation.setIcon(directionalIcon(Qt::blue), true);
        auto *timeline = animation.findChild<QTimeLine *>();
        timeline->setCurrentTime(1050);
        const auto oldFrame = tray.icon().pixmap(QSize(36, 36), 1.0).toImage();

        animation.setIcon(directionalIcon(Qt::cyan), true);
        QCOMPARE(timeline->currentTime(), 1050);
        QCOMPARE(timeline->state(), QTimeLine::Running);
        QVERIFY(tray.icon().pixmap(QSize(36, 36), 1.0).toImage() != oldFrame);
        QVERIFY(tray.icon().pixmap(QSize(36, 36), 1.0).toImage().pixelColor(30, 18).alpha() > 0);
    }

    void staticStateImmediatelyStopsRotation()
    {
        auto tray = QSystemTrayIcon{};
        auto animation = TrayIconAnimation(tray);
        animation.setIcon(directionalIcon(Qt::blue), true);
        auto *timeline = animation.findChild<QTimeLine *>();
        timeline->setCurrentTime(1050);

        const auto error = directionalIcon(QColor(128, 0, 32));
        animation.setIcon(error, false);
        QCOMPARE(timeline->state(), QTimeLine::NotRunning);
        QCOMPARE(tray.icon().cacheKey(), error.cacheKey());
        timeline->setCurrentTime(2100);
        QCoreApplication::processEvents();
        QCOMPARE(tray.icon().cacheKey(), error.cacheKey());
    }

    void reducedMotionKeepsSyncingStationaryAndCanResume()
    {
        auto tray = QSystemTrayIcon{};
        auto animation = TrayIconAnimation(tray);
        const auto source = directionalIcon(Qt::blue);
        animation.setIcon(source, true);
        auto *timeline = animation.findChild<QTimeLine *>();

        animation.setReducedMotion(true);
        QCOMPARE(timeline->state(), QTimeLine::NotRunning);
        QCOMPARE(tray.icon().cacheKey(), source.cacheKey());
        animation.setIcon(source, true);
        QCOMPARE(timeline->state(), QTimeLine::NotRunning);
        animation.setReducedMotion(false);
        QCOMPARE(timeline->state(), QTimeLine::Running);

        animation.setIcon(source, false);
        animation.setReducedMotion(true);
        animation.setReducedMotion(false);
        QCOMPARE(timeline->state(), QTimeLine::NotRunning);
        QCOMPARE(tray.icon().cacheKey(), source.cacheKey());
    }

    void emptyIconAndDestructionLeaveNoRunningTimeline()
    {
        auto tray = QSystemTrayIcon{};
        auto *animation = new TrayIconAnimation(tray);
        auto timeline = QPointer<QTimeLine>(animation->findChild<QTimeLine *>());
        animation->setIcon({}, true);
        QCOMPARE(timeline->state(), QTimeLine::NotRunning);
        QVERIFY(tray.icon().isNull());

        animation->setIcon(directionalIcon(Qt::blue), true);
        QCOMPARE(timeline->state(), QTimeLine::Running);
        delete animation;
        QVERIFY(timeline.isNull());
        QCoreApplication::processEvents();
    }
};

QTEST_MAIN(TestTrayIconAnimation)
#include "testtrayiconanimation.moc"
