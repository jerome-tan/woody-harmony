#pragma once
#include "ReleaseUpdate.h"
#include <QObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QTemporaryDir>
#include <QFile>
#include <QCryptographicHash>
#include <functional>
class Backend;
class QNetworkReply;
class QProcess;

class UpdateManager : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString state READ state NOTIFY changed)
  Q_PROPERTY(QString message READ message NOTIFY changed)
  Q_PROPERTY(QString version READ version NOTIFY changed)
  Q_PROPERTY(QString notes READ notes NOTIFY changed)
  Q_PROPERTY(double progress READ progress NOTIFY changed)
  Q_PROPERTY(bool automatic READ automatic WRITE setAutomatic NOTIFY changed)
public:
  explicit UpdateManager(Backend *backend, QObject *parent = nullptr, QNetworkAccessManager *network = nullptr);
  ~UpdateManager() override;
  QString state() const { return mState; }
  QString message() const { return mMessage; }
  QString version() const { return mRelease.version; }
  QString notes() const { return mRelease.notes; }
  double progress() const { return mProgress; }
  bool automatic() const;
  void setAutomatic(bool enabled);
  Q_INVOKABLE void check(bool interactive = true);
  Q_INVOKABLE void download();
  Q_INVOKABLE void cancel();
  Q_INVOKABLE void install();
  Q_INVOKABLE void openRelease();
  void startup();
signals:
  void changed();
  void showRequested();
private:
  void setState(const QString &state, const QString &message);
  void fail(const QString &message);
  void fetch(const QUrl &url, const std::function<void(QByteArray)> &done);
  void downloadAsset();
  void prepare();
  bool installed() const;
  QString target() const;
  QString helper() const;
  Backend *mBackend;
  QNetworkAccessManager *mNetwork;
  QPointer<QNetworkReply> mReply;
  QPointer<QProcess> mExtract;
  std::unique_ptr<QTemporaryDir> mTemporary;
  QFile mFile;
  QCryptographicHash mHash{QCryptographicHash::Sha256};
  ReleaseUpdate::Release mRelease;
  QByteArray mExpected;
  QString mState = "idle", mMessage = "", mPayload;
  double mProgress = 0;
  qint64 mReceived = 0;
};
