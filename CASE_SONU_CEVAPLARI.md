# CASE SONU CEVAPLARI

Bu dosyada aşağıdaki soruların tamamını, yaptığınız çalışma ile doğrudan ilişkilendirerek cevaplayın.

Cevaplarınızın kısa, somut ve teknik kararlarınızı açıklayacak düzeyde olması beklenmektedir. Gerekli gördüğünüz yerlerde ilgili kaynak koduna, manifest dosyasına, pipeline adımına veya dokümana dosya yolu vererek referans verebilirsiniz. Çalışma kanıtları ve ekran görüntüleri ayrıca `TESLIM_KANITLARI.md` dosyasında sunulmalıdır.

---

## Aday Bilgileri

- **Ad Soyad:** İrem Sıla AY
- **Repository adresi:** https://github.com/iremsilay/devops-case  
- **Çalışmanın tamamlandığı tarih:** 11 Kasım 2026  
- **Kullanılan hedef ortam:** Yerel Kubernetes — Docker Desktop üzerinde k3d cluster (`devops-case`)

---

## 1. Mimari ve İstek Akışı

Kurduğunuz mimariyi ve bir kullanıcı isteğinin frontend’den başlayarak backend ve veritabanına kadar izlediği yolu açıklayın.

Ayrıca sistem bileşenlerini, bileşenler arasındaki bağlantıları, trafik akışını ve dış erişim noktalarını gösteren bir mimari diyagram hazırlayarak proje reposuna aşağıdaki dosyalardan biri olarak ekleyin:

- `docs/architecture.md`
- `docs/architecture.pdf`

Diyagram Mermaid, Draw.io, Excalidraw veya benzeri bir araçla hazırlanabilir. Düzenlenebilir kaynak dosyasının da repoya eklenmesi beklenmektedir.

**Cevap:**

Sistem, Docker Desktop üzerinde çalışan yerel `k3d-devops-case` Kubernetes cluster'ında, `devops-case` namespace'i altında çalışır.

Kullanıcı uygulamaya dış erişime açık olan `frontend` NodePort Service üzerinden erişir. Bu Service, isteği Nginx çalışan frontend Pod'una iletir. Nginx React uygulamasının statik dosyalarını sunar.

Tarayıcıdan gelen `/api` istekleri Nginx reverse proxy tarafından yalnızca cluster içinden erişilebilen `case-backend` ClusterIP Service'ine yönlendirilir. Backend Pod'u, çalışan kayıtları için MongoDB işlemlerini `mongodb-service` headless Service üzerinden gerçekleştirir. MongoDB, `mongodb-0` StatefulSet Pod'unda çalışır ve verisini `mongo-data` PersistentVolumeClaim üzerinde tutar.

Dış erişime açık tek uygulama bileşeni frontend NodePort Service'tir. Backend ve MongoDB doğrudan dış erişime kapalıdır. Yerel erişim, k3d host port eşlemesi veya geçici `kubectl port-forward` ile sağlanır. Bu mimaride Ingress Controller ve HTTPS/TLS terminasyonu bulunmaz; trafik HTTP üzerinden çalışır.

Kullanıcı isteklerinden bağımsız olarak `github-etl` CronJob'ı saat başında çalışır. ETL Job'ı GitHub REST API'den repository verilerini alır ve `github_id` alanı üzerinden MongoDB'deki `github_etl.repositories` koleksiyonuna upsert yapar.

`monitoring-check` CronJob'ı her dakika backend ve ETL durumlarını Kubernetes API üzerinden kontrol eder. Alarm durumu `monitoring-state` ConfigMap'inde tutulur; sorun tespit edildiğinde Slack Incoming Webhook ile bildirim gönderilir.

Mimari açıklaması `docs/architecture.md`, görsel diyagram `docs/architecture.png`, düzenlenebilir kaynak `docs/architecture.drawio` ve PDF çıktısı `docs/architecture.pdf` dosyalarında sunulmuştur.

---

## 2. Kritik Bulgular ve Önceliklendirme

Başlangıç projelerinde tespit ettiğiniz en kritik üç sorun neydi? Bu sorunları hangi etki ve risk kriterlerine göre önceliklendirdiniz?

Doğru; bu cevap ilk analizde belirlediğimiz sırayı korumalı. Aşağıdaki metni kullan:

**Cevap:**

İlk analizde öncelikli olarak F-08, F-01 ve F-04 seçildi. Önceliklendirmede servis kesintisi riski, güvenlik etkisi ve case'in zorunlu teslim kriterlerini karşılama durumu dikkate alındı.

| Bulgu | Öncelik | Seçilme nedeni ve çözüm yaklaşımı |
| --- | --- | --- |
| F-08 — MongoDB bağlantı dayanıklılığı | Kritik | MongoDB erişilemez olduğunda yakalanmayan `MongoServerSelectionError`, backend Node.js sürecinin tamamen çökmesine neden oluyordu. Kısa süreli bir veritabanı veya ağ kesintisi tüm API'nin kapanmasına yol açtığı için ilk ele alınan bulgu buydu. Bağlantı ve asenkron hata yönetimi düzenlendi, `serverSelectionTimeoutMS: 5000` eklendi, MongoDB kesintisinde readiness endpoint'inin HTTP 503 dönmesi sağlandı. MongoDB geri geldiğinde backend yeniden başlatılmadan tekrar `READY` durumuna geçecek şekilde doğrulandı. |
| F-01 — Bağımlılık güvenlik açıkları | Kritik | Başlangıçta backend'de 11, frontend'de 89 güvenlik açığı; bunların içinde backend'de 1, frontend'de 6 kritik açık bulunuyordu. Bilinen CVE'lerin runtime veya build sürecinde istismar edilebilmesi nedeniyle kritik kabul edildi. İlk aşamada bağımlılık güncellemeleri ve `npm audit` kontrolleri uygulandı. Sonrasında backend açıkları 0'a indirildi, frontend'deki kritik açıklar giderildi, CI'a bağımlılık denetimi ile Trivy image taraması ve SBOM üretimi eklendi. Kalan frontend `devDependencies` riskleri `docs/findings.md` içinde açıklandı. |
| F-04 — Container ve deployment dosyalarının eksikliği | Yüksek | Başlangıçta frontend, backend ve ETL için Dockerfile, Kubernetes manifesti ve CI/CD pipeline bulunmuyordu. Bu nedenle proje tekrarlanabilir biçimde kurulamaz, dağıtılamaz veya doğrulanamazdı. Bu bulgu, Core Criteria 2–8 kapsamındaki çalışmalar tamamlandıkça çözüldü: Dockerfile ve `.dockerignore` dosyaları, Docker Compose, Kubernetes Deployment/StatefulSet/Service/CronJob manifestleri, PVC, Secret ve ConfigMap yapısı, CI pipeline, monitoring, backup/restore ve kontrollü deployment/rollback eklendi. |

