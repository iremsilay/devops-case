# DEVOPS TEKNİK CASE — MERN UYGULAMASI VE PYTHON ETL

## 1. PROJE HAKKINDA

Bu proje, sağlanan MERN uygulamasının ve Python ETL iş yükünün production-readiness açısından incelenmesi, kritik sorunlarının iyileştirilmesi ve tekrarlanabilir bir çalışma ortamına taşınması için hazırlanmış bir DevOps teknik değerlendirme çalışmasıdır.

Çözüm iki çalışma yolu sunar: Docker Compose ile yerel doğrulama ve Docker Desktop üzerinde k3d kullanılarak oluşturulan yerel Kubernetes cluster'ında dağıtım. Nihai orkestrasyon ortamı Kubernetes'tir. Public cloud veya internet üzerinden erişilebilir bir production ortamı kurulmamıştır.

MERN arayüzü çalışan kayıtlarını oluşturma, listeleme, güncelleme ve silme işlemlerini destekler. Ayrı Python ETL uygulaması, belirtilen GitHub kullanıcısının repository bilgilerini GitHub API üzerinden alıp MongoDB'ye kaydeder. ETL'nin yeniden çalışması mevcut repository kayıtlarını günceller; aynı GitHub repository kimliğine sahip ikinci bir kayıt üretmez.

Bunlara ek olarak GitHub Actions CI, container image üretimi, yerel kontrollü deployment ve rollback, MongoDB backup/restore, Kubernetes tabanlı monitoring ve Slack bildirimleri uygulanmıştır.

Bu çalışma bir production ortamının bire bir karşılığı olarak sunulmaz. Kurulan ortamın güvenlik, erişilebilirlik ve felaket kurtarma sınırlamaları bu belgenin sonunda açıklanmıştır.

Repository: `https://github.com/iremsilay/devops-case`

## 2. TEKNOLOJİLER VE BİLEŞENLER

**Frontend:** React, JavaScript, Nginx. React uygulaması Docker build sırasında derlenir; oluşan statik içerik son container'da Nginx üzerinden port 8080'de sunulur.

**Backend:** Node.js 22, Express, MongoDB sürücüsü. HTTP API port 5050'de çalışır. `/record` altında CRUD, `/healthcheck` altında liveness ve `/healthcheck/ready` altında MongoDB bağlantısını da değerlendiren readiness endpoint'i bulunur.

**Veritabanı:** MongoDB 7. MERN kayıtları sample_training veritabanının records collection'ında, GitHub ETL kayıtları github_etl veritabanının repositories collection'ında tutulur.

**ETL:** Python 3.11, Requests ve PyMongo. GitHub API'den repository verilerini çeker; `github_id` benzersiz indeksini kullanarak upsert işlemi gerçekleştirir.

**Container ve yerel ortam:** Docker, Docker Compose, Docker Desktop, k3d.

**Orkestrasyon:** Kubernetes Deployment, StatefulSet, Service, ConfigMap, Secret, Job ve CronJob. MongoDB için PersistentVolumeClaim kullanılır.

**CI ve image dağıtımı:** GitHub Actions, Docker Buildx, GitHub Container Registry (GHCR). Backend, frontend ve ETL image'ları hazırlanır; main branch push'larında GHCR'ye yayınlanır.

**Monitoring:** Bash, Python, kubectl, Kubernetes CronJob, ConfigMap tabanlı alarm durumu, Slack Incoming Webhook.

**Backup ve restore:** mongodump, mongorestore, shell scriptleri, SHA-256 checksum doğrulaması.

## 3. MİMARİ VE TRAFİK AKIŞI

Kubernetes namespace adı: devops-case.

**Kullanıcı istekleri Kubernetes üzerinde aşağıdaki yolu izler:**

Kullanıcı -> Tarayıcı -> Frontend NodePort Service (30080) -> Frontend Pod (Nginx, 8080) -> Nginx Reverse Proxy (`/api`) -> `case-backend` ClusterIP Service (5050) -> Backend Pod (Node.js, 5050) -> `mongodb-service` (Headless Service, 27017) -> MongoDB StatefulSet Pod (`mongodb-0`).

Frontend, kullanıcının tarayıcısına React uygulamasının statik dosyalarını sunar. Tarayıcıdan gönderilen `/api` istekleri Nginx tarafından cluster içindeki `case-backend` servisine yönlendirilir. Backend, MongoDB işlemleri için headless `mongodb-service` üzerinden MongoDB StatefulSet Pod'una bağlanır.

Frontend NodePort Service, cluster dışından uygulamaya erişim noktasıdır. Backend ClusterIP Service ve MongoDB headless Service yalnızca cluster içi erişim için yapılandırılmıştır.

Bu mimari, Ingress Controller veya TLS terminasyonu (HTTPS) içermez; doğrudan NodePort üzerinden düz HTTP yayını yapar. Yerel bilgisayardan erişim için k3d cluster'ında uygun host port mapping tanımlanması gerekir.

Python ETL, kullanıcı isteğinden bağımsız çalışır: `github-etl` CronJob -> ETL Job -> GitHub REST API -> MongoDB `github_etl.repositories` collection'ı. CronJob her saat başında UTC zaman diliminde çalışır (0 * * * *).

Monitoring de bağımsızdır: `monitoring-check` CronJob -> backend ve ETL Kubernetes durumlarının okunması -> alarm state'inin kontrolü -> gerekirse Slack webhook bildirimi. CronJob her dakika çalışır.

**Kubernetes servisleri:**

- frontend: NodePort, servis portu 8080, nodePort 30080; dış erişim için ayrılmış tek uygulama servisi.
- `case-backend`: ClusterIP, port 5050; cluster içinden erişilir.
- `mongodb-service`: headless Service, port 27017; MongoDB StatefulSet için sabit ağ kimliği ve iç erişim sağlar.

Mimari çizim ayrıca `docs/architecture.md` dosyasında hazırlanacaktır.

## 4. REPOSITORY YAPISI

mern-project/client/: React kaynak kodu, Cypress testleri, frontend Dockerfile ve nginx.conf.

mern-project/server/: Express API, MongoDB bağlantısı, sağlık kontrolleri ve backend Dockerfile.

python-project/: `ETL.py`, `requirements.txt`, ETL Dockerfile ve ETL'ye özel açıklama.

monitoring/: check-health.sh, evaluate_etl.py ve monitoring Dockerfile.

kubernetes/: namespace, genel yapılandırma ve backend/frontend/MongoDB/ETL/monitoring kaynak manifestleri.

`.github/workflows/ci.yml`: GitHub Actions doğrulama, E2E ve image build/publish süreci.

`scripts/deploy-local.sh`: GHCR image tag'iyle yerel Kubernetes deployment ve hata durumunda rollback.

`scripts/backup.sh`: sample_training ve github_etl veritabanlarını arşiv olarak yedekleme.

`scripts/restore.sh`: checksum doğrulamalı, onay gerektiren MongoDB geri yükleme.

`tests/test_etl_recovery.py`: ETL başarısızlık ve iyileşme analizinin birim testleri.

`docker-compose.yml`: Yerel container ortamı ve isteğe bağlı tek seferlik ETL çalıştırması.

.env.example: Docker Compose örnek ortam değişkenleri.

`docs/findings.md` ve `docs/findings_en.md`: Başlangıç riskleri, uygulanan iyileştirmeler ve kapsam sınırları.

`docs/backup-restore.md`: Backup/restore runbook; teslimden önce gerçek ölçümler ve kanıt bağlantılarıyla doldurulacaktır.

`docs/screenshots/`: Zorunlu çalışma kanıtlarının yerleştirileceği klasör.

`TESLIM_KANITLARI.md` ve `SUBMISSION_EVIDENCE.md`: Kanıt görsellerinin açıklamaları.

`CASE_SONU_CEVAPLARI.md` ve `CASE_END_ANSWERS.md`: Case sonu teknik sorularının cevapları.

Git tarafından yok sayılan node_modules, derleme çıktıları, sanal ortamlar, gerçek .env/Secret dosyaları ve backups/ klasörü kaynak tesliminin parçası değildir.

## 5. ÖN KOŞULLAR

**Yerel kurulum için:**

