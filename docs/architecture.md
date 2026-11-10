# Sistem Mimarisi

Bu doküman, MERN uygulamasının, GitHub ETL iş yükünün ve monitoring mekanizmasının yerel Kubernetes ortamındaki çalışma zamanı (runtime) mimarisini açıklar. Sistem bileşenleri, ağ bağlantıları, dış erişim noktaları, veri akışları ve mimari tercihlerin gerekçeleri ele alınır. CI/CD ve container image yayınlama süreçleri `README.md` dosyasında açıklanmıştır.

## 1. Hedef Ortam ve Mimari Diyagram

| Özellik | Yapılandırma |
| --- | --- |
| Çalışma ortamı | Docker Desktop üzerinde yerel k3d Kubernetes cluster'ı |
| Kubernetes context | `k3d-devops-case` |
| Namespace | `devops-case` |
| Uygulama girişi | `frontend` NodePort Service, `30080/TCP` |
| Backend erişimi | `case-backend` ClusterIP Service, `5050/TCP` |
| Veritabanı erişimi | `mongodb-service` headless Service, `27017/TCP` |
| Veritabanı | MongoDB 7, tek replikalı StatefulSet |
| Kalıcı depolama | `mongo-data` PersistentVolumeClaim, `2Gi` |

**[Mimari diyagram (PDF)](architecture.pdf)**

**[Düzenlenebilir mimari diyagramı (Draw.io)](architecture.drawio)**

PDF, mimarinin tek sayfalık görsel sunumudur. Draw.io dosyası kutuların, bağlantıların ve açıklamaların düzenlenebildiği kaynak dosyadır. Diyagram, kullanıcı isteği ve yanıtını, zamanlanmış GitHub ETL işini, monitoring ve alarm akışını ayrı bölümlerde gösterir. Kubernetes cluster sınırının dışında kalan tarayıcı, GitHub REST API ve Slack Incoming Webhook ayrıca belirtilmiştir.

## 2. Kullanıcı İsteğinin İşlenmesi

Uygulamaya erişim, Kubernetes üzerinde `frontend` adıyla tanımlanan `NodePort` Service üzerinden sağlanır. Kullanıcının tarayıcısından gelen HTTP isteği, cluster'a açılan `30080` numaralı porta ulaşır. Bu Service trafiği, `8080` portunda çalışan Nginx sürecini barındıran frontend Pod'una iletir. Frontend, Kubernetes Deployment tarafından yönetilen durumsuz bir iş yüküdür.

Nginx iki görev üstlenir. İlk olarak React uygulamasının derlenmiş statik dosyalarını tarayıcıya sunar. İkinci olarak React tarafından `/api/` önekiyle gönderilen istekleri backend'e yönlendiren bir reverse proxy görevi görür. Böylece tarayıcının backend için ayrı bir dış erişim adresi kullanmasına gerek kalmaz. Mevcut Nginx yapılandırması `/api/` önekini kaldırarak isteği `case-backend:5050` adresine iletir. Örneğin `/api/healthcheck/ready` isteği backend'deki `/healthcheck/ready` endpoint'ine karşılık gelir.

`case-backend` Service, `ClusterIP` türündedir ve yalnızca cluster içi servis erişimi sağlar. Kubernetes bu Service üzerinden gelen isteği backend Deployment'ının yönettiği Pod'a aktarır. Pod içinde `5050` portunda çalışan Node.js/Express uygulaması HTTP isteğini karşılar, ilgili route üzerinden işlemi yürütür ve gerektiğinde MongoDB'ye erişir.

Backend, MongoDB ile `mongodb-service` isimli headless Service üzerinden iletişim kurar. Bu Service, `mongodb-0` Pod'una Kubernetes DNS aracılığıyla erişilmesini sağlar. MongoDB, `mongodb` StatefulSet tarafından yönetilir; kullanıcı kayıtları `sample_training.records` koleksiyonunda, ETL verileri ise `github_etl` veritabanında saklanır. Veritabanı işleminin sonucu Express tarafından HTTP yanıtına dönüştürülür ve Nginx üzerinden tarayıcıya iletilir.

### 2.1. Örnek senaryo: Yeni çalışan kaydı oluşturma

Kullanıcı React arayüzündeki kayıt formunu doldurup gönderdiğinde tarayıcı bir API isteği oluşturur. İstek, frontend NodePort Service aracılığıyla Nginx'e ulaşır. Nginx, `/api/` ile başlayan isteği reverse proxy yapılandırması üzerinden `case-backend` Service'e aktarır. Backend Pod'undaki Express uygulaması ilgili kayıt oluşturma işlemini yürütür ve MongoDB sürücüsüyle `sample_training.records` koleksiyonuna yeni bir belge ekler.

MongoDB işlem sonucunu backend'e döndürür. Backend uygun HTTP yanıtını üretir ve Nginx bu yanıtı tarayıcıya iletir. Kullanıcı kayıt listesini yeniden görüntülediğinde frontend, API üzerinden güncel kayıtları ister; backend de verileri MongoDB'den okuyarak React arayüzüne sunar. Kayıt oluşturma, listeleme, düzenleme ve silme işlemleri aynı temel ağ ve uygulama katmanlarını kullanır.