F-08 ilk ele alındı çünkü doğrudan servis kesintisine neden oluyordu. F-01 güvenlik riski taşıdığı için ikinci kritik bulguydu; başlangıçta kısmi iyileştirme yapıldı, daha sonra CI güvenlik kontrolleriyle kapsamı genişletildi. F-04 ise tek bir kod düzeltmesiyle kapanmayacak yapısal bir bulguydu; case'in containerization, orkestrasyon, CI/CD, ETL, logging, güvenlik ve backup/restore kriterleri tamamlandıkça giderildi.

---

## 3. Kapsam Dışında Bırakılan Konular

Hangi sorunları bilinçli olarak düzeltmediniz veya kapsam dışında bıraktınız? Bu kararların gerekçelerini açıklayın.

**Cevap:**

Core Criteria 1–9 tamamlandı. Üst kriterlerde ileri gözlemlenebilirlik, ileri güvenlik ve ileri felaket kurtarma alanları seçildi:

- **Üst Kriter 4:** Kubernetes tabanlı monitoring, Slack alarmı, throttling ve `RESOLVED` bildirimi
- **Üst Kriter 5:** Trivy container image taraması ve CycloneDX SBOM üretimi
- **Üst Kriter 7:** SHA-256 doğrulamalı backup/restore ve izole MongoDB container'ında otomatik backup doğrulaması

Aşağıdaki konular bilinçli olarak kapsam dışında bırakıldı:

| Konu | Gerekçe |
| --- | --- |
| Public cloud, çoklu node ve yüksek erişilebilirlik | Çözüm yerel k3d ortamında doğrulandı. MongoDB replica set, çoklu node, otomatik failover, HPA ve PDB gerçek production altyapısı ve kapasite planlaması gerektirir. |
| Helm, Kustomize ve Terraform | Mevcut Kubernetes manifestleri case kapsamındaki yerel dağıtım için yeterlidir. Ortam sayısı ve cloud kaynakları arttığında Helm/Kustomize ile ortam ayrımı, Terraform ile altyapı kurulumu anlamlı hale gelir. |
| GitOps ve tam otomatik CD | GitHub Actions image üretip GHCR'ye yayınlar. Yerel cluster'a dış erişim açmamak için deployment kontrollü olarak `deploy-local.sh` ile manuel başlatılır. Argo CD veya Flux kurulmadı. |
| Prometheus, Grafana ve merkezi log toplama | Backend ve ETL sağlık durumu, Kubernetes CronJob ve Slack alarmı ile izlenmektedir. Metrik depolama, dashboard ve merkezi log altyapısı bu yerel case için ek operasyonel yük oluşturacağı için uygulanmadı. |
| Harici cluster erişilebilirlik izleme | Monitoring CronJob'ı cluster içinde çalıştığından cluster veya Kubernetes API tamamen erişilemezse bildirim üretemez. Production ortamında bağımsız harici uptime monitoring gerekir. |
| Dar CORS allowlist ve tam API şema doğrulaması | API hata yönetimi ve MongoDB kesintisi davranışı iyileştirildi; ancak Joi veya Zod ile tam request-body şema doğrulaması ve production origin allowlist'i eklenmedi. |
| NetworkPolicy ve merkezi Secret yönetimi | Kubernetes Secret ve ConfigMap ayrımı uygulandı. NetworkPolicy, External Secrets Operator, Vault veya cloud Secret Manager entegrasyonu ile otomatik Secret rotasyonu uygulanmadı. |
| Image signing, policy as code ve yayın engelleme | Trivy taraması ve SBOM üretimi raporlama amaçlıdır. Güvenlik açıkları CI çalışmasını otomatik olarak durdurmaz. Image signing ve politika tabanlı yayın engelleme eklenmedi. |
| Otomatik, uzak ve şifreli backup | Backup/restore ve izole restore doğrulaması uygulandı; ancak backup manuel başlatılır, retention otomatik temizlenmez ve backup'lar aynı yerel bilgisayarda tutulur. Object storage, şifreleme ve point-in-time recovery uygulanmadı. |

Bu kararlar, önce servis sürekliliği, güvenlik açıkları, tekrarlanabilir deployment, ETL doğruluğu ve backup/restore gibi zorunlu kriterleri tamamlamak için alındı.

---

## 4. Hedef Ortam Seçimi

Cloud veya sanal makine tercihinin gerekçesi nedir? Gerçek bir production ortamında mevcut çözümden farklı olarak hangi bileşenleri veya yaklaşımları kullanırdınız?

**Cevap:**

Hedef ortam olarak Docker Desktop üzerinde çalışan yerel k3d Kubernetes cluster'ı seçildi. Bu seçim, case'in Kubernetes, containerization, CI, ETL CronJob, monitoring, backup/restore ve rollback gereksinimlerini cloud maliyeti oluşturmadan ve tekrarlanabilir şekilde doğrulamayı sağladı.

k3d, standart Kubernetes kaynaklarını kullanmayı mümkün kıldı: Deployment, StatefulSet, Service, CronJob, PersistentVolumeClaim, ConfigMap, Secret ve RBAC. Böylece çözüm yalnızca Docker Compose ile sınırlı kalmadı; Kubernetes üzerindeki çalışma davranışı yerel ortamda test edildi.

Gerçek production ortamında yönetilen Kubernetes ve yönetilen MongoDB tercih ederdim. Örneğin AWS EKS, Azure AKS veya Google GKE üzerinde çoklu availability zone kullanan bir cluster; MongoDB için ise replica set ve otomatik failover sağlayan MongoDB Atlas gibi yönetilen bir hizmet kullanırdım.

Production ortamında mevcut çözümden farklı olarak aşağıdaki bileşenleri eklerdim:

| Alan | Production yaklaşımı |
| --- | --- |
| Ağ ve dış erişim | VPC/VNet, private subnet, Load Balancer veya Ingress Controller, TLS sertifikaları, HTTPS ve gerekirse WAF |
| Yüksek erişilebilirlik | Birden fazla node, backend/frontend için çoklu replica, HPA, PDB ve topology spread kuralları |
| MongoDB | Çoklu node replica set, otomatik failover, yönetilen disk, bağlantı havuzu ve kapasite izleme |
| Altyapı yönetimi | Terraform veya OpenTofu ile network, cluster, IAM ve cloud kaynaklarının tekrarlanabilir kurulumu |
| Manifest yönetimi | Helm veya Kustomize ile development, test ve production ortamlarının ayrı değerlerle yönetimi |
| Secret yönetimi | Cloud Secret Manager, HashiCorp Vault veya External Secrets Operator ile merkezi Secret yönetimi ve otomatik rotasyon |
| Güvenlik | NetworkPolicy, dar CORS allowlist'i, tam API şema doğrulaması, image signing, policy as code ve yayın engelleme kuralları |
| CI/CD | GitHub OIDC ile kısa ömürlü cloud erişimi, GitOps yaklaşımı, kontrollü production onayı, canary veya blue-green deployment |
| Gözlemlenebilirlik | Prometheus, Grafana, merkezi log toplama, dashboard, SLI/SLO tanımları ve cluster dışı uptime monitoring |
| Felaket kurtarma | Zamanlanmış backup, şifreli object storage, off-site kopya, retention politikası, point-in-time recovery ve periyodik restore tatbikatı |

