# Backup & Restore Runbook

Bu doküman, yerel Kubernetes ortamındaki MongoDB verilerinin yedeklenmesi, geri yüklenmesi ve veri kaybı sonrasında doğrulanması için uygulanan prosedürü açıklar.

**Test tarihi:** 10 Kasım 2026  
**Kubernetes context:** `k3d-devops-case`  
**Namespace:** `devops-case`  
**MongoDB Pod:** `mongodb-0`

## 1. Yaklaşım / Approach

| Özellik | Açıklama |
| --- | --- |
| Yedekleme yöntemi | MongoDB `mongodump` |
| Geri yükleme yöntemi | MongoDB `mongorestore --drop` |
| Çalıştırma yöntemi | Manuel Bash scriptleri |
| Backup script'i | `scripts/backup.sh` |
| Restore script'i | `scripts/restore.sh` |
| Yedeklenen veritabanları | `sample_training`, `github_etl` |
| Saklama konumu | `backups/YYYYMMDDTHHMMSSZ/` |
| Yedek formatı | Veritabanı başına ayrı `.archive` dosyası |
| Bütünlük doğrulaması | SHA-256 checksum |
| Dosya izinleri | Klasör `700`, dosyalar `600` |
| Otomatik zamanlama | Uygulanmadı |
| Otomatik retention | Uygulanmadı |
| Şifreli uzak depolama | Uygulanmadı |

### 1.1. Backup içeriği

Her backup işleminde üç dosya oluşturulur:

```text
backups/
└── YYYYMMDDTHHMMSSZ/
    ├── sample_training.archive
    ├── github_etl.archive
    └── SHA256SUMS
```

Yedekler Kubernetes cluster'ı dışında, script'in çalıştırıldığı bilgisayarda saklanır.

Bu yöntem MongoDB Pod'unun veya Kubernetes kaynaklarının kaybedilmesi durumunda verilerin geri yüklenmesini destekler. Ancak aynı bilgisayardaki disk arızasına karşı bağımsız koruma sağlamaz.

### 1.2. Sıklık ve retention yaklaşımı

Mevcut uygulamada backup işlemi manuel olarak başlatılır. Otomatik backup takvimi ve retention temizleme mekanizması bulunmaz.

Üretim ortamı için önerilen operasyonel politika:

- **Backup sıklığı:** Her 24 saatte bir.
- **Retention hedefi:** Son 7 günlük yedeğin saklanması.
- **Ek koruma:** Yedeklerin şifreli ve cluster dışındaki bağımsız bir depolama ortamına aktarılması.
- **Doğrulama:** Periyodik checksum kontrolü ve restore tatbikatı.

Bu değerler önerilen hedeflerdir; mevcut sistemde otomatik olarak uygulanmamaktadır.

## 2. Hedefler / Targets

| Metrik | Önerilen hedef | Gerçek test sonucu |
| --- | --- | --- |
| RPO | En fazla 24 saat | Manuel backup kullanıldığı için garanti edilen RPO yok |
| RTO | En fazla 15 dakika | Uçtan uca kurtarma süresi ölçülmedi |
| Restore script çalışma süresi | RTO hedefinin altında tamamlanması | 4,80 saniye |
| Backup bütünlüğü | SHA-256 doğrulaması başarılı | İki arşiv için `OK` |
| Veri kurtarma | Silinen kayıtlar hem arayüzde hem MongoDB'de geri gelmeli | Başarılı |
| Retention | 7 gün | Otomatik retention uygulanmadı |

**RPO (Recovery Point Objective):** Veri kaybı durumunda kabul edilebilir en fazla veri kaybı süresidir. Günlük backup politikası uygulanırsa hedef RPO 24 saat olarak belirlenebilir. Mevcut manuel backup sisteminde bu hedef garanti edilmez.