Bu tasarımda backend ve MongoDB doğrudan dış dünyaya açılmaz. Ancak `ClusterIP` ve headless Service kullanımı tek başına ağ izolasyonu anlamına gelmez; bu sürümde `NetworkPolicy` uygulanmamıştır.

### 2.2. Service türleri ve dış erişim noktaları

| Bileşen | Service türü | Port | Görevi |
| --- | --- | --- | --- |
| `frontend` | `NodePort` | Dış port `30080`, hedef `8080` | Tarayıcı trafiğini Nginx'e iletir. |
| `case-backend` | `ClusterIP` | `5050` | Frontend reverse proxy'sinden gelen API isteklerini backend Pod'una iletir. |
| `mongodb-service` | Headless (`clusterIP: None`) | `27017` | Backend ve ETL Pod'larının MongoDB Pod'una DNS üzerinden erişmesini sağlar. |

Uygulamaya yönelik dış erişim noktası `frontend` NodePort Service'tir. Yerel bilgisayardan erişilebilmesi için k3d cluster'ında uygun port eşlemesinin bulunması gerekir. GitHub REST API ve Slack Incoming Webhook ise cluster'ın dışındaki, ilgili iş yüklerinin HTTPS ile eriştiği servislerdir.

## 3. Zamanlanmış GitHub ETL İş Yükü

`github-etl` CronJob, UTC saat diliminde her saat başında (`0 * * * *`) bir Kubernetes Job oluşturur. Job içinde başlatılan Python Pod'u GitHub REST API'ye HTTPS isteği gönderir, repository verilerini alır ve MongoDB'deki `github_etl.repositories` koleksiyonuna kaydeder. ETL, frontend ve backend'in HTTP isteklerinden bağımsız çalışır.

Repository kayıtları `github_id` alanı üzerinden eşleştirilir. Benzersiz indeks ve `upsert` işlemi sayesinde daha önce alınmış bir repository tekrar geldiğinde aynı kayıt güncellenir; gereksiz kopya oluşturulmaz. `concurrencyPolicy: Forbid`, aynı CronJob'a ait işlerin birbiriyle çakışmasını önlemek için kullanılır.

ETL Pod'u MongoDB'ye, backend'in de kullandığı cluster içi `mongodb-service` üzerinden erişir. GitHub API ise cluster sınırının dışındadır. Diyagramda bu iki farklı bağlantı ayrı gösterilmiştir.

## 4. Monitoring ve Slack Alarm Akışı

`monitoring-check` CronJob her dakika (`* * * * *`) bir Job başlatır. Monitoring Pod'u, `check-health.sh` ve `evaluate_etl.py` aracılığıyla backend Deployment'ının kullanılabilirliğini ve ETL CronJob/Job durumunu kontrol eder. Bu kontroller için Kubernetes API üzerinden Deployment, Job ve CronJob kaynakları okunur.

Monitoring mekanizması `BACKEND_UNAVAILABLE`, `ETL_JOB_FAILED`, `ETL_OVERDUE`, `ETL_NO_SUCCESS` ve `ETL_SUSPENDED` durumlarını değerlendirir. Alarmın aktiflik bilgisi ve son bildirim zamanı `monitoring-state` ConfigMap'inde tutulur. Aynı alarma ait tekrar bildirimler 900 saniyelik (15 dakika) bekleme süresine tabidir. Sorun düzeldiğinde Slack Incoming Webhook aracılığıyla `RESOLVED` bildirimi gönderilir.

Monitoring Pod'u, `monitoring-sa` ServiceAccount ile çalışır. RBAC yapılandırması, gerekli Kubernetes kaynaklarını okumak ve ilgili alarm durumunu saklayan ConfigMap üzerinde işlem yapmak üzere sınırlandırılmıştır. Slack webhook adresi Kubernetes Secret üzerinden sağlanır; gizli değerler diyagramda ve bu dokümanda gösterilmez.

Bu mekanizma cluster içinden çalışır. Cluster'ın tamamının erişilemez olduğu bir durumda monitoring Job'ı da çalışamayabileceğinden bağımsız, cluster dışı bir izleme hizmetinin yerini tutmaz.

## 5. Kubernetes Bileşenleri ve Kalıcı Veri

| Bileşen | Kubernetes kaynağı | Seçilme nedeni |
| --- | --- | --- |
| Frontend | Deployment, 1 replika | Nginx tarafından sunulan statik uygulama durumsuzdur ve Pod yeniden oluşturulabilir. |
| Backend | Deployment, 1 replika | API durumsuz çalışır; kalıcı uygulama verileri MongoDB'de tutulur. |
| MongoDB | StatefulSet, 1 replika | Sabit Pod kimliği ve kalıcı disk gerektirir. |
| GitHub ETL | CronJob ve Job | Saatlik, tamamlandığında sonlanan veri toplama işlemidir. |
| Monitoring | CronJob ve Job | Her dakika çalışan kısa süreli sağlık ve alarm kontrolüdür. |