Yerel k3d ortamı teknik kararları ve temel operasyonel akışları doğrulamak için uygundur. Production ortamında ise erişilebilirlik, veri dayanıklılığı, güvenlik, kapasite ve felaket kurtarma gereksinimleri için yönetilen ve çoklu node içeren altyapı gerekir.

---

## 5. MongoDB Yaklaşımı

MongoDB için kullandığınız deployment ve servis yaklaşımını neden seçtiniz? Değerlendirdiğiniz alternatifleri, avantajları, dezavantajları ve operasyonel trade-off’ları açıklayın.

**Cevap:**

MongoDB, Kubernetes üzerinde tek replikalı `StatefulSet` olarak çalıştırıldı. Veritabanı Pod'u `mongodb-0` sabit adıyla oluşturulur ve verisi `mongo-data` PersistentVolumeClaim üzerinde tutulur. Bu yaklaşım, Pod yeniden oluşturulsa bile verinin Pod yaşam döngüsünden bağımsız kalmasını sağlar.

MongoDB için `mongodb-service` adlı headless Service kullanıldı. Headless Service, StatefulSet Pod'una sabit DNS kimliği sağlar ve backend ile ETL'nin MongoDB'ye yalnızca cluster içinden erişmesini mümkün kılar. MongoDB dış erişime açılmadı.

| Bileşen | Seçim | Gerekçe |
| --- | --- | --- |
| Workload | `StatefulSet` | MongoDB stateful bir bileşendir. Sabit Pod adı ve kalıcı volume ilişkisi gerekir. |
| Depolama | PersistentVolumeClaim | MongoDB verisinin Pod silinse veya yeniden başlasa da korunmasını sağlar. |
| Service | Headless Service | `mongodb-0` için sabit ağ kimliği ve cluster içi DNS erişimi sağlar. |
| Replica sayısı | 1 | Yerel k3d case ortamında kaynak tüketimini ve operasyonel karmaşıklığı düşük tutar. |
| Dış erişim | Yok | MongoDB yalnızca backend ve ETL tarafından cluster içinden erişilir. |

Değerlendirilen alternatifler:

| Alternatif | Avantaj | Dezavantaj | Tercih edilme durumu |
| --- | --- | --- | --- |
| Deployment ve ClusterIP Service | Daha basit kurulum | Sabit Pod kimliği ve stateful volume yönetimi için daha zayıf bir model | Stateless uygulamalar için daha uygundur |
| StatefulSet ve ClusterIP Service | Tek MongoDB Pod'u için yeterli olabilir | StatefulSet Pod'ları için sabit DNS kimliğini doğrudan sağlamaz | Headless Service tercih edildi |
| MongoDB replica set | Yüksek erişilebilirlik, veri replikasyonu ve failover | Çoklu Pod, çoklu volume, quorum, kapasite ve operasyon yönetimi gerektirir | Production için tercih edilir |
| MongoDB Operator veya Helm chart | Hazır kurulum, lifecycle ve replica set yönetimi | Yerel case için ek soyutlama ve karmaşıklık getirir | Büyük veya uzun ömürlü cluster'larda uygundur |
| Yönetilen MongoDB hizmeti | Backup, patching, replikasyon ve failover yönetimi hizmet sağlayıcı tarafından yapılır | Cloud maliyeti ve sağlayıcı bağımlılığı oluşturur | Production için en uygun seçenektir |

Bu çözümün temel trade-off'u, basitlik karşılığında yüksek erişilebilirlikten vazgeçilmesidir. Tek MongoDB replica'sı nedeniyle Pod, node veya yerel disk kaybında otomatik failover bulunmaz. Backup/restore mekanizması veri kurtarma için uygulanmıştır; ancak replica set, uzak yedekleme ve point-in-time recovery yerine geçmez.

Gerçek production ortamında MongoDB Atlas veya cloud üzerinde yönetilen, çoklu availability zone içeren MongoDB replica set kullanırdım. Böylece otomatik failover, izleme, şifreli backup, point-in-time recovery ve daha güvenli operasyon yönetimi sağlanır.

---

## 6. Helm veya Manifest Yönetimi

Çözümünüzde Helm kullandıysanız neden tercih ettiğinizi ve Helm’in bu projede hangi problemi çözdüğünü açıklayın.

Düz Kubernetes manifestleri veya Kustomize gibi alternatiflerle karşılaştırıldığında sağladığı avantajları ve oluşturduğu ek karmaşıklığı belirtin.

Helm kullanmadıysanız tercih ettiğiniz yöntemi ve seçim gerekçenizi açıklayın.

**Cevap:**

Bu çözümde Helm kullanılmadı. Kubernetes kaynakları, bileşenlere göre ayrılmış düz YAML manifestleriyle yönetildi:

- `kubernetes/backend/`
- `kubernetes/frontend/`
- `kubernetes/mongodb/`
- `kubernetes/etl/`
- `kubernetes/monitoring/`

Namespace, ConfigMap, Secret bağımlılıkları, Deployment, StatefulSet, Service ve CronJob kaynakları ayrı dosyalarda tutuldu. Kurulum sırası README'de açıkça belirtildi.

Düz manifestler, tek bir yerel Kubernetes ortamı bulunan bu case için tercih edildi. Kaynakların tamamı doğrudan görülebildiği için değerlendirme sırasında her bileşenin yapılandırmasını, bağlı olduğu Secret veya ConfigMap'i ve kullandığı Service türünü incelemek kolaydır. Ayrıca Helm chart yapısı, `values.yaml`, template fonksiyonları ve release yönetimi gibi ek katmanlar oluşturmadan Kubernetes kaynaklarına odaklanmayı sağladı.

