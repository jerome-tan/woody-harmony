#include "UiAutomation.h"
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSaveFile>
#include <algorithm>
#include <cmath>

UiAutomation::UiAutomation(QQmlApplicationEngine *engine, QObject *root,
                           QObject *backend, const QString &file)
    : QObject(engine), mEngine(engine),
      mDirectory(QFileInfo(file).absolutePath()) {
  QFile input(file);
  if (!input.open(QIODevice::ReadOnly)) {
    QTimer::singleShot(0, this,
                       [this] { finish("Cannot read automation script"); });
    return;
  }
  const auto document = QJsonDocument::fromJson(input.readAll());
  if (!document.isObject() || !document.object()["steps"].isArray()) {
    QTimer::singleShot(0, this,
                       [this] { finish("Invalid automation script"); });
    return;
  }
  mSteps = document.object()["steps"].toArray();
  QQmlEngine::setObjectOwnership(root, QQmlEngine::CppOwnership);
  QQmlEngine::setObjectOwnership(backend, QQmlEngine::CppOwnership);
  QQmlEngine::setObjectOwnership(this, QQmlEngine::CppOwnership);
  engine->globalObject().setProperty("root", engine->newQObject(root));
  engine->globalObject().setProperty("backend", engine->newQObject(backend));
  engine->globalObject().setProperty("qa", engine->newQObject(this));
  mTimer.setInterval(30);
  connect(&mTimer, &QTimer::timeout, this, &UiAutomation::tick);
  mTotal.start();
  mStepTime.start();
  mTimer.start();
  mWorkTimer.setInterval(25);
  mWorkTimer.setTimerType(Qt::PreciseTimer);
  connect(&mWorkTimer, &QTimer::timeout, this, [this] {
    const auto now = mWorkClock.elapsed();
    if (mWorkItem) {
      mTimerLags.append(std::max<qint64>(0, now - mLastWorkTick - 25));
      mLastWorkTick = now;
      const int due = int(std::min<qint64>(now, mWorkDuration) / 25);
      // Catch up delayed timer ticks so both runtimes receive exactly the same
      // input count.
      while (mWorkTicks < due) {
        const double x = 80 + (mWorkItem->width() - 110) *
                                  (.5 + .4 * std::sin(mWorkTicks * .07));
        hover(mWorkItem, x, mWorkItem->height() * .45);
        if (mWorkTicks % 4 == 0)
          wheel(mWorkItem, mWorkItem->width() * .55, mWorkItem->height() * .5,
                (mWorkTicks / 80) % 2 ? -80 : 80);
        ++mWorkTicks;
      }
    }
    if (now >= mWorkDuration || !mWorkItem) {
      mWorkTimer.stop();
      std::sort(mTimerLags.begin(), mTimerLags.end());
      const double p95 = mTimerLags.isEmpty()
                             ? 0
                             : mTimerLags[int((mTimerLags.size() - 1) * .95)];
      QFile output(QDir(mDirectory).filePath("interaction.json"));
      if (output.open(QIODevice::WriteOnly))
        output.write(
            QJsonDocument(QJsonObject{{"timerLagP95Ms", p95},
                                      {"inputTicks", mWorkTicks},
                                      {"elapsedMs", mWorkClock.elapsed()}})
                .toJson());
      mark("done");
      emit workloadFinished();
    }
  });
}

