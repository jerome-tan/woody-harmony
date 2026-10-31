#include "../tests/UiAutomation.h"
#include "Backend.h"
#include "MemoryPlot.h"
#include "SnapshotPlot.h"
#include <QCommandLineParser>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSysInfo>
#include <QThreadPool>

int main(int argc, char **argv) {
  QElapsedTimer startup;
  startup.start();
  QGuiApplication::setApplicationName("Woody");
  QGuiApplication::setApplicationVersion(WOODY_VERSION);
  QGuiApplication::setOrganizationName("");
  QGuiApplication::setDesktopFileName("com.woody.harmony");
  QGuiApplication app(argc, argv);
  app.setWindowIcon(QIcon(":/assets/icon.png"));
  QQuickStyle::setStyle("Basic");
  QFont font = app.font();
  font.setPixelSize(14);
  app.setFont(font);
  QCommandLineParser parser;
  parser.addHelpOption();
  parser.addVersionOption();
  parser.addOption(
      {"profile", "Use an isolated settings directory.", "directory"});
  parser.addOption({"offline", "Skip device discovery (report-only use)."});
  parser.addOption(
      {"report", "Open a report directory on startup.", "directory"});
  parser.addOption({"compare",
                    "Compare report directories (repeat this option).",
                    "directory"});
  parser.addOption({"metrics",
                    "Write startup/frame measurements to a JSON file on exit.",
                    "file"});
  parser.addOption({"quit-after",
                    "Exit after a specified number of milliseconds.",
                    "milliseconds"});
  parser.addOption(
      {"qa", "Run an explicit local UI validation script.", "file"});
  parser.addOption(
      {"ready-file", "Write a marker after the first rendered frame.", "file"});
  parser.process(app);
  qmlRegisterType<MemoryPlot>("Woody.Native", 1, 0, "MemoryPlot");
  qmlRegisterType<SnapshotPlot>("Woody.Native", 1, 0, "SnapshotPlot");
  qmlRegisterUncreatableType<Report>("Woody.Native", 1, 0, "Report",
                                     "Reports are loaded by Woody");
  Backend backend(parser.value("profile"));
  QQmlEngine::setObjectOwnership(&backend, QQmlEngine::CppOwnership);
  QObject::connect(&backend, &Backend::quitReady, &app, &QCoreApplication::quit,
                   Qt::QueuedConnection);
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("backend", &backend);
  engine.rootContext()->setContextProperty(
      "buildInfo", QVariantMap{{"version", WOODY_VERSION},
                               {"commit", WOODY_COMMIT},
                               {"qt", QT_VERSION_STR},
                               {"os", QSysInfo::prettyProductName()},
                               {"arch", QSysInfo::currentCpuArchitecture()}});
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
  engine.loadFromModule("Woody", "Main");
  if (engine.rootObjects().isEmpty())
    return 1;
  qint64 firstFrame = -1, frames = 0;
  if (auto *window =
          qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
    QObject::connect(
        window, &QQuickWindow::frameSwapped, &app,
        [&] {
          if (firstFrame < 0) {
            firstFrame = startup.elapsed();
            if (parser.isSet("ready-file")) {
              QFile marker(parser.value("ready-file"));
              if (marker.open(QIODevice::WriteOnly))
                marker.write("ready\n");
            }
          }
          ++frames;
        },
        Qt::QueuedConnection);
  }
  QTimer::singleShot(0, &backend, [&] {
    if (!parser.isSet("offline"))
      backend.initialize();
    else
      backend.refreshRecords();
    if (parser.isSet("report"))
      backend.openReport(parser.value("report"));
    if (parser.values("compare").size() >= 2)
      backend.openCompare(parser.values("compare"));
  });
  if (parser.isSet("quit-after"))
    QTimer::singleShot(parser.value("quit-after").toInt(), &backend,
                       &Backend::requestQuit);
  if (parser.isSet("qa"))
    new UiAutomation(&engine, engine.rootObjects().first(), &backend,
                     parser.value("qa"));
  const int result = app.exec();
  if (parser.isSet("metrics")) {
    QFile file(parser.value("metrics"));
    if (file.open(QIODevice::WriteOnly))
      file.write(QJsonDocument(QJsonObject{{"qt", QT_VERSION_STR},
                                           {"firstFrameMs", firstFrame},
                                           {"elapsedMs", startup.elapsed()},
                                           {"frames", frames}})
                     .toJson());
  }
  return result;
}