| Yaklaşım | Avantaj | Dezavantaj |
| --- | --- | --- |
| Düz YAML manifestleri | Basit, görünür, kolay incelenir; tek ortam için yeterlidir | Ortam sayısı arttığında tekrar eden değerler ve bakım yükü oluşur |
| Kustomize | Ortak manifestlerden development, test ve production overlay'leri üretir | Çok sayıda environment ve patch kuralında yapı karmaşıklaşabilir |
| Helm | Tekrarlanan değerleri template ile yönetir; release sürümü, rollback ve hazır chart kullanımı sağlar | Template mantığı, `values.yaml` dosyaları ve chart bağımlılıkları ek karmaşıklık oluşturur |

Bu projede image sürümü güncelleme işlemi Helm release yerine `scripts/deploy-local.sh` ile `kubectl set image` kullanılarak yapıldı. Script, önceki image referanslarını kaydeder ve deployment hatasında bu referanslarla rollback dener.

Gerçek production ortamında birden fazla environment bulunduğu için Helm veya Kustomize kullanırdım. Helm; ortak uygulama chart'ı, sürümlü release yönetimi ve environment bazlı `values` dosyaları için; Kustomize ise mevcut manifestlere az sayıda environment farkı uygulamak için uygun olurdu. Seçim, environment sayısı, yapılandırma çeşitliliği ve release yönetimi ihtiyacına göre yapılmalıdır.

---

## 7. Kubernetes Service Tipleri

Kubernetes Service tiplerini hangi kriterlere göre belirlediniz?

Her servis için neden `ClusterIP`, `NodePort`, `LoadBalancer`, `ExternalName` veya headless Service tercih ettiğinizi açıklayın. Hangi servislerin cluster dışından erişilebilir olması gerektiğini ve gereksiz dış erişimi nasıl engellediğinizi belirtin.

**Cevap:**

Service tiplerini belirlerken üç ölçüt kullandım: bileşenin kullanıcı tarafından erişilmesi gerekip gerekmediği, yalnızca cluster içindeki bileşenlere hizmet verip vermediği ve stateful bir bileşen için sabit ağ kimliği ihtiyacı.

| Servis | Tip | Port | Gerekçe |
| --- | --- | --- | --- |
| `frontend` | NodePort | `30080` → `8080` | Kullanıcının web arayüzüne cluster dışından erişmesi gerekir. Yerel k3d ortamında host port eşlemesiyle tarayıcı erişimi sağlanır. |
| `case-backend` | ClusterIP | `5050` | Backend yalnızca frontend Nginx reverse proxy tarafından çağrılır. Doğrudan dış erişime açılması gerekmez. |
| `mongodb-service` | Headless Service | `27017` | MongoDB StatefulSet Pod'una sabit DNS kimliği sağlar. Backend ve ETL, MongoDB'ye yalnızca cluster içinden erişir. |

`frontend` dış erişime açık tek uygulama servisidir. Nginx, React statik dosyalarını sunar ve tarayıcıdan gelen `/api` isteklerini cluster içindeki `case-backend` Service'ine yönlendirir. Böylece backend API'si ayrı bir NodePort veya LoadBalancer ile dışarı açılmaz.

`case-backend` için `ClusterIP` seçildi çünkü bu tip, yalnızca namespace içindeki Pod'ların erişebileceği bir sanal IP sağlar. Backend'in MongoDB bağlantısı da yalnızca cluster içinden yapılır.

`mongodb-service` için headless Service seçildi. Headless Service, normal Service'lerdeki tek sanal IP yerine StatefulSet Pod'unun DNS kimliğini kullanır. Bu yapı, `mongodb-0` gibi stateful Pod'lara sabit erişim sağlamak için uygundur.

`LoadBalancer` kullanılmadı çünkü hedef ortam public cloud üzerinde değildir. Yerel k3d ortamında cloud Load Balancer sağlayıcısı bulunmaz; frontend erişimi için NodePort yeterlidir.

`ExternalName` kullanılmadı çünkü cluster içinden erişilmesi gereken harici, DNS tabanlı bir servis yoktur. GitHub API ve Slack webhook gibi dış servisler, uygulama ve monitoring Pod'larının doğrudan HTTPS istekleriyle kullanılır.

ETL ve monitoring bileşenleri için Service tanımlanmadı. Bunlar kullanıcı isteği alan uzun ömürlü servisler değildir; CronJob tarafından oluşturulan geçici Job/Pod'lar olarak çalışırlar.

Gereksiz dış erişim, backend ve MongoDB için NodePort veya LoadBalancer oluşturmadan engellendi. Bu çözümde NetworkPolicy bulunmasa da Service tipleriyle doğrudan dış erişim yüzeyi frontend ile sınırlandırılmıştır. Production ortamında buna ek olarak NetworkPolicy, Ingress, HTTPS/TLS, WAF ve dar ağ erişim kuralları uygulanmalıdır.

---

## 8. Kubernetes Workload Türleri

Uygulama bileşenleri için kullandığınız iş yükü (workload) türlerini hangi kriterlere göre seçtiniz?

Frontend, backend, MongoDB ve ETL bileşenlerinde neden `Deployment`, `StatefulSet`, `Job`, `CronJob` veya farklı bir workload türü kullandığınızı açıklayın.

Karar verirken aşağıdaki konuları nasıl değerlendirdiğinizi belirtin:

- Stateless veya stateful çalışma modeli
- Kalıcı depolama ihtiyacı
- Pod kimliği ve sıralı çalışma gereksinimi
- Çalışma sıklığı
- Yeniden başlatma davranışı
- Ölçeklenebilirlik ihtiyacı

**Cevap:**

Workload türlerini seçerken bileşenin stateful olup olmadığı, kalıcı depolama ihtiyacı, çalışma süresi, çalışma sıklığı, yeniden başlatma davranışı ve ölçeklenme ihtiyacı değerlendirildi.

| Bileşen | Workload türü | Gerekçe |
| --- | --- | --- |
| Frontend | Deployment | React çıktısını Nginx ile sunan stateless bir bileşendir. Pod kaybolduğunda yeni Pod aynı image ile yeniden oluşturulabilir. |
| Backend | Deployment | Express API stateless çalışır; uygulama verisi MongoDB'de tutulur. Deployment istenen replica sayısını korur ve Pod hatasında yeni Pod oluşturur. |
| MongoDB | StatefulSet | MongoDB stateful bir bileşendir. Sabit Pod kimliği, kalıcı volume ve öngörülebilir başlatma davranışı gerektirir. |
| ETL | CronJob | ETL sürekli çalışan bir servis değildir; saatte bir çalışmalıdır. `github-etl` CronJob'ı her saat için ayrı bir Job oluşturur. |
| Monitoring | CronJob | Monitoring sürekli açık bir Pod yerine dakikada bir çalışacak kontrol görevi olarak tasarlandı. Her kontrol için ayrı Job oluşturulur. |