MongoDB Pod'u, `mongo-data` adlı PersistentVolumeClaim aracılığıyla `local-path` StorageClass üzerinde `2Gi` disk alanı kullanır. Böylece uygulama verileri MongoDB container'ının geçici dosya sisteminden ayrı tutulur ve Pod'un yeniden oluşturulmasında korunabilir. Bununla birlikte tek replikalı MongoDB ile yerel disk kullanımı, otomatik failover veya farklı makine arızalarına karşı yüksek erişilebilirlik sağlamaz.

Backend, `/healthcheck` endpoint'ini liveness ve `/healthcheck/ready` endpoint'ini readiness amacıyla kullanır. Readiness kontrolü MongoDB erişimini de değerlendirir. Veritabanı bağlantısı kaybolduğunda backend süreci çalışmaya devam etse bile readiness isteği başarısız olabilir. Kubernetes, hazır olmayan Pod'u Service'in kullanılabilir endpoint'lerinden çıkarabilir; bu davranış kesintisiz hizmet garantisi değildir.

## 6. Backup, Restore ve Kurtarma Doğrulaması

MongoDB için `scripts/backup.sh` ve `scripts/restore.sh` kullanılarak manuel yedekleme ve geri yükleme uygulanmıştır. `sample_training` ve `github_etl` veritabanları ayrı arşiv dosyalarına kaydedilir; `SHA256SUMS` dosyası ile arşiv bütünlüğü doğrulanır. Yedekler Kubernetes cluster'ının dışında, script'in çalıştırıldığı yerel bilgisayarın `backups/` dizininde saklanır.

Core 8 kapsamındaki gerçek kurtarma testinde React arayüzünden oluşturulan kayıtlar yedeklenmiş, MongoDB'deki `sample_training.records` koleksiyonu silinerek veri kaybı hem veritabanında hem arayüzde gözlemlenmiştir. Restore sonrasında aynı kayıtlar tekrar görüntülenmiş ve toplam altı belgenin geri yüklendiği doğrulanmıştır.

Advanced 7 kapsamında eklenen `scripts/verify-backup.sh`, arşivlerin geri yüklenebilirliğini mevcut MongoDB'yi değiştirmeden test eder. Script, geçici ve ağ erişimi kapalı bir MongoDB container'ı oluşturur, iki veritabanı arşivini bu ortama geri yükler, collection ve belge sayılarını kontrol eder ve geçici container'ı kaldırır. Test başarıyla tamamlanmıştır.

Yedekleme halen manuel başlatılır; otomatik zamanlama, uzak ve bağımsız yedek depolama, otomatik retention ve point-in-time recovery uygulanmamıştır. Adımlar ve test kanıtları [`backup-restore.md`](backup-restore.md) dosyasında bulunur. Backup işlemleri çalışma zamanı mimari diyagramının ana trafik akışlarına dahil edilmemiştir.

## 7. Yapılandırma, Güvenlik ve Mimari Sınırlamalar

Gizli olmayan yapılandırmalar `app-config` ConfigMap üzerinden, MongoDB bağlantı bilgileri ve Slack webhook adresi ise Kubernetes Secret üzerinden sağlanır. Backend ve ETL için ayrı MongoDB bağlantı bilgileri kullanılır. Monitoring Pod'unun Kubernetes API erişimi ServiceAccount ve RBAC ile sınırlandırılmıştır.

Mevcut çalışma ortamı yerel geliştirme, dağıtım ve doğrulama için hazırlanmıştır. Frontend NodePort erişimi düz HTTP kullanır; TLS terminasyonu ve Ingress Controller uygulanmamıştır. `NetworkPolicy`, HPA, çok düğümlü yüksek erişilebilirlik, MongoDB replica set ve otomatik failover da bu sürümün kapsamında değildir.

Backend ve frontend image'ları ile Python ETL image'ı CI içinde Trivy ile taranır ve CycloneDX SBOM raporları üretilir. Bu kontrol, bilinen güvenlik açıklarının raporlanmasını sağlar; mevcut uygulamada tarama bulguları image yayınını otomatik olarak durdurmaz. CI güvenlik kontrolleri, runtime diyagramı yerine `README.md` içinde açıklanmıştır.

Monitoring için Slack tabanlı alarm ve durum düzelme bildirimleri uygulanmıştır. Merkezi log toplama ve Prometheus/Grafana tabanlı bir gözlemleme sistemi bu sürümde bulunmaz.

## 8. İlgili Dokümanlar

- [`README.md`](../README.md): Kurulum, CI/CD, container image'ları, deployment, rollback ve güvenlik kontrolleri.
- [`findings.md`](findings.md): Başlangıç sorunları, uygulanan iyileştirmeler ve kalan riskler.
- [`backup-restore.md`](backup-restore.md): MongoDB backup, restore ve izole kurtarma doğrulaması.
- [`TESLIM_KANITLARI.md`](../TESLIM_KANITLARI.md): Çalışan sistemin ekran görüntüleri ve doğrulama kanıtları.

**Düzenlenebilir diyagram kaynağı:** [`architecture.drawio`](architecture.drawio).
