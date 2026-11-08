/*
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "systray.h"
#include "theme.h"
#include "tray/trayiconanimation.h"

#include <QFile>
#include <QPainter>
#include <QSignalSpy>
#include <QSvgRenderer>
#include <QTest>
#include <QXmlStreamReader>

#import <AppKit/AppKit.h>

using namespace Qt::StringLiterals;

class TestTrayBranding : public QObject
{
    Q_OBJECT

private:
    NSDictionary *_arguments = nil;

    void setDarkMenuBar(bool dark)
    {
        auto *arguments = [[NSMutableDictionary alloc] initWithDictionary:_arguments];
        [arguments setObject:(dark ? @"Dark" : @"Light") forKey:@"AppleInterfaceStyle"];
        [[NSUserDefaults standardUserDefaults] setVolatileDomain:arguments forName:NSArgumentDomain];
        [arguments release];
    }

    QImage renderSvg(const QString &path, int size)
    {
        auto renderer = QSvgRenderer(path);
        auto image = QImage(size, size, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        {
            auto painter = QPainter(&image);
            renderer.render(&painter);
        }
        return image;
    }

    QStringList compassPaths(const QString &path)
    {
        auto file = QFile(path);
        if (!file.open(QIODevice::ReadOnly)) {
            return {};
        }
        auto xml = QXmlStreamReader(&file);
        auto paths = QStringList{};
        while (!xml.atEnd()) {
            xml.readNext();
            if (xml.isStartElement() && xml.name() == u"path") {
                const auto attributes = xml.attributes();
                paths.append(attributes.value(u"id").toString() + u"|"_s + attributes.value(u"d").toString() + u"|"_s
                             + attributes.value(u"transform").toString());
            }
        }
        return xml.hasError() ? QStringList{} : paths;
    }

private Q_SLOTS:
    void initTestCase()
    {
        Q_INIT_RESOURCE(resources);
        Q_INIT_RESOURCE(theme);
        if (OCC::Theme::instance()->appNameGUI() != u"Outlaw Cloud"_s) {
            QSKIP("Requires the Outlaw Cloud branded build.");
        }
        _arguments = [[[NSUserDefaults standardUserDefaults] volatileDomainForName:NSArgumentDomain] copy];
    }

    void cleanupTestCase()
    {
        if (_arguments) {
            [[NSUserDefaults standardUserDefaults] setVolatileDomain:_arguments forName:NSArgumentDomain];
            [_arguments release];
        }
    }

    void connectedCompass_data()
    {
        QTest::addColumn<bool>("mono");
        QTest::addColumn<int>("size");
        for (const auto size : {18, 36}) {
            for (const auto mono : {false, true}) {
                QTest::newRow(qPrintable(u"%1px-mono-%2"_s.arg(size).arg(mono))) << mono << size;
            }
        }
    }

    void connectedCompass()
    {
        QFETCH(bool, mono);
        QFETCH(int, size);
        auto *theme = OCC::Theme::instance();
        theme->setSystrayUseMonoIcons(mono);

        // Reuse the same theme across appearance changes to catch stale icon caches.
        for (const auto dark : {false, true, false}) {
            setDarkMenuBar(dark);
            const auto icon = theme->syncStateIcon(OCC::SyncResult::Success, true);
            QVERIFY(!icon.isNull());
            QVERIFY(!icon.isMask()); // A macOS template would discard the green accent.
            const auto flavor = dark ? u"white"_s : u"black"_s;
            const auto expected = renderSvg(u":/client/theme/%1/outlaw-tray-connected.svg"_s.arg(flavor), size);
            const auto actual = icon.pixmap(QSize(size, size), 1.0).toImage().convertToFormat(expected.format());
            QCOMPARE(actual, expected);

            auto inkPixels = 0;
            auto accentPixels = 0;
            for (auto y = 0; y < size; ++y) {
                for (auto x = 0; x < size; ++x) {
                    const auto color = actual.pixelColor(x, y);
                    if (color.alpha() < 128) {
                        continue;
                    }
                    if (dark ? color.red() >= 230 && color.green() >= 230 && color.blue() >= 230
                             : color.red() <= 25 && color.green() <= 25 && color.blue() <= 25) {
                        ++inkPixels;
                    }
                    if (color.green() > color.red() && color.green() > color.blue()) {
                        ++accentPixels;
                    }
                }
            }
            QVERIFY(inkPixels > 0);
            QVERIFY(accentPixels > 0);

            // The generic status glyph remains available outside the menu bar.
            const auto status = theme->syncStateIcon(OCC::SyncResult::Success, false);
            const auto generic = renderSvg(u":/client/theme/colored/state-ok.svg"_s, 32);
            QCOMPARE(status.pixmap(QSize(32, 32), 1.0).toImage().convertToFormat(generic.format()), generic);
        }
    }

    void otherStates_data()
    {
        QTest::addColumn<QString>("name");
        QTest::addColumn<int>("status");
        QTest::newRow("sync") << u"state-sync"_s << int(OCC::SyncResult::SyncRunning);
        QTest::newRow("offline") << u"state-offline"_s << int(OCC::SyncResult::Undefined);
        QTest::newRow("warning") << u"state-warning"_s << int(OCC::SyncResult::Problem);
        QTest::newRow("error") << u"state-error"_s << int(OCC::SyncResult::Error);
        QTest::newRow("pause") << u"state-pause"_s << int(OCC::SyncResult::Paused);
    }

    void otherStates()
    {
        QFETCH(QString, name);
        QFETCH(int, status);
        auto *theme = OCC::Theme::instance();
        for (const auto dark : {false, true}) {
            setDarkMenuBar(dark);
            for (const auto mono : {false, true}) {
                theme->setSystrayUseMonoIcons(mono);
                const auto icon =
                    name == u"state-offline"_s ? theme->folderOfflineIcon(true) : theme->syncStateIcon(static_cast<OCC::SyncResult::Status>(status), true);
                QVERIFY(!icon.isMask());
                const auto flavor = dark ? u"white"_s : u"black"_s;
                const auto expected = renderSvg(u":/client/theme/%1/outlaw-tray-%2.svg"_s.arg(flavor, name), 32);
                QCOMPARE(icon.pixmap(QSize(32, 32), 1.0).toImage().convertToFormat(expected.format()), expected);

                const auto generic = renderSvg(u":/client/theme/colored/%1.svg"_s.arg(name), 32);
                const auto nonTray =
                    name == u"state-offline"_s ? theme->folderOfflineIcon(false) : theme->syncStateIcon(static_cast<OCC::SyncResult::Status>(status), false);
                QCOMPARE(nonTray.pixmap(QSize(32, 32), 1.0).toImage().convertToFormat(generic.format()), generic);

                if (name == u"state-error"_s) {
                    const auto maroon = dark ? QColor(179, 90, 112) : QColor(128, 0, 32);
                    const auto actual = icon.pixmap(QSize(72, 72), 1.0).toImage();
                    auto maroonPixels = 0;
                    for (auto y = 0; y < actual.height(); ++y) {
                        for (auto x = 0; x < actual.width(); ++x) {
                            if (actual.pixelColor(x, y) == maroon) {
                                ++maroonPixels;
                            }
                        }
                    }
                    QVERIFY(maroonPixels > 0);
                }
            }
        }
    }

    void appearanceRefreshesTray()
    {
        auto *theme = OCC::Theme::instance();
        auto changed = QSignalSpy(theme, &OCC::Theme::systrayUseMonoIconsChanged);
        theme->systemPaletteHasChanged();
        QCOMPARE(changed.count(), 1);
        QCOMPARE(changed.at(0).at(0).toBool(), theme->systrayUseMonoIcons());
    }

    void everyStateRetainsAllCompassPathsAndOuterArcs()
    {
        const auto approved = compassPaths(u":/client/theme/black/outlaw-tray-connected.svg"_s);
        QCOMPARE(approved.size(), 13);
        QCOMPARE(approved.filter(u"arc|"_s).size(), 4);
        for (const auto &flavor : {u"white"_s, u"black"_s}) {
            for (const auto &name : {u"connected"_s, u"state-sync"_s, u"state-offline"_s, u"state-pause"_s, u"state-warning"_s, u"state-error"_s}) {
                QCOMPARE(compassPaths(u":/client/theme/%1/outlaw-tray-%2.svg"_s.arg(flavor, name)), approved);
            }
        }
    }

    void nativeMotionObserverIsRemovedWithItsAnimation()
    {
        auto tray = QSystemTrayIcon{};
        auto *animation = new OCC::TrayIconAnimation(tray);
        OCC::connectMacOSTrayMotionPreference(animation);
        auto *center = NSWorkspace.sharedWorkspace.notificationCenter;
        [center postNotificationName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
        delete animation;
        [center postNotificationName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
        QTest::qWait(1);
    }
};

QTEST_MAIN(TestTrayBranding)
#include "testtraybranding.moc"