Frontend ve backend için Deployment seçildi çünkü bu bileşenlerin yerel disk üzerinde kalıcı veri tutma ihtiyacı yoktur. Uygulama durumu MongoDB'de bulunduğu için Pod yeniden başlatıldığında aynı image ve yapılandırmayla tekrar çalışabilir. Mevcut yerel ortamda birer replica kullanılır; production ortamında CPU, bellek, istek sayısı ve gecikme metriklerine göre yatay olarak ölçeklenebilirler.

MongoDB için StatefulSet kullanıldı. `mongodb-0` sabit Pod kimliğine sahiptir ve verisini `mongo-data` PersistentVolumeClaim üzerinde tutar. Pod yeniden oluşturulsa bile veri volume üzerinde kalır. StatefulSet ayrıca stateful bileşenlerde gerekli olan kararlı Pod kimliği ve sıralı başlatma davranışını sağlar.

ETL için Deployment kullanılmadı çünkü ETL'nin sürekli istek karşılayan bir servis olarak çalışması gerekmez. `github-etl` CronJob'ı her saat başında UTC zaman diliminde çalışır ve tamamlandığında sona eren bir Job oluşturur. ETL'nin `github_id` alanı üzerinden idempotent upsert kullanması, aynı repository verisinin sonraki çalışmalarda tekrar işlenmesini güvenli hale getirir.

Monitoring de CronJob olarak tasarlandı. `monitoring-check` her dakika backend ve ETL durumunu Kubernetes API üzerinden değerlendirir, sonucu ConfigMap'te saklar ve gerekirse Slack bildirimi gönderir. Sürekli çalışan ayrı bir monitoring Deployment yerine kısa süreli kontroller kullanılması, yerel case ortamında kaynak tüketimini düşük tutar.

MongoDB'nin yatay ölçeklenmesi mevcut tek replikalı yapı ile sağlanmaz. Production ortamında replica set, çoklu node, uygun persistent disk, otomatik failover ve kapasite planlaması gerekir. Frontend ve backend için ise HPA, PDB ve topology spread kurallarıyla daha dayanıklı bir ölçeklenme yaklaşımı uygulanabilir.

---

## 9. Konfigürasyon ve Secret Yönetimi

Uygulama konfigürasyonlarını ve secret bilgilerini nasıl yönettiniz?

Bir secret değeri değiştirildiğinde veya yenilendiğinde uygulamanın yeni değeri güvenli şekilde kullanmasını nasıl sağlarsınız?

**Cevap:**

Konfigürasyon ve gizli bilgiler ayrıştırıldı. Gizli olmayan değerler Kubernetes `ConfigMap`, parola ve bağlantı bilgileri ise Kubernetes `Secret` kaynakları ile container'lara ortam değişkeni olarak aktarılır.

| Kaynak | İçerik | Kullanım amacı |
| --- | --- | --- |
| `app-config` ConfigMap | GitHub kullanıcı adı, ETL veritabanı ve koleksiyon bilgileri | Ortama göre değişebilen, gizli olmayan ETL yapılandırması |
| `mongodb-auth` Secret | MongoDB root ve uygulama kullanıcılarının başlangıç bilgileri | MongoDB ilk kurulumunda kullanıcı oluşturma |
| `backend-mongo-uri` Secret | `ATLAS_URI` | Backend'in MongoDB bağlantısı |
| `etl-mongo-uri` Secret | `ATLAS_URI` | ETL'nin MongoDB bağlantısı |
| `monitoring-slack-webhook` Secret | `SLACK_WEBHOOK_URL` | Slack bildirimleri |

Docker Compose ortamında aynı ayrım `.env.example` ile desteklenir. Gerçek `.env` dosyası, parola, token ve webhook değerleri Git'e eklenmez. Kubernetes Secret değerleri de repository veya container image içinde tutulmaz.

Mevcut yerel çözümde Secret'lar container'lara environment variable olarak aktarılır. Bu nedenle çalışan Pod'lar Secret değiştiğinde değeri otomatik olarak yenilemez. Secret güncellendikten sonra ilgili workload'un yeniden başlatılması gerekir.

Örneğin backend bağlantı URI'si değiştiğinde güvenli süreç şu şekilde olur:

1. Yeni MongoDB kullanıcısı veya yeni parola MongoDB tarafında oluşturulur.
2. `backend-mongo-uri` Secret'ı yeni URI ile güncellenir.
3. Backend Deployment kontrollü rollout ile yeniden başlatılır.
4. `/healthcheck/ready` endpoint'i ve Pod rollout durumu doğrulanır.
5. Eski MongoDB kullanıcısı veya parola, yeni bağlantının çalıştığı doğrulandıktan sonra kaldırılır.

ETL ve monitoring CronJob'ları için yeni oluşturulan Job'lar güncel Secret değerini kullanır. Çalışmakta olan bir Job varsa tamamlanması beklenir veya kontrollü şekilde sonlandırılır. MongoDB StatefulSet için `mongodb-auth` Secret'ını değiştirmek tek başına MongoDB kullanıcı parolalarını değiştirmez; parola değişikliği önce MongoDB içinde yapılmalı, ardından bağlantı Secret'ları güncellenmelidir.

Production ortamında Kubernetes Secret'larına ek olarak cloud Secret Manager, HashiCorp Vault veya External Secrets Operator kullanırdım. Secret değerleri at-rest encryption, sıkı RBAC, audit kayıtları ve otomatik rotasyon ile yönetilirdi. Uygulama bileşenleri yeni Secret değerini kontrollü rollout veya yeniden başlatma ile kullanırdı.

---

## 10. MongoDB Erişim Problemi

MongoDB erişilemez hale gelirse backend uygulaması, readiness/liveness kontrolleri ve kullanıcı istekleri nasıl davranır?

Kullanıcı etkisini azaltmak ve servisin kontrollü şekilde toparlanmasını sağlamak için hangi önlemleri aldınız veya alırdınız?

**Cevap:**

MongoDB erişilemez olduğunda backend süreci çökmez. Başlangıç uygulamasında `MongoServerSelectionError` yakalanmadığı için veritabanındaki kısa süreli bir kesinti Node.js uygulamasını tamamen kapatabiliyordu. Bu davranış F-08 kapsamında düzeltildi.

| Durum | Davranış |
| --- | --- |
| MongoDB erişilebilir | `/healthcheck` ve `/healthcheck/ready` HTTP 200 döndürür. Backend Pod'u Kubernetes Service trafiğine dahil edilir. |
| MongoDB erişilemez | Backend süreci çalışmaya devam eder. `/healthcheck` HTTP 200 döndürür; `/healthcheck/ready` HTTP 503 ve `NOT_READY` döndürür. |
| Kubernetes davranışı | Readiness başarısız olan Pod, Service endpoint'lerinden çıkarılır. Yeni kullanıcı trafiği sağlıksız backend Pod'una yönlendirilmez. |
| API isteği | MongoDB gerektiren istekler geçici olarak başarısız olur. Veritabanı hataları yakalanarak kontrollü hata yanıtı üretilir; Node.js süreci kapanmaz. |
| MongoDB geri geldiğinde | Backend, yeniden başlatılmadan MongoDB bağlantısını tekrar kurar. Readiness tekrar HTTP 200 ve `READY` döndürdüğünde Pod yeniden Service trafiğine alınır. |