void UiAutomation::mark(const QString &phase) {
  QSaveFile output(QDir(mDirectory).filePath("phase.json"));
  if (output.open(QIODevice::WriteOnly)) {
    output.write(
        QJsonDocument(
            QJsonObject{{"phase", phase},
                        {"timestamp", QDateTime::currentMSecsSinceEpoch()}})
            .toJson());
    output.commit();
  }
}
void UiAutomation::runWorkload(QObject *item, int durationMs) {
  mWorkItem = qobject_cast<QQuickItem *>(item);
  if (!mWorkItem) {
    finish("Workload target is not a visual item");
    return;
  }
  mWorkDuration = durationMs;
  mWorkTicks = 0;
  mLastWorkTick = 0;
  mTimerLags.clear();
  mWorkClock.start();
  mark("interaction");
  mWorkTimer.start();
}
QObject *UiAutomation::find(QObject *root, const QString &name) const {
  if (!root)
    return nullptr;
  if (root->objectName() == name)
    return root;
  if (auto *found = root->findChild<QObject *>(name))
    return found;
  if (auto *item = qobject_cast<QQuickItem *>(root))
    for (auto *child : item->childItems())
      if (auto *found = find(child, name))
        return found;
  if (auto *window = qobject_cast<QQuickWindow *>(root))
    return find(window->contentItem(), name);
  return nullptr;
}
namespace {
bool mouse(QObject *object, QEvent::Type type, double x, double y,
           Qt::MouseButton button, Qt::MouseButtons held) {
  auto *item = qobject_cast<QQuickItem *>(object);
  if (!item || !item->window())
    return false;
  const auto point = item->mapToScene(
      QPointF(x < 0 ? item->width() / 2 : x, y < 0 ? item->height() / 2 : y));
  QMouseEvent event(type, point, item->window()->mapToGlobal(point.toPoint()),
                    button, held, Qt::NoModifier);
  return QCoreApplication::sendEvent(item->window(), &event);
}
} // namespace
bool UiAutomation::click(QObject *item, double x, double y) {
  mouse(item, QEvent::MouseButtonPress, x, y, Qt::LeftButton, Qt::LeftButton);
  return mouse(item, QEvent::MouseButtonRelease, x, y, Qt::LeftButton,
               Qt::NoButton);
}
bool UiAutomation::hover(QObject *item, double x, double y) {
  return mouse(item, QEvent::MouseMove, x, y, Qt::NoButton, Qt::NoButton);
}
bool UiAutomation::wheel(QObject *object, double x, double y, int delta) {
  auto *item = qobject_cast<QQuickItem *>(object);
  if (!item || !item->window())
    return false;
  const auto point = item->mapToScene(QPointF(x, y));
  QWheelEvent event(point, item->window()->mapToGlobal(point.toPoint()), {},
                    QPoint(0, delta), Qt::NoButton, Qt::NoModifier,
                    Qt::NoScrollPhase, false);
  return QCoreApplication::sendEvent(item->window(), &event);
}
bool UiAutomation::drag(QObject *item, double x1, double y1, double x2,
                        double y2) {
  mouse(item, QEvent::MouseButtonPress, x1, y1, Qt::LeftButton, Qt::LeftButton);
  for (int i = 1; i <= 12; ++i)
    mouse(item, QEvent::MouseMove, x1 + (x2 - x1) * i / 12,
          y1 + (y2 - y1) * i / 12, Qt::NoButton, Qt::LeftButton);
  return mouse(item, QEvent::MouseButtonRelease, x2, y2, Qt::LeftButton,
               Qt::NoButton);
}
bool UiAutomation::key(QObject *object, int code, int modifiers) {
  auto *window = qobject_cast<QQuickWindow *>(object);
  if (!window)
    return false;
  QKeyEvent press(QEvent::KeyPress, code, Qt::KeyboardModifiers(modifiers)),
      release(QEvent::KeyRelease, code, Qt::KeyboardModifiers(modifiers));
  QCoreApplication::sendEvent(window, &press);
  return QCoreApplication::sendEvent(window, &release);
}
bool UiAutomation::screenshot(QObject *object, const QString &name) {
  auto *window = qobject_cast<QQuickWindow *>(object);
  if (!window)
    return false;
  const auto file = QDir(mDirectory).filePath(name);
  QDir().mkpath(QFileInfo(file).absolutePath());
  return window->grabWindow().save(file);
}
void UiAutomation::print(const QString &message) {
  qInfo().noquote() << message;
}
void UiAutomation::tick() {
  if (mIndex >= mSteps.size()) {
    finish();
    return;
  }
  const auto step = mSteps[mIndex].toObject();
  if (mStepTime.elapsed() < step["delay"].toInt(80))
    return;
  if (!mExecuted) {
    mExecuted = true;
    if (step.contains("eval")) {
      const auto result = mEngine->evaluate(step["eval"].toString());
      if (result.isError()) {
        finish(result.toString() + "\n" + result.property("stack").toString());
        return;
      }
    }
  }
  if (step.contains("wait")) {
    const auto result = mEngine->evaluate(step["wait"].toString());
    if (result.isError()) {
      finish(result.toString());
      return;
    }
    if (!result.toBool()) {
      if (mStepTime.elapsed() > step["timeout"].toInt(10000))
        finish("Timed out: " + step["wait"].toString());
      return;
    }
  }
  if (step.contains("assert")) {
    const auto result = mEngine->evaluate(step["assert"].toString());
    if (result.isError() || !result.toBool()) {
      finish("Assertion failed: " + step["assert"].toString() + " => " +
             result.toString());
      return;
    }
  }
  if (step.contains("screenshot")) {
    auto window = mEngine->evaluate(step["window"].toString("root"));
    if (!screenshot(window.toQObject(), step["screenshot"].toString())) {
      finish("Screenshot failed");
      return;
    }
  }
  mResults.append(QJsonObject{{"name", step["name"]},
                              {"elapsedMs", mStepTime.elapsed()},
                              {"passed", true}});
  qInfo().noquote() << "PASS" << step["name"].toString();
  ++mIndex;
  mExecuted = false;
  mStepTime.restart();
}
void UiAutomation::finish(const QString &error) {
  mTimer.stop();
  if (!error.isEmpty()) {
    qCritical().noquote() << "FAIL step" << mIndex << error;
    mResults.append(QJsonObject{{"name", mIndex < mSteps.size()
                                             ? mSteps[mIndex].toObject()["name"]
                                             : QJsonValue("initialization")},
                                {"passed", false},
                                {"error", error}});
  }
  QFile output(QDir(mDirectory).filePath("ui-result.json"));
  if (output.open(QIODevice::WriteOnly))
    output.write(
        QJsonDocument(
            QJsonObject{{"passed", error.isEmpty()},
                        {"elapsedMs", mTotal.isValid() ? mTotal.elapsed() : 0},
                        {"steps", mResults}})
            .toJson());
  QCoreApplication::exit(error.isEmpty() ? 0 : 2);
}
