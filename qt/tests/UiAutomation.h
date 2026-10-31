#pragma once
#include <QElapsedTimer>
#include <QJsonArray>
#include <QObject>
#include <QPointer>
#include <QTimer>
class QQmlApplicationEngine;
class QQuickItem;

// Explicit local CLI harness; never enabled by a document, report, or network
// input.
class UiAutomation : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool workloadDone READ workloadDone NOTIFY workloadFinished)
  Q_PROPERTY(bool nativePointer MEMBER mNativePointer)
public:
  UiAutomation(QQmlApplicationEngine *engine, QObject *root, QObject *backend,
               const QString &file);
  Q_INVOKABLE QObject *find(QObject *root, const QString &name) const;
  Q_INVOKABLE bool click(QObject *item, double x = -1, double y = -1);
  Q_INVOKABLE bool hover(QObject *item, double x, double y);
  Q_INVOKABLE bool wheel(QObject *item, double x, double y, int delta);
  Q_INVOKABLE bool drag(QObject *item, double x1, double y1, double x2,
                        double y2);
  Q_INVOKABLE bool key(QObject *window, int key, int modifiers = 0);
  Q_INVOKABLE bool screenshot(QObject *window, const QString &name);
  Q_INVOKABLE void print(const QString &text);
  Q_INVOKABLE void mark(const QString &phase);
  Q_INVOKABLE void runWorkload(QObject *item, int durationMs);
  bool workloadDone() const { return !mWorkTimer.isActive(); }
signals:
  void workloadFinished();

private:
  void tick();
  void finish(const QString &error = {});
  QQmlApplicationEngine *mEngine;
  QObject *mBackend;
  QString mDirectory;
  QJsonArray mSteps, mResults;
  QElapsedTimer mTotal, mStepTime;
  QTimer mTimer;
  QTimer mWorkTimer;
  QElapsedTimer mWorkClock;
  QPointer<QQuickItem> mWorkItem;
  QList<double> mTimerLags;
  qint64 mLastWorkTick = 0;
  int mWorkDuration = 0, mWorkTicks = 0;
  int mIndex = 0;
  bool mExecuted = false;
  bool mNativePointer = false;
};