**RTO (Recovery Time Objective):** Bir kesinti sonrasında hizmetin kabul edilen süre içinde geri getirilmesi hedefidir. Bu çalışma için önerilen RTO hedefi 15 dakikadır.

10 Kasım 2026 tarihli testte restore script'inin toplam çalışma süresi `/usr/bin/time -p` ile **4,80 saniye** olarak ölçülmüştür. Bu ölçüm kullanıcı onayını da içerir.

Ancak kesintinin başlangıcından uygulamanın tamamen doğrulanmasına kadar geçen süre ayrıca ölçülmediğinden, 4,80 saniye uçtan uca RTO değeri olarak değerlendirilmemiştir.


## 3. Yedek alma adımları / Backup procedure

### 3.1. Ön koşullar

- Kubernetes context `k3d-devops-case` olmalıdır.
- `devops-case` namespace'i erişilebilir olmalıdır.
- `mongodb-0` Pod'u çalışır durumda olmalıdır.
- MongoDB kimlik bilgileri Pod ortamında tanımlı olmalıdır.
- Backup dosyaları için yeterli yerel disk alanı bulunmalıdır.

### 3.2. Ortam kontrolü

```bash
kubectl config current-context
kubectl get pod mongodb-0 -n devops-case
```

### 3.3. Backup oluşturma

Proje kök dizininde:

```bash
./scripts/backup.sh
```

Script sırasıyla `sample_training` ve `github_etl` veritabanlarını yedekler.

Başarısız veya boş dump dosyaları hata olarak değerlendirilir. Geçici `.partial` dosyaları başarılı işlem sonrasında kalıcı arşiv dosyasına dönüştürülür.

### 3.4. Backup doğrulaması

```bash
BACKUP_DIR="backups/20261110T161624Z"

ls -lh "$BACKUP_DIR"

(
  cd "$BACKUP_DIR"
  shasum -a 256 -c SHA256SUMS
)
```

Gerçek testte alınan sonuç:

```text
sample_training.archive: OK
github_etl.archive: OK
```

**Test backup konumu:** `backups/20261110T161624Z`

Backup sırasında `sample_training.records` collection'ından 2 belge, `sample_training.backup_restore_test` collection'ından 1 belge ve `github_etl.repositories` collection'ından 3 belge arşivlenmiştir.

İki arşiv oluşturulmuş ve SHA-256 bütünlük kontrolleri başarıyla tamamlanmıştır.


## 4. Geri yükleme adımları / Restore procedure

### 4.1. Ön koşullar

Restore işleminden önce:

1. Doğru backup klasörü seçilmelidir.
2. Backup dosyalarının bütünlüğü kontrol edilmelidir.
3. MongoDB'ye yazma yapan uygulama ve zamanlanmış işler değerlendirilmelidir.
4. Restore işleminin mevcut collection'ları değiştireceği dikkate alınmalıdır.
5. Gerekirse restore öncesinde güncel verilerin ayrıca yedeği alınmalıdır.

**Uyarı:** `mongorestore --drop`, yedekte bulunan collection'ların mevcut sürümlerini silerek yedekteki içerikle değiştirir. Backup sonrasında yapılan değişiklikler kaybolabilir.

### 4.2. ETL CronJob'ını geçici durdurma

```bash
kubectl patch cronjob github-etl -n devops-case \
  -p '{"spec":{"suspend":true}}'

kubectl get cronjob github-etl -n devops-case
```

Beklenen durum:

```text
SUSPEND=True
ACTIVE=0
```

Bu işlem yalnızca yeni zamanlanmış ETL Job'larını durdurur. Diğer uygulamaların MongoDB'ye yazmasını otomatik olarak engellemez.

### 4.3. Restore işlemi

```bash
/usr/bin/time -p ./scripts/restore.sh backups/20261110T161624Z
```

Script önce arşivlerin SHA-256 checksum değerlerini doğrular.

Ardından kullanıcıdan şu onayı ister:

```text
Type RESTORE to continue:
```

Devam etmek için:

```text
RESTORE
```

girilmeli ve Enter'a basılmalıdır.

Script `sample_training` ve `github_etl` veritabanlarını sırasıyla geri yükler.

### 4.4. ETL CronJob'ını yeniden etkinleştirme

Restore ve veri doğrulaması tamamlandıktan sonra:

```bash
kubectl patch cronjob github-etl -n devops-case \
  -p '{"spec":{"suspend":false}}'
```

Ardından sistem durumu kontrol edilir:

```bash
kubectl get cronjob github-etl -n devops-case
kubectl get deployments -n devops-case
kubectl get pod mongodb-0 -n devops-case
```

## 5. Doğrulama / Verification

Backup ve restore işlemleri dört seviyede doğrulanır.

**1. Dosya bütünlüğü**

`SHA256SUMS` dosyası ile arşivlerin SHA-256 değerleri karşılaştırılır.

```bash
(
  cd backups/20261110T161624Z
  shasum -a 256 -c SHA256SUMS
)
```

Gerçek sonuç:

```text
sample_training.archive: OK
github_etl.archive: OK
```

**2. Veri kaybının doğrulanması**

Backup alındıktan sonra `sample_training.records` collection'ı silinmiştir.

Silme öncesinde 2 kayıt bulunmaktadır. `drop()` işlemi `true` döndürmüş, sonrasında kayıt sayısı 0 olmuştur.

MongoDB sorgusunda `Backup Test` kaydı için `null` sonucu alınmıştır.

React uygulamasındaki `Record List` sayfası yenilendiğinde kayıtların artık görüntülenmediği doğrulanmıştır.

**3. Restore işleminin sonucu**

`mongorestore` çıktısındaki başarılı ve başarısız belge sayıları kontrol edilir.

Gerçek test sonucu:

```text
sample_training: 3 documents restored, 0 failed
github_etl: 3 documents restored, 0 failed
Restore completed successfully.
```

Toplam 6 belge başarıyla geri yüklenmiştir.

Restore script'inin ölçülen toplam çalışma süresi:

```text
real 4,80
user 0,12
sys 0,06
```

**4. Kurtarılan verilerin doğrulanması**

Restore sonrasında MongoDB üzerinde `Backup Test` ve `Employee1` kayıtları yeniden sorgulanmıştır.

Kayıt sayıları:

```text
sample_training.records: 2
sample_training.backup_restore_test: 1
github_etl.repositories: 3
```

React uygulamasındaki `Record List` sayfası yeniden yüklenmiş ve `Backup Test` ile `Employee1` kayıtlarının tekrar görüntülendiği doğrulanmıştır.

Böylece verilerin hem MongoDB'de hem uygulama arayüzünde kurtarıldığı gösterilmiştir.

Bu kontrollerin tamamı 10 Kasım 2026 tarihli testte başarılı olmuştur.

## 6. Uçtan uca test sonucu / End-to-end test result

**Test tarihi:** 10 Kasım 2026  
**Test ortamı:** Yerel k3d Kubernetes cluster  
**Namespace:** `devops-case`  
**Backup:** `backups/20261110T161624Z`  
**Test kaydı:** `Backup Test`

Test, teknik case dokümanındaki altı aşamayı kapsayacak şekilde React uygulaması ve MongoDB birlikte kullanılarak gerçekleştirilmiştir.