- Git
- Docker Desktop ve Docker Compose eklentisi
- Docker Desktop çalışır durumda olmalı
- Kubernetes kurulumu için kubectl ve k3d
- GitHub repository'lerini okuyabilen internet bağlantısı

Lokal Node.js geliştirme ve Cypress testleri için Node.js 22 ve npm gerekir. Python ETL'yi Docker dışında çalıştırmak veya birim testleri yerelde yürütmek için Python 3.11 uygundur.

macOS ve Docker Desktop üzerinde doğrulama yapılmıştır. Komutlar macOS/Linux shell kullanımına göre verilmiştir. Farklı işletim sistemlerinde bazı yardımcı komutlar değişebilir.

**İlk adım:**

```bash
git clone https://github.com/iremsilay/devops-case.git
cd devops-case
```

## 6. HIZLI BAŞLANGIÇ — DOCKER COMPOSE

Docker Compose, tüm uygulamayı lokal container ağında doğrulamak için en kolay yoldur. Kubernetes'in yerini alan nihai deployment olarak değerlendirilmemelidir.

### 6.1 Ortam dosyasını oluşturma

**Proje kökünde:**

```bash
cp .env.example .env
```

**.env içindeki değerler:**

```dotenv
COMPOSE_MONGO_URI=mongodb://mongodb:27017
MONGO_DB=github_etl
MONGO_COLLECTION=repositories
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=
FRONTEND_PORT=8081
```

`GITHUB_USERNAME` değerini test edilecek GitHub hesabıyla değiştir. Token olmadan public repository bilgileri alınabilir; GitHub API rate limitleri uygulanır. Gerçek token gerekiyorsa yalnızca yerel .env veya güvenli secret mekanizmasında tut; Git'e ekleme.

### 6.2 Uygulamayı başlatma

```bash
docker compose up -d --build
```

Bu işlem MongoDB, backend ve frontend'i çalıştırır. Compose, MongoDB healthcheck ve backend readiness sonucunu bekleyerek servis bağımlılıklarını değerlendirir. ETL servisi profil altında tanımlandığı için kendiliğinden başlamaz.

### 6.3 Servisleri kontrol etme

```bash
docker compose ps
docker compose logs --tail=100 backend
docker compose logs --tail=100 frontend
```

Tarayıcı: `http://localhost:8081`

`FRONTEND_PORT` değiştirilmişse tarayıcı portu da değişir. Compose port eşlemesi yalnızca 127.0.0.1 arayüzüne bağlıdır.

**API kontrolü, Nginx proxy üzerinden:**

```bash
curl -i http://localhost:8081/api/healthcheck
curl -i http://localhost:8081/api/healthcheck/ready
```

Beklenen sağlıklı durumda iki endpoint de HTTP 200 döndürür. Readiness yanıtında READY değeri bulunur.

### 6.4 ETL'yi tek sefer çalıştırma

```bash
docker compose --profile etl run --rm etl
```

İşlem repository bilgilerini alır, MongoDB'ye yazar ve tamamlandığında çıkar. Bir kez daha çalıştırıldığında aynı `github_id` kayıtları güncellenir; tekrar insert edilmez.

ETL çıktısında fetched, inserted, updated ve unchanged sayaçları gösterilir. Bu Compose komutu saatlik bir scheduler kurmaz; saatlik planlama Kubernetes CronJob ile gerçekleştirilir.

### 6.5 Temizlik

```bash
docker compose down
```

Bu komut container ve ağları durdurur, named MongoDB volume'unu korur. `docker compose down -v` komutu veritabanı volume'unu siler; yalnızca veri kaybı isteniyorsa kullanılmalıdır.

## 7. KUBERNETES ORTAMI VE İLK KURULUM

Nihai test ortamı, Docker Desktop üzerinde yerel k3d cluster'ı olan devops-case'tir. kubectl context adı `k3d-devops-case`, Kubernetes namespace adı devops-case olarak seçilmiştir.

Kurulum, ilk defa boş cluster hazırlama ile mevcut çalışan cluster'ı güncelleme işlemlerinin farklı olduğunu dikkate alır. Özellikle Secret'lar ve alarm state'i için kullanılan ConfigMap gelişigüzel yeniden uygulanmamalıdır.

### 7.1 Cluster ve context kontrolü

```bash
k3d cluster list
kubectl config current-context
kubectl get nodes
```

Bu projedeki deploy-local.sh yalnızca `k3d-devops-case` context'inde çalışacak şekilde hazırlanmıştır. Yeni bir cluster kurulurken devops-case adı kullanılmalıdır. k3d'nin host port mapping'i kurulum sırasında yapılandırılır. Örneğin frontend NodePort 30080 için host üzerinde seçilen bir port eşlemesi olmadan tarayıcıdan erişim beklenmemelidir.

**Yeni cluster kurulumu için örnek (henüz mevcut cluster üzerinde çalıştırılmamalı):**

```bash
k3d cluster create devops-case --port '127.0.0.1:8081:30080@loadbalancer'
```

Bu satır örnek kurulumdur; gerçek mevcut cluster'ın hangi port eşlemesiyle oluşturulduğu k3d yapılandırmasından doğrulanmalıdır. Mevcut cluster'ı silerek yeniden oluşturmak MongoDB verilerini kaybettirebilir.

### 7.2 Image hazırlığı

**Repository'deki ilk Kubernetes manifestleri yerel Docker image etiketlerini kullanır:**

- `case-backend:1.0`
- `case-frontend:1.0`
- `case-etl:1.0`
- `case-monitoring:1.1`

**Proje kökünden:**

```bash
docker build -t case-backend:1.0 ./mern-project/server
docker build -t case-frontend:1.0 ./mern-project/client
docker build -t case-etl:1.0 ./python-project
docker build -t case-monitoring:1.1 ./monitoring
```

**Image'ları k3d cluster'ına aktar:**

```bash
k3d image import case-backend:1.0 case-frontend:1.0 case-etl:1.0 case-monitoring:1.1 -c devops-case
```

Yerel geliştirme ve release süreçleri iki farklı image yönetimi yaklaşımı kullanır.

**Yerel geliştirme:** Repository içindeki varsayılan Kubernetes manifestleri `case-backend:1.0`, `case-frontend:1.0` ve `case-etl:1.0` etiketlerini kullanır. Image'lar yerel Docker ortamında oluşturulur ve `k3d image import` ile cluster'a aktarılır. Bu yöntem geliştirme ve ilk kurulum testlerini hızlandırır.

**Release:** GitHub Actions başarılı kontrollerden sonra backend, frontend ve ETL image'larını GHCR'ye `sha-<commit-hash>` etiketiyle yayınlar. `scripts/deploy-local.sh`, belirtilen SHA etiketine ait image'ları kullanarak çalışan Kubernetes kaynaklarının image referanslarını `kubectl set image` komutuyla günceller.

Deployment script'i manifest dosyalarını değiştirmez. Yeni image referansları Kubernetes API üzerinden mevcut Deployment ve CronJob kaynaklarına uygulanır. Böylece repository'deki varsayılan YAML dosyaları yerel image etiketlerini korurken çalışan cluster GHCR image'larını kullanabilir.

Monitoring image'ı bu release script'inin kapsamında değildir ve ayrı yönetilir.

Kubernetes manifestleri yeniden kubectl apply ile uygulandığında image referansları varsayılan yerel etiketlere dönebilir. Bu nedenle release sonrasında manifestlerin yeniden uygulanması kontrollü yapılmalıdır.

Image'lar cluster'da bulunmadığında veya GHCR üzerinden çekilemediğinde Pod'lar `ImagePullBackOff` durumuna geçebilir.