Uygulanan önlemler şunlardır:

- `db/conn.mjs` içindeki bağlantı ve asenkron hata yönetimi düzenlendi.
- MongoDB bağlantısının uzun süre beklemesini önlemek için `serverSelectionTimeoutMS: 5000` eklendi.
- MongoDB bağlantı hataları için kontrollü HTTP 503 yanıtı eklendi.
- Liveness ve readiness kontrolleri ayrıldı. Liveness yalnızca backend sürecinin ayakta olup olmadığını, readiness ise MongoDB bağlantısını da kontrol eder.
- Backend Deployment için readiness probe tanımlandı.
- Monitoring CronJob ile backend kullanılabilirliği izlenir; sorun oluştuğunda Slack bildirimi gönderilir.

Bu yaklaşım kullanıcıların sağlıksız bir Pod'a yönlendirilmesini engeller, ancak MongoDB tamamen erişilemezken veri gerektiren işlemlerin başarılı olmasını garanti etmez. Kullanıcı geçici hata görebilir; amaç tüm backend servisinin çökmesini önlemek ve MongoDB geri geldiğinde kontrollü toparlanmayı sağlamaktır.

Production ortamında buna ek olarak MongoDB replica set, çoklu availability zone, bağlantı havuzu izleme, timeout ve retry politikaları, circuit breaker yaklaşımı, çoklu backend replica, HPA ve dışarıdan erişilebilirlik izleme kullanırdım.

---

## 11. Hatalı Deployment ve Rollback

Hatalı bir sürüm deploy edildiğinde problemi nasıl tespit edersiniz?

Rollback işlemini hangi yöntemle gerçekleştirirsiniz ve önceki çalışan sürümün güvenli şekilde devreye alındığını nasıl doğrularsınız?

**Cevap:**

Mevcut yerel çözümde `scripts/deploy-local.sh`, backend ve frontend rollout durumlarını `kubectl rollout status --timeout=180s` ile kontrol eder. Pod'un image çekememesi, çökmesi veya readiness kontrolünden geçememesi durumunda Bash `ERR` trap mekanizması, deployment öncesinde kaydedilen image SHA referanslarını `kubectl set image` ile geri uygular.

Bu yöntem altyapı seviyesindeki rollout hatalarını yakalar; ancak Pod'un `1/1 Ready` olması uygulamanın iş mantığının doğru çalıştığını garanti etmez. API tüm isteklerde HTTP 500 dönebilir, yanlış environment variable kullanabilir veya veritabanı şemasıyla uyumsuz olabilir. Bu tür bir durumda yalnızca Kubernetes probe'larına dayanan mevcut script rollback tetiklemez.

Production ortamında manuel Bash script yerine GitOps yaklaşımı kullanırdım. Argo CD veya Flux, Git repository'deki deklaratif hedef sürümü cluster'a uygular. Argo Rollouts veya Flagger ise yeni sürümü canary olarak önce trafiğin küçük bir bölümüne, örneğin `%10` oranında açar.

Canary aşamasında Prometheus üzerinden aşağıdaki kalite sinyalleri değerlendirilir:

- HTTP 5xx hata oranı
- p95 ve p99 API gecikmesi
- İstek başarısızlık oranı
- MongoDB bağlantı ve sorgu hata oranı
- Smoke test veya sentetik CRUD kontrolü sonucu

Belirlenen SLO eşikleri aşılırsa Argo Rollouts veya Flagger, yeni sürümün trafiğini artırmadan otomatik ve deklaratif rollback yapar. Başarılı analizlerden sonra trafik aşamalı olarak `%25`, `%50` ve `%100` seviyesine çıkarılır.

Veritabanı şema değişiklikleri image rollback'inden ayrı yönetilmelidir. Production ortamında geriye uyumlu migration, ayrı migration Job'ı, schema version kontrolü ve backup planı kullanırdım.

---

## 12. Ölçeklenebilirlik ve Darboğazlar

Trafik 10 kat arttığında ilk darboğazın nerede oluşmasını beklersiniz?

Hangi bileşenleri, hangi metriklere ve eşiklere göre ölçeklersiniz? Veritabanı bağlantıları, kaynak kullanımı ve bağımlı servisleri nasıl değerlendirirsiniz?

**Cevap:**

Trafik 10 kat arttığında ilk kalıcı darboğazın MongoDB olması beklenir. Mevcut yapıda MongoDB tek replica ile çalışır ve tüm CRUD yazma işlemleri aynı instance'a gider. Backend de tek replica olduğu için ilk sınır olabilir; kesin sıralama yük testiyle belirlenmelidir.

Backend'i yalnızca CPU veya bellek kullanımına göre HPA ile ölçeklemek yeterli değildir. Node.js asenkron ve I/O ağırlıklı çalıştığı için MongoDB yavaşladığında CPU kullanımı düşük kalabilir; buna rağmen bekleyen istek sayısı, p95 gecikme, bağlantı havuzu kuyruğu ve bellek kullanımı artabilir.

| Bileşen | İzlenecek metrikler | Yaklaşım |
| --- | --- | --- |
| Backend | RPS, in-flight istek sayısı, p95/p99 gecikme, 5xx oranı, Event Loop gecikmesi, bellek | Custom Metrics ile HPA; CPU yalnızca destekleyici metrik |
| MongoDB | Aktif bağlantı sayısı, connection-pool wait time, sorgu gecikmesi, CPU, bellek, disk I/O, disk doluluk oranı | Önce kaynak ve indeks optimizasyonu; sonra replica set ve read replica |
| Frontend | İstek hızı, p95 gecikme, 5xx oranı, CPU/bellek | Deployment replica artışı ve CDN |
| ETL | Job süresi, GitHub API 403/429 yanıtları, MongoDB yazma gecikmesi | Paralelliği sınırlamak, API çağrılarını ve zamanlamayı optimize etmek |

Backend replica sayısı artırıldığında her Pod MongoDB için ayrı connection pool açabilir. Bu nedenle Node.js MongoDB istemcisinde `maxPoolSize` sınırı belirlenmelidir.

```text
Pod başına maxPoolSize
≤ (MongoDB bağlantı kapasitesi - ETL, monitoring ve yönetim payı)
  / maksimum backend replica sayısı
```

