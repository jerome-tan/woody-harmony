#include "ReleaseUpdate.h"
#include "UpdateManager.h"
#include "Backend.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QTemporaryDir>
#include <QtTest>

class TestReply : public QNetworkReply {
public:
  QByteArray body;
  TestReply(const QNetworkRequest &r, QByteArray data, bool failure, QObject *parent, int status = 200)
      : QNetworkReply(parent), body(std::move(data)) {
    setRequest(r); setUrl(r.url()); open(QIODevice::ReadOnly);
    setAttribute(QNetworkRequest::HttpStatusCodeAttribute, status);
    QTimer::singleShot(20, this, [this, failure, status] {
      if (isFinished()) return;
      if (failure) setError(ConnectionRefusedError, "Test network unavailable");
      else if (status >= 400) setError(ContentAccessDenied, "Test HTTP error");
      emit readyRead(); setFinished(true); emit finished();
    });
  }
  void abort() override { if (!isFinished()) { setError(OperationCanceledError,"Canceled"); setFinished(true); emit finished(); } }
  qint64 bytesAvailable() const override { return body.size() + QNetworkReply::bytesAvailable(); }
protected:
  qint64 readData(char *data, qint64 size) override {
    const auto n = qMin(size, qint64(body.size()));
    if (n == 0) return -1;
    memcpy(data, body.constData(), n); body.remove(0,n); return n;
  }
};
class TestNetwork : public QNetworkAccessManager {
public:
  QJsonObject release;
  QByteArray sums, payload = QByteArray(100,'x');
  bool failure = false;
  bool legacy = false, limited = false;
protected:
  QNetworkReply *createRequest(Operation operation, const QNetworkRequest &request, QIODevice *) override {
    if (operation == HeadOperation) {
      QNetworkRequest redirected(request);
      redirected.setUrl(QUrl("https://github.com/jerome-tan/woody-harmony/releases/tag/"+release["tag_name"].toString()));
      return new TestReply(redirected,{},failure,this);
    }
    QByteArray body = (request.url().path().endsWith("/latest") || request.url().path().endsWith("/update.json")) ? QJsonDocument(release).toJson()
        : request.url().path().endsWith("SHA256SUMS.txt") ? sums : payload;
    const int status = legacy && request.url().path().endsWith("/update.json") ? 404
        : limited && request.url().host() == "api.github.com" ? 403 : 200;
    return new TestReply(request, body, failure, this, status);
  }
};