### 7.3 Namespace ve genel ConfigMap

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
```

Genel `app-config` ConfigMap'inde GitHub kullanıcı adı ve ETL collection bilgileri bulunur. Test kullanıcısı değiştirilecekse `GITHUB_USERNAME` değeri güncellenmelidir.

### 7.4 Kubernetes Secret hazırlığı

Gerçek parolaları ve bağlantı URI'lerini repository içine yazma. Aşağıdaki Secret'lar mevcut manifestlerin bağımlılıklarıdır:

- `mongodb-auth`: MongoDB root ve uygulama kullanıcıları için başlangıç kullanıcı/parola ortam değişkenleri.
- `backend-mongo-uri`: `ATLAS_URI` anahtarı; sample_training üzerinde yetkili backend kullanıcısının bağlantı URI'si.
- `etl-mongo-uri`: `ATLAS_URI` anahtarı; github_etl üzerinde yetkili ETL kullanıcısının bağlantı URI'si.
- `monitoring-slack-webhook`: `SLACK_WEBHOOK_URL` anahtarı.

MongoDB uygulama kullanıcıları başlangıçta `init-mongo.js` tarafından oluşturulur. Script aşağıdaki değişkenleri kullanır:

`MONGO_BACKEND_USERNAME`, `MONGO_BACKEND_PASSWORD`,

`MONGO_ETL_USERNAME`, MONGO_ETL_PASSWORD.

MongoDB resmi image'ının root hesabı için ayrıca `MONGO_INITDB_ROOT_USERNAME` ve `MONGO_INITDB_ROOT_PASSWORD` gerekir.

**Yerel, Git tarafından yok sayılan bir env dosyası hazırlanıp aşağıdaki komutla Secret oluşturulabilir:**

```bash
kubectl create secret generic mongodb-auth -n devops-case --from-env-file=kubernetes/secrets/mongodb.env
```
**Mimari not:** Bu projede yerel Kubernetes ortamının kurulumu için Secret değerleri Git tarafından takip edilmeyen .env dosyalarından manuel olarak oluşturulmuştur. Bu yaklaşım yerel geliştirme ve teknik değerlendirme ortamı için tercih edilmiştir.

Gerçek production ortamında ise AWS Secrets Manager, HashiCorp Vault veya External Secrets Operator (ESO) gibi merkezi secret yönetim çözümleri kullanılmalıdır. Bu sistemler secret değerlerinin kontrollü dağıtımını, erişim yönetimini ve rotasyon süreçlerini destekler.

Mevcut çözümde otomatik secret rotasyonu uygulanmamıştır. Secret değerlerinin değiştirilmesi ve ilgili Pod'ların yeni değerleri kullanacak şekilde güncellenmesi ayrıca yönetilmelidir.

Bu örnek dosya Git'te bulunmamalıdır ve yukarıdaki altı değişkeni içermelidir. Aynı yöntemle `backend-mongo-uri`, `etl-mongo-uri` ve `monitoring-slack-webhook` Secret'ları ilgili anahtarlarla güvenli biçimde oluşturulmalıdır. MongoDB parola içeren URI'lerde özel karakterler gerekiyorsa URL encoding uygulanmalıdır. Gizli bilgileri terminal çıktılarına, ekran görüntülerine veya shell history'ye yazmamaya dikkat edilmelidir.

**Önemli:** Secret isimlerinin varlığı tek başına doğru yetkilendirmeyi garanti etmez. Backend ve ETL kullanıcılarının yalnızca kendi veritabanlarına erişmesi amaçlanmıştır.

### 7.5 MongoDB init ConfigMap, StatefulSet ve Service

**İlk boş veritabanında uygulama kullanıcılarını oluşturacak ConfigMap'i yükle:**

```bash
kubectl create configmap mongodb-init-script -n devops-case --from-file=init-mongo.js=kubernetes/mongodb/init-mongo.js
```

**Ardından:**

```bash
kubectl apply -f kubernetes/mongodb/service.yaml
kubectl apply -f kubernetes/mongodb/statefulset.yaml
kubectl rollout status statefulset/mongodb -n devops-case --timeout=180s
```

MongoDB, `mongodb-0` Pod'unda ve `mongo-data` PVC'sinde çalışır. Init script yalnızca boş verinin ilk oluşturulduğu sırada çalışır. Var olan PVC üzerine tekrar deploy yapmak kullanıcıları yeniden oluşturmaz. Secret değiştirildiğinde uygulama kullanıcı parolaları kendiliğinden güncellenmeyebilir; parola rotasyonu ayrıca planlanmalıdır.

### 7.6 Frontend, backend ve ETL kaynakları

```bash
kubectl apply -f kubernetes/backend/service.yaml
kubectl apply -f kubernetes/backend/deployment.yaml
kubectl apply -f kubernetes/frontend/service.yaml
kubectl apply -f kubernetes/frontend/deployment.yaml
kubectl apply -f kubernetes/etl/cronjob.yaml
```

```bash
kubectl rollout status deployment/backend -n devops-case --timeout=180s
kubectl rollout status deployment/frontend -n devops-case --timeout=180s
kubectl get deployments,services,cronjobs -n devops-case
```

Kubernetes manifestlerinde backend ve frontend için birer replica, MongoDB için tek StatefulSet replica'sı tanımlanmıştır. Bu, yüksek erişilebilirlik mimarisi değildir.

### 7.7 Monitoring kaynakları

Monitoring için ServiceAccount, sınırlı RBAC, script ConfigMap'i, durum ConfigMap'i ve CronJob gereklidir.

**İlk kurulumda:**

```bash
kubectl apply -f kubernetes/monitoring/serviceaccount.yaml
kubectl apply -f kubernetes/monitoring/role.yaml
kubectl apply -f kubernetes/monitoring/rolebinding.yaml
kubectl apply -f kubernetes/monitoring/configmap.yaml
kubectl apply -f kubernetes/monitoring/state-configmap.yaml
kubectl apply -f kubernetes/monitoring/cronjob.yaml
```

Uyarı: state-configmap.yaml başlangıç değerlerini içerir. Monitoring çalışmaya başladıktan sonra bunu tekrar uygulamak, aktif alarm durumunu sıfırlayabilir. Mevcut bir cluster'da tüm monitoring klasörünü körlemesine tekrar apply etme. Monitoring script değişiklikleri de configmap.yaml içindeki gömülü script içerikleriyle senkron tutulmalıdır.

Slack webhook Secret'ı yoksa notification gönderilemez; webhook adresini hiçbir zaman `README` veya Git'e ekleme.

### 7.8 Kubernetes erişim ve genel sağlık kontrolü

```bash
kubectl get pods -n devops-case
kubectl get deployments -n devops-case
kubectl get services -n devops-case
kubectl get cronjobs -n devops-case
kubectl get pvc -n devops-case
```

Backend readiness kontrolü için cluster içinden erişim veya uygun port-forward kullanılabilir. Tarayıcı erişimi k3d host port eşlemesine bağlıdır.

**Örneğin frontend servisini geçici olarak yerel 8082 portuna yönlendirmek için:**

```bash
kubectl port-forward -n devops-case service/frontend 8082:8080
```

Bu komut terminali açık tutar. Başka terminalden `http://localhost:8082` adresine gidilebilir. NodePort port mapping kurulmuşsa host üzerindeki ilgili port doğrudan kullanılabilir.

## 8. UYGULAMA İŞLEVLERİNİN DOĞRULANMASI

Frontend'de bir kayıt oluştur, listele, düzenle ve sil. Arayüzde kayıtların doğru değiştiğini kontrol et. Backend `/record` API'si bu işlemleri `sample_training.records` collection'ına yazar.

**Sağlık endpoint'leri:**

GET `/healthcheck`: Backend sürecinin HTTP isteğine cevap verip vermediği (liveness).

GET `/healthcheck/ready`: MongoDB erişimi doğrulanır (readiness). Sağlıklı durumda HTTP 200 READY; MongoDB erişilemezse HTTP 503 NOT_READY.

MongoDB kesinti testinde backend süreci çalışmaya devam etmiş; readiness 503 döndürmüş ve MongoDB geri geldikten sonra backend yeniden başlatılmadan tekrar READY durumuna geçmiştir. Readiness, geçici veritabanı sorunlarında Kubernetes Service'in trafik yönlendirme kararına temel oluşturur; anında ve kesintisiz servis garantisi değildir.

**ETL Job kontrolü:**

```bash
kubectl get cronjob github-etl -n devops-case
kubectl get jobs -n devops-case
```

**Belirli başarılı Job'ın logu:**

```bash
kubectl logs -n devops-case job/<gercek-etl-job-adi>
```

ETL 0 * * * * UTC zamanlamasıyla saat başında çalışır. İlk çalıştırmada repository belgeleri eklenir; sonraki çalıştırmada aynı `github_id` üzerinden update yapılır. Unique index duplicate ID oluşmasını engeller. `last_synced_at` alanı her başarılı upsert sırasında güncellenir.