Bu bağlantı bütçesi aşılırsa HPA backend'i ölçeklese bile MongoDB connection exhaustion, sorgu kuyruğu ve servis gecikmesi oluşabilir. Bu nedenle backend HPA kararı MongoDB aktif bağlantı oranı ve connection-pool wait time ile birlikte değerlendirilmelidir.

Read replica'lar okuma yükünü azaltabilir; create, update ve delete işlemleri yine primary node'a gider. Yazma yükü artmaya devam ederse replica set, veri modeli, indeksler ve ileri aşamada sharding değerlendirilmelidir.

---

## 13. Logging, Monitoring ve Alarm Yönetimi

Hangi logları, metrikleri ve alarmları oluşturdunuz?

Bir incident sırasında problemi teşhis etmek için ilk olarak hangi dashboard, log, metrik veya alarm kayıtlarını incelersiniz?

**Cevap:**

Mevcut çözümde merkezi log toplama veya dashboard altyapısı yoktur. İzleme; Kubernetes kaynak durumları, Pod ve Job logları, `monitoring-check` CronJob çıktıları, `monitoring-state` ConfigMap'i ve Slack bildirimleri üzerinden yapılır.

| Alan | Mevcut log veya sinyal |
| --- | --- |
| Backend | HTTP hata kayıtları, MongoDB bağlantı hataları, readiness ve liveness sonuçları |
| ETL | `fetched`, `inserted`, `updated`, `unchanged` sayaçları; GitHub API ve MongoDB hata kayıtları |
| Kubernetes | Pod durumu, Deployment replica sayısı, restart sayısı, event'ler |
| Monitoring | `BACKEND_UNAVAILABLE`, `ETL_OVERDUE`, `ETL_JOB_FAILED`, `ETL_NO_SUCCESS`, `ETL_SUSPENDED` alarm durumları |
| Slack | İlk alarm, 15 dakikalık throttling, `RESOLVED`, webhook başarı veya hata sonuçları |
| Backup | Backup/restore sonucu, SHA-256 doğrulaması ve restore script süresi |

Bir incident sırasında önce Slack alarmındaki bileşen ve zaman bilgisini, ardından `monitoring-state` ConfigMap'indeki aktif alarm ve `last_sent` durumunu incelerim. Sonrasında Kubernetes Pod, Deployment, Job ve event durumlarını; ilgili backend, ETL veya monitoring loglarını kontrol ederim.

```bash
kubectl get pods,deployments,cronjobs,jobs -n devops-case
kubectl get events -n devops-case --sort-by='.lastTimestamp'
kubectl get configmap monitoring-state -n devops-case -o yaml
```

Backend problemi varsa backend logları, readiness sonucu, MongoDB Pod/PVC durumu ve MongoDB logları incelenir. ETL problemi varsa son ETL Job logları, CronJob `suspend` değeri, GitHub API erişimi ve MongoDB bağlantısı kontrol edilir.

Mevcut log yaklaşımının önemli sınırı, istekler arasında Correlation ID bulunmamasıdır. Yoğun trafikte aynı anda birçok isteğin logu karışabilir; belirli bir kullanıcı isteğinin frontend, backend ve MongoDB hata kayıtları boyunca izlenmesi zorlaşır.

Production ortamında her isteğe `X-Request-ID` veya Trace ID atanmasını sağlardım. Nginx veya backend bu kimliği üretir; frontend, Nginx, backend ve bağımlı servis çağrıları boyunca aynı kimlik taşınır. Backend loglarında en az şu alanlar yapılandırılmış JSON olarak yazılırdı:

```text
timestamp, level, service, pod, request_id, method, path,
status_code, duration_ms, mongo_error
```

Böylece örneğin bir kullanıcıya dönen hata üzerindeki `request_id`, merkezi log sistemi olmasa bile `kubectl logs` çıktısında `grep` ile filtrelenebilir. Merkezi log toplama olduğunda ise aynı kimlik Kibana veya Grafana Loki üzerinde tüm servisler boyunca aranabilir.

Production ortamında ayrıca Prometheus ile metrik toplar, Grafana dashboard'ları kurar, Loki veya ELK ile merkezi log toplama kullanırdım. OpenTelemetry ile trace bilgisi eklenerek bir isteğin frontend, backend, MongoDB ve dış API çağrılarındaki gecikmesi uçtan uca izlenebilirdi.

---

## 14. Güvenlik Riskleri

Çözümünüzde gördüğünüz en önemli üç güvenlik riski nedir?

Bu riskleri azaltmak için uyguladığınız veya production ortamında uygulayacağınız kontrolleri açıklayın.

**Cevap:**

Önemli güvenlik risklerinden biri container runtime güvenliğidir. Mevcut çözümde backend, frontend ve ETL container'ları non-root kullanıcıyla çalışır; `allowPrivilegeEscalation: false`, `capabilities.drop: ALL` ve `seccompProfile: RuntimeDefault` ayarları kullanılır. Monitoring container'ında ayrıca `readOnlyRootFilesystem: true` bulunur.

Backend ve frontend container'larında `readOnlyRootFilesystem: true` henüz uygulanmamıştır. Production ortamında bu ayarı eklerdim. Böylece bir RCE zafiyeti istismar edilse bile saldırgan container dosya sistemi katmanına kalıcı araç veya payload yazamaz.

Bu ayar uygulanırken uygulamanın gerçekten yazması gereken yollar ayrıca tanımlanmalıdır. Örneğin Nginx için `/var/cache/nginx`, `/var/run` veya `/tmp` gibi gerekli dizinler `emptyDir` volume ile yazılabilir yapılmalıdır. Aksi halde read-only root filesystem nedeniyle container başlatılamaz. Bu kontrol RCE'yi tamamen engellemez; bellek içi saldırılar veya açıkça yazılabilir volume'ler için ek savunmalar gerekir.

Diğer önemli riskler ve production kontrolleri:

| Risk | Production kontrolü |
| --- | --- |
| Geniş CORS ve eksik API şema doğrulaması | Dar CORS allowlist'i, Zod/Joi validation, rate limiting, kimlik doğrulama ve HTTPS |
| Manuel Secret yönetimi | Cloud Secret Manager veya Vault, Workload Identity, RBAC, otomatik Secret rotasyonu |
| NetworkPolicy eksikliği | Default-deny NetworkPolicy ve yalnızca gerekli Pod'lar arasında izinli trafik |
| Supply-chain riski | Trivy, SBOM, image signing, digest doğrulaması ve kritik açıkta image yayınını engelleyen politika |

---

## 15. Python ETL Güncelleme Yaklaşımı

Python ETL aynı repository bilgisini tekrar aldığında mevcut kaydı nasıl bulup güncelliyor? Benzersiz kayıt anahtarı olarak hangi alanı kullandınız ve duplicate oluşmadığını hangi ekran görüntüsü veya çıktı ile gösterdiniz?