| # | Test adımı | Gerçek sonuç | Kanıt |
| --- | --- | --- | --- |
| 1 | React arayüzünden kayıt oluşturma | `Backup Test` oluşturuldu, listede görüntülendi | [35](screenshots/35-backup-ui-record-created.png) |
| 2 | Backup oluşturma | İki arşiv oluşturuldu, SHA-256 kontrolü başarılı | [36](screenshots/36-backup-ui-created.png) |
| 3 | Collection silme | `sample_training.records.drop()` sonucu `true`, kayıt sayısı 2'den 0'a düştü | [37](screenshots/37-backup-records-dropped.png) |
| 4 | Veri kaybını doğrulama | React listesi boşaldı; MongoDB sorgusu `null`, kayıt sayısı 0 | [38](screenshots/38-backup-ui-data-lost.png), [39](screenshots/39-backup-db-data-lost.png) |
| 5 | Restore gerçekleştirme | Toplam 6 belge, 0 hata; script çalışma süresi 4,80 saniye | [40](screenshots/40-backup-restore-timed.png) |
| 6 | Kurtarılan veriyi doğrulama | `Backup Test` ve `Employee1` hem React arayüzünde hem MongoDB'de yeniden görüntülendi | [41](screenshots/41-backup-ui-recovered.png), [42](screenshots/42-backup-db-recovered.png) |

### 6.1. Test sonrası servis durumu

Restore ve veri doğrulaması tamamlandıktan sonra ETL CronJob'ı yeniden etkinleştirilmiştir.

Son Kubernetes kontrol sonuçları:

```text
github-etl: SUSPEND=False, ACTIVE=0
backend:    1/1 Ready
frontend:   1/1 Ready
mongodb-0:  1/1 Running, 0 restarts
```

### 6.2. Sonuç

**Backup ve restore testi başarılıdır.**

React arayüzünden oluşturulan kayıtların MongoDB collection'ının silinmesiyle kaybolduğu, restore işleminden sonra aynı kayıtların hem veritabanında hem React arayüzünde yeniden görüntülendiği doğrulanmıştır.

- İki MongoDB veritabanı başarıyla geri yüklenmiştir.
- Toplam 6 belge kurtarılmıştır.
- Başarısız restore edilen belge sayısı 0'dır.
- Restore script'inin ölçülen toplam çalışma süresi 4,80 saniyedir.
- Backend, frontend ve MongoDB servisleri test sonunda çalışır durumdadır.

Uçtan uca kurtarma süresi ayrıca ölçülmediği için 15 dakikalık RTO hedefinin sağlandığı kesin olarak raporlanmamıştır.

Ekran görüntülerinin tamamı `TESLIM_KANITLARI.md` dosyasında da listelenmiştir.


## 7. Bilinen sınırlamalar / Known limitations

- Backup işlemi manuel olarak çalıştırılır; otomatik zamanlama uygulanmamıştır.
- Otomatik retention ve eski backup dosyalarını temizleme mekanizması bulunmamaktadır.
- Backup dosyaları yerel bilgisayarda saklanır; bağımsız off-site koruma yoktur.
- Backup dosyaları için şifreli uzak object storage kullanılmamaktadır.
- Dosya izinleri sınırlandırılmıştır ancak arşiv düzeyinde ayrıca şifreleme uygulanmamıştır.
- MongoDB tek replica olarak çalışmaktadır; otomatik failover bulunmamaktadır.
- Point-in-time recovery ve oplog tabanlı kurtarma uygulanmamıştır.
- `mongorestore --drop` işlemi, yedek sonrasında yapılan değişiklikleri geri alabilir.
- Restore işlemi sırasında ETL CronJob'ı manuel olarak durdurulmalıdır.
- ETL CronJob'ının durdurulması diğer uygulama yazmalarını engellemez.
- Restore script'inin toplam çalışma süresi 4,80 saniye olarak ölçülmüştür. Ancak veri kaybından uygulamanın tamamen doğrulanmasına kadar geçen uçtan uca kurtarma süresi ölçülmemiştir.
- Önerilen RPO, RTO ve retention hedefleri otomatik olarak uygulanmamaktadır.

Bu sınırlamalar nedeniyle mevcut çözüm, yerel Kubernetes ortamında doğrulanmış manuel backup/restore mekanizmasıdır; tam otomatik bir production disaster recovery sistemi değildir.