Önceki doğrulamada üç repository için sonraki çalışmada fetched=3, inserted=0, updated=3 sonucu alınmıştır. Bu sayı GitHub hesabının o günkü durumuna aittir; kalıcı bir sayı değildir.

## 9. TESTLER VE KALİTE KONTROLLERİ

### 9.1 Frontend build

```bash
cd mern-project/client
npm ci
npm run build
```

### 9.2 Backend kontrolü

```bash
cd mern-project/server
npm ci
npm audit --omit=dev --audit-level=high
node --check server.mjs
```

Komutlar proje kökünden çalıştırılmıyorsa ilgili dizine geçilmiş olmalıdır.

### 9.3 Cypress E2E

Cypress testleri frontend ve backend çalışırken yürütülür. GitHub Actions bunları kendi Docker ağı içinde kurduğu MongoDB, backend ve frontend ile çalıştırır. Yerel frontend geliştirme sunucusunda:

```bash
cd mern-project/client
npx cypress run --e2e
```

Cypress'in yerel varsayılan baseUrl ayarı `http://localhost:3000`'dür. Uygulama farklı porttan sunuluyorsa testin baseUrl değeri buna göre verilmelidir. CI, `http://localhost:8082` adresini kullanır.

Başlangıçtaki kayıt ekleme testi yanlış sayfada kayıt aradığı için başarısız oluyordu; sayfa seçimi düzeltildikten sonra mevcut iki Cypress testi başarıyla çalışmıştır.

### 9.4 Python ETL analizi için birim testler

**Proje kökünde:**

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Altı test; eski ve yeni ETL başarısızlıklarını ayırma, recovery, başarı kaydı olmayan CronJob, eksik hata zamanı ve farklı CronJob'a ait başarısızlıkların filtrelenmesi gibi durumları kapsar. Altı testin başarılı çalıştığı doğrulanmıştır; bu sonuç tüm modül için yüzde 100 kod kapsamı ölçüldüğü anlamına gelmez.

### 9.5 Güvenlik bağımlılık kontrolü

İlk npm audit testlerinde backend 11 ve frontend 89 güvenlik açığı raporlanmıştı. İyileştirmeler sonrası yapılan yerel kontrolde backend 0, frontend 33 açık kalmıştı. Bu sayılar tarihsel ölçümlerdir; güncel durum için audit yeniden çalıştırılmalıdır. Frontend üretim container'ı Node.js build bağımlılıklarını taşımayan Nginx image'ı kullanır; buna rağmen build-time/supply-chain riskleri tamamen yok olmaz.

### 9.6 Container Image Security Scanning ve SBOM (Advanced 5)

CI pipeline'ına Trivy tabanlı container image güvenlik taraması ve CycloneDX formatında SBOM (Software Bill of Materials) üretimi eklenmiştir.

**Uygulanan kontroller:**

- Backend, frontend ve Python ETL için ayrı güvenlik job'ları.
- Her bileşenin Docker image'ının CI ortamında oluşturulması.
- Trivy ile HIGH ve CRITICAL seviyesindeki bilinen güvenlik açıklarının taranması.
- Her image için CycloneDX JSON formatında SBOM üretilmesi.
- Tarama raporlarının ve SBOM dosyalarının GitHub Actions artifact olarak saklanması.

**CI job'ları:**

- `Security - backend`
- `Security - frontend`
- `Security - etl`

**Üretilen artifact'lar:**

| Artifact | İçerik |
| --- | --- |
| `security-backend` | `trivy-backend.json`, `sbom-backend.json` |
| `security-frontend` | `trivy-frontend.json`, `sbom-frontend.json` |
| `security-etl` | `trivy-etl.json`, `sbom-etl.json` |

Artifact saklama süresi 14 gündür.

**Doğrulama:**

10 Kasım 2026 tarihinde çalıştırılan GitHub Actions workflow'unda üç Security job'ı başarıyla tamamlanmış, vulnerability scanning ve SBOM üretimi doğrulanmıştır.