**Cevap:**

ETL, GitHub API'den alınan her repository için GitHub'ın değişmeyen sayısal repository kimliği olan `github_id` alanını kullanır. Bu alan MongoDB'de benzersiz indeks olarak tanımlanmıştır.

Her repository için MongoDB'de aşağıdaki mantıkla işlem yapılır:

```python
collection.update_one(
    {"github_id": repository["id"]},
    {"$set": repository_data},
    upsert=True
)
```

İlk çalıştırmada `github_id` ile eşleşen kayıt bulunmazsa `upsert=True` yeni belge oluşturur. Aynı repository sonraki çalıştırmalarda tekrar alındığında aynı `github_id` ile mevcut belge bulunur ve güncellenir. MongoDB'deki unique index de aynı kimlikle ikinci bir belge eklenmesini engeller.

Doğrulama sırasında aynı üç repository ikinci kez işlendi. İkinci ETL çalıştırmasında aşağıdaki sonuç alındı:

```text
fetched=3
inserted=0
updated=3
unchanged=0
```

Koleksiyondaki toplam belge sayısı üç olarak kaldı.

Kanıtlar:

- `docs/screenshots/11-etl-first-import.png`: İlk ETL çalıştırmasında repository verilerinin MongoDB'ye kaydedildiğini gösterir.
- `docs/screenshots/14-etl-upsert-result.png`: Aynı repository'lerin tekrar işlendiğinde yeni kayıt oluşturulmadan güncellendiğini gösterir.
- `docs/screenshots/15-etl-unique-index.png`: `github_id` alanındaki `unique: true` indeksi ve toplam kayıt sayısını gösterir.

---

## 16. Backup ve Restore Yaklaşımı

MongoDB için hangi yedekleme yöntemini ve saklama konumunu seçtiniz?

Yedekleme sıklığı, retention süresi, RPO ve RTO hedefleriniz nedir ve ölçtüğünüz gerçek geri yükleme süresi ne kadar oldu?

Yedeğin bozuk veya eksik olmasına karşı hangi doğrulamayı yaparsınız; gerçek bir production ortamında bu yaklaşımı nasıl farklılaştırırdınız?

Runbook’unuzu `docs/backup-restore.md` içinde paylaşın ve kanıtları `TESLIM_KANITLARI.md` dosyasından referanslayın.

**Cevap:**

Mevcut çözümde backup, yerel bilgisayardan çalıştırılan `scripts/backup.sh` ile alınır. Script, Kubernetes'teki `mongodb-0` Pod'unda `mongodump` çalıştırır; archive dosyalarını `backups/YYYYMMDDTHHMMSSZ/` dizinine indirir ve SHA-256 checksum oluşturur. Bu yaklaşım case için çalışır ve uçtan uca doğrulanmıştır; ancak production için uygun nihai mimari değildir.

Production ortamında backup sürecini Kubernetes içinde çalışan bir CronJob olarak tasarlardım. CronJob, cloud Workload Identity kullanan bir ServiceAccount ile çalışır; örneğin AWS üzerinde IRSA üzerinden yalnızca ilgili S3 bucket'a yazma yetkisi alır.

Backup Job'ı MongoDB dump'ını geçici yerel diske yazmadan stream olarak şifreli object storage'a aktarır. Kavramsal akış şu şekildedir:

```text
mongodump archive stream
→ encryption
→ immutable object storage
```

AWS örneğinde archive verisi S3'e SSE-KMS şifrelemesiyle yüklenir. S3 Object Lock ile silme veya değiştirme koruması uygulanır. Lifecycle policy, retention süresi dolan yedekleri otomatik yönetir. Backup'lar farklı availability zone veya bölgedeki bağımsız depolamada tutulur.

Production çözümünde ayrıca:

- Zamanlanmış günlük backup ve daha sık incremental veya oplog tabanlı backup
- Point-in-time recovery
- Otomatik checksum ve restore doğrulaması
- Düzenli restore tatbikatı
- Restore Job'ının izole ortamda çalıştırılması
- Backup başarısızlığı için alarm ve SLO takibi

uygulanırdı.

Bu yaklaşım, mevcut host makineye bağlı manuel script modelini kaldırır; yedekleme, erişim kontrolü, şifreleme, retention ve felaket kurtarma sürecini Kubernetes ve cloud altyapısı içinde yönetilebilir hale getirir.

---

## Ek Notlar

Case kapsamında özellikle belirtmek istediğiniz ek kararlar, sınırlamalar veya sonraki geliştirme adımları varsa bu bölümde açıklayabilirsiniz.

**Cevap:**

Bu çalışma, sağlanan uygulamayı yeniden yazmak yerine production çalışma koşullarını doğrudan etkileyen sorunları önceliklendirerek iyileştirmeye odaklandı.

Önemli mimari kararlar:

- Docker Compose yerel doğrulama, k3d ise Kubernetes dağıtımı için kullanıldı.
- CI, build, test, image üretimi ve GHCR yayınlamayı otomatikleştirir. Yerel Kubernetes cluster'ına deployment, cluster'ı GitHub-hosted runner'a açmamak için kontrollü olarak `scripts/deploy-local.sh` ile yapılır.
- MongoDB dış erişime açılmadı; backend `ClusterIP`, MongoDB headless Service ve frontend NodePort kullanıldı.
- MongoDB kesintisinde backend'in çökmesini önlemek için hata yönetimi, readiness davranışı ve bağlantı timeout ayarları iyileştirildi.
- ETL, `github_id` unique index'i ve upsert yaklaşımıyla idempotent hale getirildi.
- Backup/restore, gerçek veri kaybı senaryosuyla hem MongoDB hem React arayüzü üzerinden doğrulandı.

Üst kriterler kapsamında; Slack tabanlı doğrulanmış backend alarmı ve throttling, Trivy image taraması ile CycloneDX SBOM üretimi, SHA-256 doğrulamalı backup/restore ve restore kanıtları uygulandı.

Çözüm yerel Kubernetes ortamında test edilmiştir. Production ortamında öncelikli sonraki adımlar; çoklu node ve MongoDB replica set, HTTPS/TLS, NetworkPolicy, merkezi Secret yönetimi ve otomatik rotasyon, Prometheus/Grafana, merkezi log toplama, GitOps, zamanlanmış ve uzak şifreli backup ile point-in-time recovery olacaktır.

Tüm teknik kararlar, kurulum adımları, test sonuçları, ekran görüntüleri ve sınırlamalar README, `docs/findings.md`, `docs/backup-restore.md` ve `TESLIM_KANITLARI.md` dosyalarında belgelenmiştir.