class UpdateTest : public QObject {
  Q_OBJECT
  QJsonObject release(QString tag = "v1.2.0") {
    QJsonArray assets;
    for (const auto &name : QStringList{"Woody-"+tag.mid(1)+"-qt-win-x64-setup.exe",
         "Woody-"+tag.mid(1)+"-qt-win-x64-portable.zip", "Woody-"+tag.mid(1)+"-qt-mac-arm64-portable.zip",
         "Woody-"+tag.mid(1)+"-qt-mac-x64-portable.zip", "SHA256SUMS.txt"})
      assets.append(QJsonObject{{"name",name},{"state","uploaded"},{"size",100},
        {"browser_download_url","https://github.com/jerome-tan/woody-harmony/releases/download/"+tag+'/'+name}});
    return {{"tag_name",tag},{"draft",false},{"prerelease",false},{"body","Changes"},{"assets",assets}};
  }
private slots:
  void legacyAndRateLimitFallback() {
    QCoreApplication::setApplicationVersion("1.0.0");
    QTemporaryDir profile; Backend backend(profile.path());
    TestNetwork network; network.release=release(); network.legacy=true;
    UpdateManager updater(&backend,nullptr,&network);
    updater.check(); QTRY_COMPARE(updater.state(),QString("available"));
    network.limited=true; network.release=release("v1.0.0");
    updater.check(); QTRY_COMPARE(updater.state(),QString("current"));
    network.release=release();
    updater.check(); QTRY_COMPARE(updater.state(),QString("error"));
    QVERIFY(updater.message().contains("发现新版"));
  }
  void checkDownloadFailureAndCancel() {
    QCoreApplication::setApplicationVersion("1.0.0");
    QTemporaryDir profile;
    Backend backend(profile.path());
    TestNetwork network; network.release = release();
    UpdateManager updater(&backend, nullptr, &network);
    QSignalSpy shown(&updater, &UpdateManager::showRequested);
    updater.check(false);
    QTRY_COMPARE(updater.state(), QString("available"));
    QCOMPARE(shown.size(), 1);
    // Checksums for every platform; deliberately wrong for the downloaded bytes.
    for (const auto &a : network.release["assets"].toArray())
      network.sums += QByteArray(64,'a') + "  " + a.toObject()["name"].toString().toUtf8() + '\n';
    updater.download();
    QTRY_COMPARE(updater.state(), QString("error"));
    QVERIFY2(updater.message().contains("SHA-256"), qPrintable(updater.message()));
    updater.check(); QTRY_COMPARE(updater.state(), QString("available"));
    updater.download(); updater.cancel();
    QCOMPARE(updater.state(),QString("available"));
    QTest::qWait(80);
    QCOMPARE(updater.state(),QString("available"));
    network.payload = QByteArray::fromBase64("UEsDBBQAAAAAAFh+a13uQOUFBwAAAAcAAAAeAAAAV29vZHkuYXBwL0NvbnRlbnRzL01hY09TL1dvb2R5Zml4dHVyZVBLAwQUAAAAAABYfmtd7kDlBQcAAAAHAAAADwAAAFdvb2R5L1dvb2R5LmV4ZWZpeHR1cmVQSwECFAMUAAAAAABYfmtd7kDlBQcAAAAHAAAAHgAAAAAAAAAAAAAAgAEAAAAAV29vZHkuYXBwL0NvbnRlbnRzL01hY09TL1dvb2R5UEsBAhQDFAAAAAAAWH5rXe5A5QUHAAAABwAAAA8AAAAAAAAAAAAAAIABQwAAAFdvb2R5L1dvb2R5LmV4ZVBLBQYAAAAAAgACAIkAAAB3AAAAAAA=");
    auto assets=network.release["assets"].toArray();
    network.sums.clear();
    for (int i=0; i<assets.size(); ++i) {
      auto asset=assets[i].toObject(); asset["size"]=network.payload.size(); assets[i]=asset;
      network.sums += QCryptographicHash::hash(network.payload,QCryptographicHash::Sha256).toHex()
          + "  " + asset["name"].toString().toUtf8() + '\n';
    }
    network.release["assets"]=assets;
    updater.check(); QTRY_COMPARE(updater.state(),QString("available"));
    updater.download(); QTRY_COMPARE_WITH_TIMEOUT(updater.state(),QString("ready"),15000);
    updater.cancel(); QCOMPARE(updater.state(),QString("available"));
    network.failure = true;
    updater.check(); QTRY_COMPARE(updater.state(),QString("error"));
    QVERIFY(updater.message().contains("无法连接"));
    updater.setAutomatic(false); QVERIFY(!updater.automatic());
    UpdateManager second(&backend, nullptr, &network); QVERIFY(!second.automatic());
  }
  void versionOrdering() {
    QVERIFY(ReleaseUpdate::newer("v1.10.0","1.9.9"));
    QVERIFY(!ReleaseUpdate::newer("v1.0.0","1.0.0"));
    QVERIFY(!ReleaseUpdate::newer("v1.0.0","2.0.0"));
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::newer("v1.2.0-rc1","1.0.0"), std::exception);
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::newer("v1.02.0","1.0.0"), std::exception);
  }
  void platforms() {
    for (const auto &arch : {"arm64","x64"}) {
      auto r = ReleaseUpdate::parse(release(),"1.0.0","mac",arch,false);
      QCOMPARE(r.assetName,QString("Woody-1.2.0-qt-mac-%1-portable.zip").arg(arch));
    }
    QVERIFY(ReleaseUpdate::parse(release(),"1.0.0","win","x64",true).assetName.endsWith("setup.exe"));
    QVERIFY(ReleaseUpdate::parse(release(),"1.0.0","win","x64",false).assetName.endsWith("portable.zip"));
    QVERIFY(ReleaseUpdate::parse(release("v1.0.0"),"1.0.0","win","x64",false).version.isEmpty());
    auto r=release(); r["draft"]=true;
    QVERIFY(ReleaseUpdate::parse(r,"1.0.0","mac","arm64",false).version.isEmpty());
    r=release(); r["prerelease"]=true;
    QVERIFY(ReleaseUpdate::parse(r,"1.0.0","mac","arm64",false).version.isEmpty());
  }
  void rejectIncompleteOrForeignAssets() {
    auto r=release(); auto assets=r["assets"].toArray(); assets.removeLast();r["assets"]=assets;
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::parse(r,"1.0.0","win","x64",true),std::exception);
    r=release();assets=r["assets"].toArray();auto asset=assets[0].toObject();
    asset["browser_download_url"]="https://example.com/installer.exe";assets[0]=asset;r["assets"]=assets;
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::parse(r,"1.0.0","win","x64",true),std::exception);
    r=release();assets=r["assets"].toArray();asset=assets[0].toObject();
    asset["size"]=0;assets[0]=asset;r["assets"]=assets;
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::parse(r,"1.0.0","win","x64",true),std::exception);
  }
  void exactChecksum() {
    QByteArray hash(64,'a'); const QByteArray line=hash+"  Woody.zip\n";
    QCOMPARE(ReleaseUpdate::checksum(line,"Woody.zip"),hash);
    QCOMPARE(ReleaseUpdate::checksum(hash.toUpper()+" *Woody.zip\r\n","Woody.zip"),hash);
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::checksum(line,"Other.zip"),std::exception);
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::checksum(line+line,"Woody.zip"),std::exception);
    QVERIFY_EXCEPTION_THROWN(ReleaseUpdate::checksum("bad  Woody.zip","Woody.zip"),std::exception);
  }
};
QTEST_GUILESS_MAIN(UpdateTest)
#include "UpdateTest.moc"