Başarılı workflow: [GitHub Actions Run #13](https://github.com/iremsilay/devops-case/actions/runs/42861106121)

**Bilinen sınırlamalar:**

- Güvenlik taraması raporlama amaçlıdır. Bulunan açıklar CI çalışmasını otomatik olarak başarısız yapmaz (`exit-code: '0'`).
- Tarama, GHCR'ye yayımlanan image digest'i yerine CI ortamında yeniden oluşturulan image üzerinde gerçekleştirilir.
- Güvenlik açıklarının tamamı giderilmemiştir.
- SBOM üretilmesi, image'ın güvenlik açıklarından arındırılmış olduğu anlamına gelmez.
- Image signing, policy as code ve otomatik güvenlik politikasıyla yayın engelleme uygulanmamıştır.

**Kanıtlar:**

- [43 - Başarılı Security job'ları](docs/screenshots/43-security-jobs-success.png)
- [44 - Trivy taraması ve SBOM üretimi](docs/screenshots/44-security-trivy-scan.png)
- [45 - Güvenlik raporları ve SBOM artifact'ları](docs/screenshots/45-security-artifacts.png)

## 10. CI/CD VE RELEASE YÖNETİMİ

CI/CD süreci, GitHub Actions ile otomatik doğrulama ve Docker image yayınlama, yerel Kubernetes cluster'ında ise kontrollü deployment yaklaşımıyla yönetilir.

### 10.1. CI Pipeline

`.github/workflows/ci.yml` dosyasında tanımlanan pipeline aşağıdaki olaylarla tetiklenir:

- `main` branch'ine push
- `main` branch'ine pull request
- `workflow_dispatch` ile manuel çalıştırma

**Pipeline aşamaları:**

1. **Backend:** `npm ci`, production `npm audit` ve Node.js syntax doğrulaması.
2. **Frontend:** `npm ci` ve `CI=true` ile React production build.
3. **Python ETL:** Requirements kurulumu, `py_compile`, `requests` ve `pymongo` import kontrolü.
4. **Cypress:** Docker ile MongoDB, backend ve frontend servislerini başlatma ve E2E testleri.
5. **Docker:** Önceki doğrulamalar başarılıysa backend, frontend ve ETL image'larını `linux/amd64` ve `linux/arm64` mimarileri için build etme. `main` branch'ine yapılan push işlemlerinde image'ları GHCR'ye yayınlama.

#### Cypress Test Ortamı

Cypress E2E testleri hedef Kubernetes cluster'ında değil, GitHub Actions runner'ı üzerinde oluşturulan geçici ve izole bir Docker ortamında çalıştırılır.

Pipeline, `docker network create` komutuyla ayrı bir `case-ci` ağı oluşturur. MongoDB, backend ve frontend container'ları bu ağ içinde başlatılır.

Backend readiness kontrolü ve frontend üzerinden API erişimi doğrulandıktan sonra Cypress testleri çalıştırılır.

Bu yaklaşım, testlerin hedef Kubernetes cluster'ındaki mevcut verileri ve çalışan servisleri etkilemesini önler. Ayrıca her CI çalışmasında bağımsız bir test ortamı kullanılmasını sağlar.

Testler başarısız olduğunda ilgili container logları ve varsa Cypress ekran görüntüleri inceleme için saklanır.

Bu aşama uygulamanın container ortamındaki E2E davranışını doğrular. Kubernetes deployment ve orkestrasyon davranışlarının tamamını test ettiği anlamına gelmez.

#### Fail-Fast ve Job Bağımlılıkları

Docker aşaması `backend`, `frontend`, `etl` ve `cypress` job'larına bağımlıdır.

Bu job'lardan herhangi biri başarısız olursa Docker aşaması başlatılmaz. Böylece başarısız doğrulamalardan sonra yeni image yayınlanması engellenir.

Pull request kontrollerinde Docker image'ları build edilir ancak GHCR'ye push edilmez.

#### Fail-Fast Test Kanıtları

Fail-fast davranışı, `test/ci-fail-fast` branch'inden `main` branch'ine açılan geçici Pull Request #1 üzerinde test edilmiştir.

- **Pull Request:** [#1 — CI fail-fast testi](https://github.com/iremsilay/devops-case/pull/1)
- **Test commit'i:** `4cd5e7d`
- **Yöntem:** Cypress testine kasıtlı olarak başarısız olacak `FAIL_FAST_TEST_ELEMENT` assertion'ı eklenmiştir.
- **Cypress E2E:** Failure
- **Docker build/publish:** Skipped
- **Diğer kontroller:** Backend validation, Frontend build ve Python ETL validation başarılıdır.

**Pull Request kontrol sonuçları:**

![Fail-fast testinde başarısız Cypress ve atlanan Docker job'ı](docs/screenshots/22-cicd-fail-fast.png)

**Cypress hata logu:**

![Kasıtlı Cypress assertion hatası](docs/screenshots/23-cicd-fail-fast-log.png)

Bu test, Cypress doğrulaması başarısız olduğunda Docker job'ının başlatılmadığını göstermektedir. Böylece başarısız test sonucunda yeni Docker image'larının GHCR'ye yayınlanması engellenmiştir.

Test yalnızca geçici branch üzerinde gerçekleştirilmiştir. Değişiklikler `main` branch'ine dahil edilmemiştir.

### 10.2. CI Pipeline Çalışma Kanıtları

GitHub Actions üzerinde `main` branch'ine yapılan push sonrasında `CI - MERN and ETL` workflow'u başarıyla tamamlanmıştır.

- **Workflow:** CI - MERN and ETL (#9)
- **Commit:** `b5873c8`
- **Sonuç:** Success
- **Süre:** 3 dakika 11 saniye

Backend validation, Frontend build, Python ETL validation, Cypress E2E ve üç Docker build job'ının tamamı başarılıdır.

**GitHub Actions pipeline geçmişi:**

![Başarılı CI pipeline](docs/screenshots/12-cicd-pipeline-success.png)

**Pipeline job sonuçları:**

![Başarılı CI doğrulama ve Docker build job'ları](docs/screenshots/13-cicd-jobs-success.png)

Bu görüntüler, belirtilen commit için CI doğrulamalarının ve Docker build aşamalarının başarıyla tamamlandığını gösterir.

### 10.3. GHCR Image Yayınlama

CI doğrulamaları başarılı olduğunda backend, frontend ve ETL için Docker image'ları oluşturulur.

**GHCR image adları:**

- `ghcr.io/iremsilay/devops-case-backend`
- `ghcr.io/iremsilay/devops-case-frontend`
- `ghcr.io/iremsilay/devops-case-etl`

Image'lar iki farklı tag ile sürümlenir:

- `latest`: En son yayınlanan sürüm.
- `sha-<40-karakterlik-commit-hash>`: Belirli bir Git commit'ine ait sürüm.

SHA tabanlı sürümleme, deployment sırasında belirli bir image sürümünün seçilmesini ve CI çalışmasıyla ilişkilendirilmesini sağlar.

#### GHCR Yayınlama Kanıtları

Backend, frontend ve ETL paketlerinin GHCR üzerinde yayınlandığı doğrulanmıştır.

![GHCR üzerinde yayınlanan Docker image'ları](docs/screenshots/20-cicd-ghcr-images.png)

Backend image'ının `latest` ve `sha-b5873c8b85f31885109fb038f517e18f06601448` tag'leriyle yayınlandığı doğrulanmıştır.

Bu SHA tag'i, başarılı CI workflow'unun commit'iyle eşleşmektedir.

![GHCR backend image sürüm detayları](docs/screenshots/21-cicd-ghcr-image-tags.png)

### 10.4. Kubernetes Deployment

Deployment'ın GitHub Actions tarafından doğrudan yapılmaması bilinçli bir yerel cluster izolasyonu kararıdır.

GitHub-hosted runner'ın yerel Kubernetes cluster'ına erişimi bulunmadığından, cluster'ı dış erişime açmak yerine image yayınlama ve deployment adımları ayrılmıştır.

Bu yaklaşım tam otomatik CD veya GitOps olarak tanımlanmaz. CI ve image yayınlama otomatik, yerel cluster'a sürüm geçişi ise manuel olarak tetiklenir.

**Yerel cluster'a yayınlanmış bir SHA image sürümünü geçirmek için:**

```bash
./scripts/deploy-local.sh sha-<40-karakterlik-git-commit-hash>
```

`deploy-local.sh` script'i yalnızca `k3d-devops-case` Kubernetes context'inde çalışır ve image etiketi olarak 40 karakterlik Git commit SHA'sını içeren `sha-<commit-hash>` biçimini kabul eder.

Script'in deployment akışı:

1. Backend Deployment, frontend Deployment ve ETL CronJob kaynaklarının mevcut image referanslarını kaydeder.
2. `kubectl set image` ile backend image'ını yeni sürüme günceller.
3. `kubectl rollout status --timeout=180s` ile backend rollout sonucunu kontrol eder.
4. Backend başarılıysa frontend image'ını günceller ve rollout sonucunu kontrol eder.
5. Her iki Deployment başarılıysa ETL CronJob image'ını günceller.

Bu sıra, başarısız bir backend rollout sonrasında frontend ve ETL kaynaklarının yeni sürüme geçirilmesini önler.

#### Kubernetes Deployment Çalışma Kanıtları

Yerel `k3d-devops-case` Kubernetes cluster'ında, GHCR üzerinde yayınlanmış yeni bir SHA sürümüne kontrollü deployment gerçekleştirilmiştir.

**Deployment bilgileri:**

- **Namespace:** `devops-case`
- **Önceki sürüm:** `sha-92683629ca434accfb946cb255ad97eb0e4f4bc5`
- **Yeni sürüm:** `sha-b5873c8b85f31885109fb038f517e18f06601448`
- **Deployment yöntemi:** `scripts/deploy-local.sh`
- **Sonuç:** Başarılı

**Deployment öncesi durum:**

Backend, frontend ve ETL kaynakları önceki SHA sürümünü kullanmaktadır. Backend ve frontend Deployment kaynakları `1/1 Ready` durumundadır.

![Deployment öncesi Kubernetes durumu](docs/screenshots/24-cd-before-deployment.png)

**Deployment işlemi:**

Aşağıdaki komut ile yeni sürüm uygulanmıştır:

```bash
./scripts/deploy-local.sh sha-b5873c8b85f31885109fb038f517e18f06601448
```

Script çıktısında backend ve frontend için `successfully rolled out`, ETL CronJob için `image updated` ve işlem sonunda `Deployment completed successfully.` mesajları görülmüştür.

![Başarılı Kubernetes deployment işlemi](docs/screenshots/25-cd-deployment-success.png)

**Deployment sonrası doğrulama:**

Deployment sonrasında backend, frontend ve ETL image referanslarının yeni SHA sürümüne geçtiği doğrulanmıştır.

Backend ve frontend Deployment kaynakları `1/1 Ready`, ilgili pod'lar ise `Running` durumundadır.

![Deployment sonrası image ve pod doğrulaması](docs/screenshots/26-cd-rollout-success.png)

Bu test, GHCR üzerinde yayınlanan belirli bir commit sürümünün yerel Kubernetes cluster'ına uygulanabildiğini ve backend/frontend rollout işlemlerinin başarıyla tamamlandığını göstermektedir.

### 10.5. Rollback Mekanizması

Deployment sırasında herhangi bir komut başarısız olduğunda Bash `ERR` trap mekanizması rollback fonksiyonunu çalıştırır.

Rollback fonksiyonu:

1. Deployment öncesinde kaydedilen backend, frontend ve ETL image referanslarını kullanır.
2. `kubectl set image` komutlarıyla eski image referanslarını ilgili Kubernetes kaynaklarına yeniden uygular.
3. Backend ve frontend Deployment kaynaklarının rollout durumlarını tekrar kontrol eder.
4. Rollback sırasında hata oluşursa uyarı verir ve manuel inceleme gerektirir.

Bu mekanizma, başarısız deployment sonrasında önceki image sürümlerine kontrollü dönüş sağlamayı amaçlar. Ancak image erişimi, cluster sağlığı veya başka altyapı sorunları nedeniyle her koşulda otomatik iyileşme garanti edilmez.

#### Rollback Test Kanıtları

Rollback mekanizması, yerel `k3d-devops-case` Kubernetes cluster'ında kasıtlı olarak başarısız bir deployment oluşturularak test edilmiştir.

- **Sağlıklı sürüm:** `sha-b5873c8b85f31885109fb038f517e18f06601448`
- **Hatalı test sürümü:** `sha-0000000000000000000000000000000000000000`
- **Test yöntemi:** GHCR'de bulunmayan bir image tag'iyle deployment başlatılması.
- **Hata:** Backend rollout işlemi zaman aşımına uğramıştır.
- **Rollback:** Script otomatik olarak geri dönüş fonksiyonunu çalıştırmıştır.

**Rollback'i tetikleyen komut:**

```bash
./scripts/deploy-local.sh sha-0000000000000000000000000000000000000000
```

Script çıktısında `error: timed out waiting for the condition` hatasının ardından `Deployment failed. Starting rollback...` mesajı görülmüştür.

Backend ve frontend rollout kontrolleri başarılı olmuş ve script `Rollback completed.` mesajıyla geri dönüş işlemini tamamlamıştır.

![Başarısız deployment ve rollback işlemi](docs/screenshots/27-cd-rollback-trigger.png)

**Rollback sonrası Kubernetes doğrulaması:**

![Rollback sonrası image ve pod durumları](docs/screenshots/28-cd-rollback-success.png)

Bu test, hatalı deployment durumunda rollback mekanizmasının tetiklendiğini ve önceki image referanslarına geri dönüş işleminin gerçekleştirildiğini göstermektedir.

### 10.6. Sınırlamalar ve Doğrulama

- **Manuel CD:** Kubernetes deployment işlemi GitHub Actions tarafından otomatik olarak tetiklenmez.
- **Image erişimi:** Belirtilen SHA tag'lerinin GHCR üzerinde bulunması ve Kubernetes cluster'ı tarafından çekilebilir olması gerekir. Kimlik doğrulaması gerekiyorsa uygun `imagePullSecret` yapılandırılmalıdır.
- **ETL doğrulaması:** ETL CronJob image'ının güncellenmesi, yeni ETL sürümünün başarılı çalıştığını tek başına kanıtlamaz. Bunun için sonraki ETL Job sonucu ayrıca kontrol edilmelidir.
- **Rollback:** Script önceki image referanslarını geri yüklemeyi dener. Rollback başarısı, Kubernetes rollout sonuçlarıyla ayrıca doğrulanmalıdır.
- **CI kapsamı:** Cypress testleri izole Docker ortamında çalışır; hedef Kubernetes cluster'ının tüm deployment davranışlarını doğrulamaz.

Başarılı CI pipeline ve GHCR image yayınlama sonuçları ekran görüntüleriyle belgelenmiştir. Fail-fast, Kubernetes deployment ve rollback davranışlarının çalışma kanıtları ayrı testlerle doğrulanacaktır.

## 11. MONITORING, LOGLAMA VE SLACK UYARILARI

`monitoring-check` Kubernetes CronJob'ı her dakika çalışır. Backend Deployment kullanılabilir replica sayısını ve `github-etl` CronJob/Job durumunu Kubernetes API üzerinden inceler.

**Alarm türleri:**

`BACKEND_UNAVAILABLE`: Backend kullanılabilir replica sayısının beklenenin altında olması.

`ETL_OVERDUE`: Son başarılı ETL'nin belirlenen süreyi aşması; mevcut eşik 4500 saniye (75 dakika).

`ETL_JOB_FAILED`: Son başarılı ETL'den sonra başarısız olmuş, CronJob tarafından oluşturulmuş ETL Job'ı bulunması.

`ETL_NO_SUCCESS`: ETL için hiç başarılı zaman kaydı bulunmaması.

`ETL_SUSPENDED`: ETL CronJob'ının askıya alınması.

Her alarm türünün aktif durumu ve son gönderim zamanı `monitoring-state` ConfigMap'inde saklanır. İlk alarm Slack'e gönderilir. Devam eden sorunlarda 900 saniyelik (15 dakikalık) bağımsız throttling uygulanır. Sorun düzeldiğinde RESOLVED mesajı ile alarm state'i temizlenir. Webhook gönderimi başarısızsa bildirim başarılı olarak kaydedilmez. ConfigMap güncellemelerinde `resourceVersion` koşulu kullanılarak eski state'e dayanan güncellemeler reddedilir; bu yöntem eşzamanlı her bildirim yarışını garantiyle engellemez.

`monitoring/evaluate_etl.py`, Job `ownerReferences` ve başarısızlık zamanlarını değerlendirerek önceki başarılı ETL'den daha eski başarısızlıkların yeni alarm sayılmasını önler. Bu modül için altı birim testi uygulanmıştır.

**Kontrol komutları:**

```bash
kubectl get cronjob monitoring-check -n devops-case
kubectl get jobs -n devops-case
kubectl logs -n devops-case job/<gercek-monitoring-job-adi>
```

**Alarm state'ini incelemek için:**

```bash
kubectl get configmap monitoring-state -n devops-case -o yaml
```

**Önemli:** ConfigMap çıktısı alarm metadatasıdır; Secret içermez. Slack webhook Secret'ının değerini okumak, loglamak veya paylaşmak gerekli değildir.

Backend ve ETL hata, throttling, yeniden bildirim ve RESOLVED senaryoları yerel Kubernetes ortamında test edilmiştir. Testlerin ardından geçici test CronJob/Job kaynakları kaldırılmış, otomatik monitoring yeniden etkinleştirilmiş ve sağlıklı log sonucu alınmıştır.

**Sınır:** Cluster veya Kubernetes API tamamen erişilemezse cluster içinde çalışan monitoring CronJob'ı bildirim üretemeyebilir. Harici cluster availability monitoring kurulmamıştır. Prometheus/Grafana ve merkezi log depolama da bu sürümde yoktur.

## 12. MONGODB BACKUP VE RESTORE

MongoDB `sample_training` ve `github_etl` veritabanlarının yedeklenmesi ve geri yüklenmesi için `scripts/backup.sh` ve `scripts/restore.sh` kullanılır.

Scriptler, Kubernetes `devops-case` namespace'inde çalışan `mongodb-0` Pod'u üzerinde çalıştırılır. Docker Compose MongoDB container'ına yönelik değildir.

### 12.1. Backup İşlemi

Proje kökünde aşağıdaki komut çalıştırılır:

```bash
./scripts/backup.sh
```

Script, `mongodump` kullanarak iki veritabanını ayrı arşiv dosyalarına kaydeder.

Her çalıştırmada `backups/YYYYMMDDTHHMMSSZ/` klasörü oluşturulur:

- `sample_training.archive`
- `github_etl.archive`
- `SHA256SUMS`

Arşivler Kubernetes Pod'undan yerel bilgisayara aktarılır. Başarısız dump işlemleri ve boş arşivler hata olarak değerlendirilir. Backup klasörü `700`, dosyalar `600` izinleriyle oluşturulur.

Arşivlerin SHA-256 bütünlük doğrulaması şu komutla yapılır:

```bash
(cd backups/<timestamp> && shasum -a 256 -c SHA256SUMS)
```

### 12.2. Restore İşlemi

Proje kökünde aşağıdaki komut çalıştırılır:

```bash
./scripts/restore.sh backups/<timestamp>
```

Script önce SHA-256 checksum değerlerini doğrular, ardından kullanıcıdan `RESTORE` onayı ister.

`mongorestore --drop` kullanıldığı için yedekte bulunan collection'ların mevcut sürümleri silinir ve arşivdeki veriler geri yüklenir.

**Dikkat:** Backup alındıktan sonra yapılan veri değişiklikleri restore sırasında kaybolabilir. Bu işlem üretim ortamında kontrollü uygulanmalıdır.

### 12.3. Gerçek Backup ve Restore Testi

Backup ve restore mekanizması, 10 Kasım 2026 tarihinde yerel Kubernetes ortamında React uygulaması ve MongoDB birlikte kullanılarak test edilmiştir.

**Test ortamı:**

- Kubernetes context: `k3d-devops-case`
- Namespace: `devops-case`
- MongoDB Pod: `mongodb-0`
- Frontend: `http://localhost:8082/records`
- Backup klasörü: `backups/20261110T161624Z`
- Test kaydı: `Backup Test`

**1. React arayüzünden kayıt oluşturma**

React uygulamasının `Create Record` ekranından aşağıdaki çalışan kaydı oluşturulmuştur:

| Alan | Değer |
| --- | --- |
| Name | `Backup Test` |
| Position | `Backup Test` |
| Level | `Junior` |

Kayıt, `Record List` ekranında mevcut `Employee1` kaydıyla birlikte görüntülenmiştir.

Aynı kayıt MongoDB'deki `sample_training.records` collection'ında doğrulanmıştır. Backup öncesinde toplam 2 kayıt bulunmaktadır.

![React arayüzünde oluşturulan test kaydı](docs/screenshots/35-backup-ui-record-created.png)

**2. Backup alma ve bütünlük doğrulaması**

ETL CronJob'ı test sırasında yeni veri yazılmasını önlemek amacıyla geçici olarak askıya alınmıştır.

Ardından aşağıdaki komut çalıştırılmıştır:

```bash
./scripts/backup.sh
```

Backup dosyaları `backups/20261110T161624Z` klasörüne kaydedilmiştir.

`sample_training` veritabanındaki `records` collection'ından 2 belge, `backup_restore_test` collection'ından 1 belge ve `github_etl.repositories` collection'ından 3 belge yedeklenmiştir.

Her iki arşivin SHA-256 doğrulaması başarılıdır:

```text
sample_training.archive: OK
github_etl.archive: OK
```

![Backup oluşturma ve SHA-256 doğrulaması](docs/screenshots/36-backup-ui-created.png)

**3. MongoDB collection'ını silme**

Gerçek veri kaybını simüle etmek için React uygulamasının kullandığı `sample_training.records` collection'ı MongoDB üzerinden silinmiştir.

Silme öncesinde collection'da `Backup Test` ve `Employee1` olmak üzere 2 kayıt bulunmaktaydı.

```text
RECORDS BEFORE DROP:
2

COLLECTION DROPPED:
true

RECORDS AFTER DROP:
0
```

![MongoDB records collection'ının silinmesi](docs/screenshots/37-backup-records-dropped.png)

**4. Veri kaybını hem arayüzde hem MongoDB'de doğrulama**

Collection silindikten sonra React uygulamasındaki `Record List` sayfası yenilenmiştir.

Önceden listelenen `Backup Test` ve `Employee1` kayıtları artık arayüzde görüntülenmemiştir.

![React arayüzünde veri kaybı](docs/screenshots/38-backup-ui-data-lost.png)

Aynı zamanda MongoDB üzerinde `Backup Test` kaydı sorgulanmıştır.

```text
BACKUP TEST AFTER DELETION:
null

TOTAL RECORDS:
0
```

Böylece veri kaybı hem uygulama arayüzünde hem veritabanında doğrulanmıştır.

![MongoDB üzerinde veri kaybının doğrulanması](docs/screenshots/39-backup-db-data-lost.png)

**5. Backup'tan geri yükleme ve süre ölçümü**

Aşağıdaki komut çalıştırılarak backup'tan geri yükleme gerçekleştirilmiştir:

```bash
/usr/bin/time -p ./scripts/restore.sh backups/20261110T161624Z
```

Script, arşivlerin SHA-256 bütünlüğünü doğrulamış ve kullanıcıdan `RESTORE` onayı almıştır.

`mongorestore --drop` ile iki veritabanındaki yedeklenmiş collection'lar geri yüklenmiştir.

**Gerçek restore sonuçları:**

| Veritabanı | Geri yüklenen belge | Başarısız belge |
| --- | ---: | ---: |
| `sample_training` | 3 | 0 |
| `github_etl` | 3 | 0 |
| **Toplam** | **6** | **0** |

Terminal çıktısı:

```text
Restore completed successfully.

real 4,80
user 0,12
sys 0,06
```

Restore script'inin toplam çalışma süresi 4,80 saniye olarak ölçülmüştür. Bu süre kullanıcı onayını da içerir; uygulamanın uçtan uca kurtarma süresi olarak değerlendirilmemiştir.

![Restore işlemi ve ölçülen süre](docs/screenshots/40-backup-restore-timed.png)

**6. Geri yüklenen verilerin hem arayüzde hem MongoDB'de doğrulanması**

Restore tamamlandıktan sonra React uygulamasındaki `Record List` sayfası yeniden yüklenmiştir.

Silinen `Backup Test` ve `Employee1` kayıtlarının aynı alan değerleriyle yeniden listelendiği doğrulanmıştır.

![React arayüzünde kurtarılan kayıtlar](docs/screenshots/41-backup-ui-recovered.png)

MongoDB üzerinde yapılan sorgularda da her iki kayıt bulunmuştur.

```text
RESTORED BACKUP TEST RECORD:
name: 'Backup Test'
position: 'Backup Test'
level: 'Junior'

RESTORED EMPLOYEE1 RECORD:
name: 'Employee1'
position: 'Position1'
level: 'Intern'

TOTAL RECORDS:
2
```

Bu sonuçlar, uygulamanın kullandığı gerçek verilerin backup'tan geri getirildiğini ve React arayüzünde yeniden görüntülenebildiğini kanıtlamaktadır.

![MongoDB üzerinde kurtarılan kayıtların doğrulanması](docs/screenshots/42-backup-db-recovered.png)

**7. Test sonrası servis kontrolü**

Restore ve veri doğrulaması tamamlandıktan sonra `github-etl` CronJob'ı yeniden etkinleştirilmiştir.

Son Kubernetes kontrolünde:

- `github-etl`: `SUSPEND=False`, `ACTIVE=0`
- Backend deployment: `1/1 Ready`
- Frontend deployment: `1/1 Ready`
- MongoDB Pod: `1/1 Running`
- MongoDB Pod restart sayısı: `0`

sonuçları alınmıştır.

### 12.4. Test Sonucu ve Sınırlamalar

**Sonuç: Backup ve restore testi başarılı.**

Teknik case kapsamında istenen altı aşama tamamlanmıştır: React arayüzünden kayıt oluşturma, backup alma, ilgili MongoDB collection'ını silme, veri kaybını hem arayüzde hem veritabanında doğrulama, restore gerçekleştirme ve kayıtların iki tarafta yeniden göründüğünü kanıtlama.

Testte toplam 6 belge hatasız geri yüklenmiş, restore script'inin çalışma süresi 4,80 saniye olarak ölçülmüştür.

**RPO/RTO hedefleri ve sınırlamalar:**

- **Hedef RPO:** 24 saat. Mevcut manuel backup sistemi bu hedefi otomatik olarak garanti etmemektedir.
- **Hedef RTO:** 15 dakika. Restore script'i 4,80 saniyede tamamlanmıştır; ancak uçtan uca uygulama kurtarma süresi ayrıca ölçülmediği için RTO hedefinin karşılandığı kesin olarak doğrulanmamıştır.
- **Retention hedefi:** 7 gün. Otomatik retention temizliği uygulanmamıştır.
- Backup işlemi manuel başlatılır; otomatik zamanlayıcı bulunmamaktadır.
- Backup dosyaları Kubernetes cluster'ının dışında, aynı fiziksel bilgisayarda saklanır. Disk kaybına karşı bağımsız off-site koruma sağlamaz.
- Şifreli uzak object storage kullanılmamaktadır.
- `mongorestore --drop` nedeniyle backup sonrasındaki değişiklikler kaybolabilir.
- ETL CronJob'ı test sırasında manuel olarak durdurulmuştur; diğer uygulama yazmaları otomatik olarak engellenmemektedir.

Mevcut çözüm, yerel Kubernetes ortamında uçtan uca test edilmiş manuel bir MongoDB backup ve restore mekanizmasıdır. Tam otomatik bir production disaster recovery sistemi değildir.

Ayrıntılı operasyon prosedürleri `docs/backup-restore.md`, ekran görüntüleri ve test sonuçları ise `TESLIM_KANITLARI.md` dosyasında sunulmuştur.

## 13. ROLLBACK, TEMİZLİK VE GÜVENLİK

### 13.1 Rollback

Hatalı bir release sırasında deploy-local.sh, deployment öncesinde kaydettiği backend, frontend ve ETL image referanslarını kullanarak otomatik rollback gerçekleştirir.

Bu işlem `kubectl rollout undo` yerine `kubectl set image` komutuyla eski image sürümlerinin yeniden uygulanmasına dayanır. Rollback sonrasında backend ve frontend için `kubectl rollout status` çalıştırılarak önceki sürümlerin yeniden kullanılabilir hale gelip gelmediği kontrol edilir.

Rollback başarısız olursa script uyarı üretir ve manuel müdahale gerekir. İşlem veritabanı içeriğini veya veri şemasını otomatik olarak geri almaz.

Deployment tamamlandıktan sonra ortaya çıkan sorunlarda otomatik rollback tetiklenmez. Bu durumda önceki çalışan Git commit SHA'sı belirlenerek `scripts/deploy-local.sh` aynı eski sürüm etiketiyle yeniden çalıştırılabilir.

ETL CronJob için image referansının geri alınması yeterli değildir. Sonraki ETL Job'ının başarılı çalıştığı ayrıca doğrulanmalıdır.

### 13.2 Güvenli temizlik

Compose container'larını kaldırmak için `docker compose down` yeterlidir; -v veritabanı volume'unu siler.

Kubernetes ortamında namespace silmek MongoDB PVC ve cluster kaynakları açısından veri kaybına neden olabilir. Değişiklik öncesi backup alınmadan devops-case namespace'i silinmemelidir. Cluster'ın tamamını silme komutu bir temizlik rutini olarak önerilmez.

Monitoring testlerini geçici olarak oluşturduktan sonra test Job/CronJob'larını kaldırmak, `monitoring-check` CronJob'ını tekrar suspend=false durumuna getirmek ve alarm state'lerinin temizlendiğini kontrol etmek gerekir. Normal çalışma sırasında `monitoring-state` ConfigMap'i sıfırlanmamalıdır.

### 13.3 Güvenlik yaklaşımı

- Gerçek parolalar, token'lar ve Slack webhook URL'si repository veya image içine eklenmez.
- Kubernetes Secret gizli değerler için; ConfigMap gizli olmayan konfigürasyon için kullanılır.
- Backend ve ETL farklı MongoDB kullanıcılarıyla kendi veritabanlarına erişir.
- Backend, frontend ve ETL için container kullanıcıları gereksiz root ayrıcalıklarından kaçınır; monitoring'de read-only root filesystem ve sınırlı ServiceAccount yetkileri kullanılır.
- Backend ClusterIP ve MongoDB headless Service ile dışa doğrudan açılmaz. Frontend NodePort dış erişim girişidir.
- CI production dependency audit uygular; kalan frontend bağımlılık uyarıları `docs/findings.md` içinde açıklanır.

**Riskler:** CORS geniş yapılandırılmıştır, API input validation tam değildir, cluster tek node/tek MongoDB replica üzerinde çalışmaktadır, otomatik secret rotation ve network policy uygulanmamıştır. Bunlar gerçek production için ek çalışma gerektirir.

## 14. SIK KARŞILAŞILAN SORUNLAR

**Frontend açılıyor fakat API isteği başarısız:**

- Frontend'in `/api` isteğini kullandığını doğrula.
- backend Deployment ve readiness değerlerini kontrol et.
- Nginx reverse proxy'deki `case-backend` servis adını ve aynı namespace'teki Service'i incele.
- Cluster port mapping veya kubectl port-forward yapılandırmasını kontrol et.

**Backend READY değil:**

- MongoDB Pod/PVC durumuna ve MongoDB loglarına bak.
- `backend-mongo-uri` Secret'ının varlığını ve MongoDB kullanıcı yetkilerini doğrula; değerlerini paylaşma.
- `/healthcheck` ile `/healthcheck/ready` sonucunu ayrı değerlendir.

**Pod `ImagePullBackOff`:**

- Yerel case-* image'ları k3d'ye import edilmiş mi kontrol et.
- GHCR image tag'i mevcut mu ve registry erişimi var mı kontrol et.
- Pod describe çıktısındaki image pull olaylarını incele.

**ETL çalışmıyor:**

- `github-etl` CronJob'ının suspend=false olduğunu kontrol et.
- Son Job loglarını ve Kubernetes Job status/conditions değerlerini incele.
- GitHub kullanıcı adı, API rate limitleri ve MongoDB erişimini kontrol et.

**Slack bildirimi gelmiyor:**

- `monitoring-check` CronJob ve son Job loglarını kontrol et.
- `monitoring-slack-webhook` Secret'ının mevcut olduğunu doğrula.
- `monitoring-state` alarmın aktifliği ve throttling zamanını kontrol et.
- WEBHOOK_FAILED/WEBHOOK_SENT loglarını karşılaştır; webhook değerini yazdırma.

**Backup/restore hata veriyor:**

- `mongodb-0` Pod'unun hazır olduğunu kontrol et.
- Yetkili MongoDB hesaplarının tanımlı olduğunu doğrula.
- SHA256SUMS kontrolünü ve archive dosyalarının varlığını incele.
- Restore işleminin --drop ile veri değiştirdiğini unutma.

## 15. DOĞRULANAN SONUÇLAR VE BİLİNEN SINIRLAMALAR

**Önceden çalıştırılmış testlerde aşağıdaki sonuçlar doğrulanmıştır:**

- Docker Compose ile frontend, backend ve MongoDB çalıştırılması.
- Frontend üzerinden create, read/list, update ve delete işlemleri.
- Cypress E2E testlerinde 2/2 başarılı sonuç.
- MongoDB bağlantı kesintisinde backend sürecinin açık kalması, readiness'in 503 olması ve veritabanı geri geldiğinde 200'e dönmesi.
- Kubernetes üzerinde frontend/backend 1/1 hazır olması.
- ETL'nin saatlik Kubernetes CronJob çalışması ve var olan repository kayıtlarını tekrar insert etmeden güncellemesi.
- Monitoring CronJob'ının periyodik çalışması ve beş alarm türüne ilişkin durum değerlendirmesi.
- Slack ilk alarm, throttling ve RESOLVED senaryoları; backend ve ETL arıza/toparlanma testleri.
- ETL analiz modülünün altı birim testinin geçmesi.
- MongoDB yedekleme ve geri yükleme yaklaşımının yerel ortamda denenmesi.

Bu sonuçlar geçmiş testlere aittir; yeni bir kurulumdaki mevcut durumu ayrıca doğrulamak gerekir.

**Bilinçli kapsam sınırları:**

- Bu ortam public cloud üretim servisi değildir; yerel k3d ile doğrulanmıştır.
- MongoDB tek replica'dır; çoklu node, replica set veya otomatik failover kurulmamıştır.
- Container image'larının CI'da üretilmesi otomatik Kubernetes deployment olduğu anlamına gelmez.
- Helm/Kustomize, Terraform, Argo CD/Flux ve HPA/PDB uygulanmamıştır.
- Prometheus/Grafana dashboard'ları veya cluster dışından bağımsız monitoring yoktur.
- Kullanıcı girdileri için tam API şema doğrulaması, dar CORS allowlist'i ve otomatik secret rotasyonu yoktur.
- MongoDB backup scriptleri manuel tetiklenir; otomatik retention, uzak şifreli depolama veya point-in-time recovery bulunmaz.

Gelecekte eklenmesi değerlendirilen üst kriterler: mevcut doğrulanmış alarm senaryolarına dayanan ileri gözlemlenebilirlik, image vulnerability scanning veya SBOM ile ileri güvenlik, otomatik/off-site yedekleme ile gelişmiş disaster recovery. Planlanan özellikler uygulanmış gibi değerlendirilmemelidir.

## 16. EK DOKÜMANLAR VE TESLİM KANITLARI

**Başlangıç bulguları, uygulanan değişiklikler ve bilinçli kapsam sınırları:**

`docs/findings.md`, `docs/findings_en.md`

**Mimari diyagramı ve ayrıntılı veri/istek akışı:**

`docs/architecture.md`

**Backup/restore uygulama adımları, retention ve RPO/RTO değerleri:**

`docs/backup-restore.md`

**Çalışan sistemin zorunlu ekran görüntüleri:**

`docs/screenshots/`, `TESLIM_KANITLARI.md`, `SUBMISSION_EVIDENCE.md`

**Case sonu soruların cevapları:**

`CASE_SONU_CEVAPLARI.md`, `CASE_END_ANSWERS.md`

**Orijinal değerlendirme dokümanları:**

`DevOps_Teknik_Case_TR.docx`, `DevOps_Technical_Case_EN.docx`
