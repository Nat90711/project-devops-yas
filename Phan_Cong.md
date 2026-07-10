# Phân công Đồ án 2 – Xây dựng hệ thống CD

> **Mục tiêu điểm số: 10/10** = 6đ bắt buộc + 2đ ArgoCD + 2đ Service Mesh
>
> **Hạ tầng:** 1 GCP VM dùng chung – 32GB RAM, chạy k3s (Kubernetes), toàn bộ thành viên SSH vào cùng 1 máy.
>
> **Chiến lược:** TV3 dùng **ArgoCD thay thế Jenkins CD** cho dev/staging (đề cho phép: *"Bỏ qua phần Jenkins CD nếu làm phần Nâng Cao"*). TV4 làm Service Mesh Istio.

---

## Tổng quan công việc & Điểm số

| Hạng mục | Điểm | Trạng thái | Người phụ trách |
|---|---|---|---|
| K8S Cluster – Dựng môi trường & deploy YAS | 2đ (bắt buộc) | 🟡 Còn phần 5 (namespace dev/staging) | **Thành viên 1** |
| CI Pipeline – Build & Push image theo commit ID | 2đ (bắt buộc) | ⬜ Chưa làm | **Thành viên 2** |
| CD Pipeline – `developer_build` + `cleanup` job | 2đ (bắt buộc) | ⬜ Chưa làm | **Thành viên 2** |
| ArgoCD – GitOps cho `dev` và `staging` | 2đ (nâng cao) | ⬜ Chưa làm | **Thành viên 3** |
| Service Mesh – Istio + mTLS + AuthzPolicy + Retry | 2đ (nâng cao) | ⬜ Chưa làm | **Thành viên 4** |
| Báo cáo & tổng hợp | — | ⬜ Chưa làm | Tất cả |

---

## Thành viên 1 – K8S Cluster ✅ (Gần xong – còn phần 5)

> Các bước 1–4 và 6–7 đã hoàn thành. **Chỉ còn phần 5 bên dưới.**

### ⏳ Phần 5 – Mở rộng scripts để hỗ trợ namespace `dev` và `staging`

TV2 và TV3 sẽ cần namespace `dev` và `staging` sẵn sàng trước khi họ làm việc.

**Sửa `k8s/deploy/deploy-yas-configuration.sh`** để nhận tham số namespace:
```bash
#!/bin/bash
set -x
NAMESPACE=${1:-yas}

helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
  --namespace $NAMESPACE --create-namespace
```

**Sửa `k8s/deploy/deploy-yas-applications.sh`** – thay `--namespace yas` bằng `--namespace $NAMESPACE`:
```bash
#!/bin/bash
set -x
NAMESPACE=${1:-yas}

read -rd '' DOMAIN < <(yq -r '.domain' ./cluster-config.yaml)

PREFIX=""
if [ "$NAMESPACE" != "yas" ]; then
    PREFIX="${NAMESPACE}-"
fi

# Áp dụng $NAMESPACE và ${PREFIX}$DOMAIN vào tất cả lệnh helm bên dưới
# Ví dụ:
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
  --namespace $NAMESPACE --create-namespace \
  --set backend.ingress.host="${PREFIX}backoffice.$DOMAIN"

# ... các service khác tương tự ...
```

**Deploy vào `dev` và `staging`:**
```bash
cd k8s/deploy/
./deploy-yas-configuration.sh dev
./deploy-yas-applications.sh dev

./deploy-yas-configuration.sh staging
./deploy-yas-applications.sh staging
```

**Thêm vào `/etc/hosts` trên từng máy thành viên** (dùng GCP External IP):
```
<GCP_EXTERNAL_IP>  dev-storefront.yas.local.com
<GCP_EXTERNAL_IP>  dev-backoffice.yas.local.com
<GCP_EXTERNAL_IP>  dev-api.yas.local.com
<GCP_EXTERNAL_IP>  staging-storefront.yas.local.com
<GCP_EXTERNAL_IP>  staging-api.yas.local.com
```

**Verify:**
```bash
kubectl get pods -n dev
kubectl get pods -n staging
```

### ✅ Output TV1 còn thiếu
- Screenshot `kubectl get pods -n dev` và `kubectl get pods -n staging` – tất cả Running.
- Scripts `deploy-yas-configuration.sh` và `deploy-yas-applications.sh` đã commit lên repo hỗ trợ tham số namespace.

---

## Thành viên 2 – CI Pipeline + Jenkins Jobs (4đ bắt buộc)

**Mục tiêu:** Bổ sung bước build & push Docker image vào CI pipeline. Tạo Jenkins job `developer_build` và `cleanup_deployment` chạy trên GCP VM.

> **Môi trường thực tế:** Jenkins chạy dưới dạng Docker container trên GCP VM, dùng chung `docker socket` và `kubeconfig` với k3s cluster.

### Bước 0 – Chạy Jenkins trên GCP VM (nếu chưa có)

```bash
# Tạo volume lưu data Jenkins
docker volume create jenkins_home

# Chạy Jenkins container
# Mount docker.sock để Jenkins build được Docker image
# Mount kubeconfig của k3s để Jenkins gọi được kubectl
docker run -d --name jenkins \
  --restart=unless-stopped \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/rancher/k3s/k3s.yaml:/root/.kube/config:ro \
  jenkins/jenkins:lts-jdk17

# Lấy password admin lần đầu
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Mở GCP firewall cho port 8080 để cả nhóm truy cập Jenkins UI:
```bash
gcloud compute firewall-rules create allow-jenkins \
  --allow tcp:8080 \
  --description="Jenkins UI"
```

Cài thêm plugins cần thiết trong Jenkins:
- **Docker Pipeline**, **Git**, **Kubernetes CLI**, **Credentials Binding**

---

### Phần A – CI: Build & Push Docker Image theo Commit ID

**1. Cập nhật Jenkinsfile** thêm stage "Build & Push Image":

```groovy
// Jenkinsfile (thêm vào pipeline CI hiện có từ Đồ án 1)
pipeline {
  agent any

  environment {
    DOCKERHUB_ACCOUNT = 'your-dockerhub-username'   // ← đổi thành account của nhóm
  }

  stages {
    // ... các stage CI cũ (test, build) giữ nguyên ...

    stage('Detect Changed Services') {
      steps {
        script {
          // Chỉ build image cho service có file thay đổi (monorepo)
          def changedFiles = sh(
            script: 'git diff --name-only HEAD~1 HEAD || git diff --name-only HEAD',
            returnStdout: true
          ).trim()

          def allServices = [
            'cart','customer','inventory','location','media','order',
            'payment','payment-paypal','product','promotion','rating',
            'search','tax','recommendation','webhook',
            'storefront-bff','backoffice-bff'
          ]

          env.CHANGED_SERVICES = allServices.findAll { svc ->
            changedFiles.split('\n').any { f -> f.startsWith("${svc}/") }
          }.join(',')

          echo "Services changed: ${env.CHANGED_SERVICES}"
        }
      }
    }

    stage('Build & Push Image') {
      when {
        expression { env.CHANGED_SERVICES != '' }
      }
      steps {
        script {
          def commitId = sh(
            script: 'git rev-parse --short HEAD',
            returnStdout: true
          ).trim()
          env.COMMIT_ID = commitId

          withCredentials([usernamePassword(
            credentialsId: 'dockerhub-credentials',
            usernameVariable: 'DOCKER_USER',
            passwordVariable: 'DOCKER_PASS'
          )]) {
            sh "echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin"

            env.CHANGED_SERVICES.split(',').each { svc ->
              sh """
                docker build -t ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId} ./${svc}
                docker push ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId}
              """
              // Nếu là branch main → cũng push tag latest
              if (env.BRANCH_NAME == 'main') {
                sh """
                  docker tag ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId} \
                             ${env.DOCKERHUB_ACCOUNT}/${svc}:latest
                  docker push ${env.DOCKERHUB_ACCOUNT}/${svc}:latest
                """
              }
            }
          }
          // Lưu lại để TV3 (ArgoCD stage) dùng
          sh "echo ${commitId} > build-info.txt"
          archiveArtifacts artifacts: 'build-info.txt'
        }
      }
    }
  }
}
```

**2. Thêm Docker Hub credentials vào Jenkins:**
- Jenkins UI → `Manage Jenkins` → `Credentials` → `(global)` → `Add Credentials`
- Kind: **Username with password**, ID: `dockerhub-credentials`

**3. Cấu hình Multibranch Pipeline** để trigger CI trên **mọi branch** (không chỉ main):
- Jenkins → `New Item` → **Multibranch Pipeline**
- Branch Sources: GitHub repo URL
- Build Configuration: `Jenkinsfile`
- Scan Triggers: tự động khi có push

---

### Phần B – Jenkins Job: `developer_build`

Tạo job mới: `New Item` → **Pipeline** → tên: `developer_build`

```groovy
// Jenkinsfile_developer_build
pipeline {
  agent any

  parameters {
    // Tên service muốn test (ví dụ: tax, cart, product)
    string(name: 'SERVICE_NAME',
           defaultValue: 'tax',
           description: 'Tên service cần deploy (ví dụ: tax, cart, product, inventory...)')
    // Branch của developer
    string(name: 'BRANCH_NAME',
           defaultValue: 'main',
           description: 'Branch của developer (ví dụ: dev_tax_service)')
  }

  environment {
    DOCKERHUB_ACCOUNT = 'your-dockerhub-username'
    KUBE_NAMESPACE    = "devbuild-${params.SERVICE_NAME}"
  }

  stages {
    stage('Get Commit ID từ branch') {
      steps {
        script {
          // Lấy commit ID mới nhất trên branch của developer
          env.IMAGE_TAG = sh(
            script: "git ls-remote origin refs/heads/${params.BRANCH_NAME} | cut -f1 | cut -c1-7",
            returnStdout: true
          ).trim()

          if (!env.IMAGE_TAG) {
            error("Không tìm thấy branch '${params.BRANCH_NAME}' trên remote!")
          }
          echo "Image tag sẽ dùng: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Deploy service được chọn') {
      steps {
        script {
          // Deploy service của developer với image tag = commit ID của branch đó
          sh """
            helm upgrade --install ${params.SERVICE_NAME} k8s/charts/${params.SERVICE_NAME} \
              --namespace ${env.KUBE_NAMESPACE} \
              --create-namespace \
              --set backend.image.tag=${env.IMAGE_TAG} \
              --set backend.image.repository=${env.DOCKERHUB_ACCOUNT}/${params.SERVICE_NAME} \
              --set backend.service.type=NodePort
          """
        }
      }
    }

    stage('Deploy các service còn lại (image: latest)') {
      steps {
        script {
          // Các service khác dùng image tag latest/main
          def otherServices = [
            'cart','customer','inventory','location','media','order',
            'payment','product','promotion','rating','search','tax',
            'recommendation','webhook','storefront-bff','backoffice-bff'
          ].findAll { it != params.SERVICE_NAME }

          otherServices.each { svc ->
            sh """
              helm upgrade --install ${svc} k8s/charts/${svc} \
                --namespace ${env.KUBE_NAMESPACE} \
                --create-namespace \
                --set backend.image.tag=latest \
                --set backend.image.repository=${env.DOCKERHUB_ACCOUNT}/${svc} \
                --set backend.service.type=NodePort \
                || true
            """
          }
        }
      }
    }

    stage('In thông tin truy cập') {
      steps {
        script {
          def gcpIp = sh(
            script: "curl -s ifconfig.me || hostname -I | awk '{print \$1}'",
            returnStdout: true
          ).trim()

          def nodePort = sh(
            script: "kubectl get svc ${params.SERVICE_NAME} -n ${env.KUBE_NAMESPACE} " +
                    "-o jsonpath='{.spec.ports[0].nodePort}'",
            returnStdout: true
          ).trim()

          echo """
============================================================
✅ DEPLOY THÀNH CÔNG!
------------------------------------------------------------
Service  : ${params.SERVICE_NAME}
Branch   : ${params.BRANCH_NAME}
Image Tag: ${env.IMAGE_TAG}
Namespace: ${env.KUBE_NAMESPACE}

Truy cập: http://${gcpIp}:${nodePort}

Thêm vào /etc/hosts (nếu dùng domain):
${gcpIp}  ${params.SERVICE_NAME}.yas.local.com

Để dọn dẹp: chạy job 'cleanup_deployment' với NAMESPACE=${env.KUBE_NAMESPACE}
============================================================
          """
        }
      }
    }
  }
}
```

---

### Phần C – Jenkins Job: `cleanup_deployment`

Tạo job mới: `New Item` → **Pipeline** → tên: `cleanup_deployment`

```groovy
// Jenkinsfile_cleanup
pipeline {
  agent any

  parameters {
    string(name: 'NAMESPACE',
           defaultValue: '',
           description: 'Namespace cần xóa (lấy từ output của developer_build, ví dụ: devbuild-tax)')
  }

  stages {
    stage('Xác nhận') {
      steps {
        echo "Sẽ xóa namespace: ${params.NAMESPACE}"
        sh "kubectl get pods -n ${params.NAMESPACE} || echo 'Namespace không tồn tại'"
      }
    }

    stage('Cleanup') {
      steps {
        sh """
          # Uninstall tất cả Helm release trong namespace
          helm list -n ${params.NAMESPACE} -q | xargs -I{} helm uninstall {} -n ${params.NAMESPACE} || true

          # Xóa namespace
          kubectl delete namespace ${params.NAMESPACE} --ignore-not-found
          echo "✅ Đã xóa namespace ${params.NAMESPACE}"
        """
      }
    }
  }
}
```

### ✅ Output TV2 (bằng chứng nộp báo cáo)
- Jenkinsfile CI cập nhật với stage detect changed files + build & push image.
- Screenshot Docker Hub: có image với tag là commit ID 7 ký tự.
- Screenshot Jenkins Multibranch Pipeline trigger trên nhiều branch.
- Screenshot job `developer_build`: form nhập tham số + output in rõ URL truy cập.
- Screenshot job `cleanup_deployment` chạy thành công, namespace đã bị xóa.

---

## Thành viên 3 – ArgoCD: GitOps cho `dev` và `staging` (2đ nâng cao)

**Mục tiêu:** Cài ArgoCD lên K8S cluster trên GCP VM. Dùng GitOps để tự động deploy vào `dev` khi CI push image mới, và deploy vào `staging` khi có release tag.

> ✅ **Phần Jenkins CD cho dev/staging được BỎ QUA** vì làm ArgoCD (đúng theo đề).
>
> ⚠️ **Phụ thuộc:** Cần TV1 hoàn thành phần 5 (namespace dev/staging sẵn sàng) và TV2 bắt đầu push image lên Docker Hub trước.

### Bước 1 – Cài đặt ArgoCD lên K8S cluster

```bash
# Tạo namespace argocd
kubectl create namespace argocd

# Cài ArgoCD
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Chờ ArgoCD sẵn sàng
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

**Expose ArgoCD UI ra ngoài (NodePort) để cả nhóm truy cập qua GCP IP:**
```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'

# Xem port được assign
kubectl get svc argocd-server -n argocd
# ArgoCD UI sẽ ở: https://<GCP_EXTERNAL_IP>:<NodePort>
```

Mở firewall GCP cho port NodePort của ArgoCD:
```bash
gcloud compute firewall-rules create allow-argocd \
  --allow tcp:30000-32767 \
  --description="ArgoCD + K8S NodePort"
```

**Lấy password admin và đăng nhập:**
```bash
# Lấy password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Cài ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login (thay <port> bằng NodePort thực tế)
argocd login <GCP_EXTERNAL_IP>:<port> --username admin --insecure
```

---

### Bước 2 – Tạo cấu trúc GitOps trong repo

Tạo thư mục mới trong repo để ArgoCD theo dõi:

```
k8s/
├── deploy/          # Scripts gốc (TV1)
├── charts/          # Helm charts (có sẵn)
└── environments/    # ← TV3 tạo mới
    ├── argocd/
    │   ├── app-dev.yaml
    │   └── app-staging.yaml
    ├── dev/
    │   └── values.yaml
    └── staging/
        └── values.yaml
```

**`k8s/environments/dev/values.yaml`** – image tag sẽ được CI Bot tự động cập nhật:
```yaml
# Image tag mặc định cho môi trường dev
# File này sẽ được CI cập nhật tự động sau mỗi lần build
global:
  imageTag: "latest"
  imageRepository: "your-dockerhub-username"
```

**`k8s/environments/staging/values.yaml`** – chỉ cập nhật khi có release tag:
```yaml
# Image tag cho môi trường staging
# Chỉ cập nhật khi CI phát hiện tag v1.x.x trên branch main
global:
  imageTag: "v1.0.0"
  imageRepository: "your-dockerhub-username"
```

---

### Bước 3 – Tạo ArgoCD Application

**`k8s/environments/argocd/app-dev.yaml`** – auto-sync:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-dev
  namespace: argocd
  annotations:
    # Thêm link để dễ nhận diện
    argocd.argoproj.io/description: "YAS Dev environment - auto synced"
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/<repo>.git   # ← đổi thành repo của nhóm
    targetRevision: main
    path: k8s/charts
    helm:
      valueFiles:
        - ../environments/dev/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true       # Xóa resource không còn trong manifest
      selfHeal: true    # Tự fix nếu ai kubectl apply thủ công sai
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**`k8s/environments/argocd/app-staging.yaml`** – sync khi CI trigger:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/<repo>.git
    targetRevision: main
    path: k8s/charts
    helm:
      valueFiles:
        - ../environments/staging/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    # KHÔNG auto-sync – chỉ sync khi CI gọi `argocd app sync`
    syncOptions:
      - CreateNamespace=true
```

Apply lên cluster:
```bash
kubectl apply -f k8s/environments/argocd/app-dev.yaml
kubectl apply -f k8s/environments/argocd/app-staging.yaml

# Kiểm tra
argocd app list
```

---

### Bước 4 – Cấu hình GitHub Webhook (tức thì, không cần polling)

> GCP VM có External IP thật → dùng được webhook, ArgoCD detect thay đổi **ngay lập tức** thay vì chờ 3 phút polling.

Lấy NodePort của ArgoCD server:
```bash
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}'
```

Vào GitHub repo → **Settings** → **Webhooks** → **Add webhook**:
```
Payload URL  : https://<GCP_EXTERNAL_IP>:<NodePort>/api/webhook
Content type : application/json
Secret       : (để trống hoặc tạo secret ngẫu nhiên)
Events       : Just the push event
```

---

### Bước 5 – Tích hợp CI → GitOps (phối hợp với TV2)

TV3 cần **bổ sung đoạn script sau vào Jenkinsfile của TV2** (sau stage Build & Push Image):

```groovy
stage('Update GitOps values.yaml') {
  when {
    branch 'main'
  }
  steps {
    script {
      // Cập nhật image tag trong values.yaml của môi trường dev
      sh """
        yq e -i '.global.imageTag = "${env.COMMIT_ID}"' \
          k8s/environments/dev/values.yaml

        git config user.email "jenkins-ci@yas.local"
        git config user.name "Jenkins CI Bot"
        git add k8s/environments/dev/values.yaml
        git commit -m "ci: update dev image tag to ${env.COMMIT_ID} [skip ci]" || true
        git push origin main
      """
      echo "✅ ArgoCD sẽ tự động detect và sync vào namespace dev"
    }
  }
}

stage('Deploy to Staging (release tag only)') {
  when {
    // Chỉ chạy khi có tag dạng v1.2.3
    buildingTag()
    expression { env.TAG_NAME ==~ /v\d+\.\d+\.\d+/ }
  }
  steps {
    script {
      sh """
        yq e -i '.global.imageTag = "${env.TAG_NAME}"' \
          k8s/environments/staging/values.yaml

        git add k8s/environments/staging/values.yaml
        git commit -m "ci: release ${env.TAG_NAME} to staging [skip ci]"
        git push origin main
      """
      // Trigger sync thủ công cho staging
      sh "argocd app sync yas-staging --auth-token \$ARGOCD_TOKEN"
      echo "✅ Staging đã được sync với tag ${env.TAG_NAME}"
    }
  }
}
```

---

### Bước 6 – Test End-to-End

**Test luồng dev (auto-sync):**
1. Sửa 1 dòng code bất kỳ trong service (ví dụ `tax/`) → commit lên `main`
2. Jenkins CI build image → push Docker Hub → update `dev/values.yaml` → commit
3. GitHub webhook → ArgoCD nhận thông báo → tự sync vào namespace `dev`
4. Kiểm tra: `argocd app get yas-dev` → trạng thái `Synced + Healthy`

**Test luồng staging (release tag):**
```bash
git tag v1.0.0
git push origin v1.0.0
```
→ Jenkins detect tag → build image `v1.0.0` → update `staging/values.yaml` → ArgoCD sync staging.

### ✅ Output TV3 (bằng chứng nộp báo cáo)
- File YAML trong `k8s/environments/` đã commit trong repo.
- Screenshot ArgoCD UI: `yas-dev` **Synced + Healthy**, `yas-staging` Synced.
- Screenshot commit history: thấy commit của Jenkins CI Bot tự động update `values.yaml`.
- Screenshot GitHub webhook đã cấu hình.
- Mô tả luồng GitOps trong báo cáo: **sơ đồ** Code → CI → Docker Hub → Git commit → ArgoCD Webhook → K8S.

---

## Thành viên 4 – Service Mesh: Istio + mTLS + AuthzPolicy + Retry (2đ nâng cao)

**Mục tiêu:** Cài Istio, bật mTLS toàn mesh, kiểm soát kết nối giữa service, cấu hình Retry, thực hiện test có bằng chứng.

> ⚠️ **Phụ thuộc:** Cần TV1 hoàn thành (cluster và namespace `yas` đang chạy đầy đủ) trước khi bắt đầu.
>
> ⚠️ **Lưu ý GCP:** Istio inject sidecar sẽ tăng RAM mỗi pod thêm ~50–100MB. Với 32GB RAM trên GCP, đủ để chạy Istio cho namespace `yas`.

### Bước 1 – Cài đặt Istio

```bash
# Tải Istio (dùng phiên bản stable)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0
export PATH="$PWD/bin:$PATH"

# Cài lên K8S cluster
istioctl install --set profile=demo -y

# Verify
kubectl get pods -n istio-system
# Tất cả phải Running: istiod, istio-ingressgateway, istio-egressgateway
```

**Bật sidecar injection cho namespace `yas`:**
```bash
kubectl label namespace yas istio-injection=enabled

# Restart tất cả pod trong yas để inject sidecar Envoy
kubectl rollout restart deployment -n yas

# Verify: mỗi pod phải có READY 2/2
kubectl get pods -n yas
```

---

### Bước 2 – Cài Kiali + Prometheus + Jaeger

```bash
# Cài bộ addons observability của Istio
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Chờ Kiali sẵn sàng
kubectl wait --for=condition=available deployment/kiali -n istio-system --timeout=120s

# Expose Kiali ra ngoài (NodePort)
kubectl patch svc kiali -n istio-system \
  -p '{"spec": {"type": "NodePort"}}'

# Xem port
kubectl get svc kiali -n istio-system
# Truy cập: http://<GCP_EXTERNAL_IP>:<NodePort>/kiali
```

**Tạo traffic để Kiali hiển thị topology:**
```bash
# Chạy load test nhỏ để có traffic
kubectl run -n yas traffic-gen --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c 'for i in $(seq 1 50); do curl -s http://product:8080/api/products; sleep 1; done'
```
→ Vào Kiali UI → **Graph** → Namespace: `yas` → chụp screenshot topology.

---

### Bước 3 – Bật mTLS toàn mesh

Tạo file `k8s/service-mesh/peer-authentication.yaml`:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system    # Áp dụng toàn cluster
spec:
  mtls:
    mode: STRICT             # Bắt buộc mTLS, reject plain HTTP
```

```bash
kubectl apply -f k8s/service-mesh/peer-authentication.yaml

# Verify mTLS đang hoạt động
kubectl get peerauthentication -n istio-system
istioctl authn tls-check <tên-pod-product>.yas inventory.yas.svc.cluster.local
# Output mong đợi: STATUS=OK, SERVER=mTLS, CLIENT=mTLS
```

---

### Bước 4 – Authorization Policy

**Phân tích các cặp service giao tiếp trong YAS:**
| Service gọi | Service được gọi | Mục đích |
|---|---|---|
| `product` | `inventory` | Kiểm tra tồn kho |
| `order` | `tax` | Tính thuế |
| `order` | `promotion` | Áp dụng khuyến mãi |
| `backoffice-bff` | `product`, `inventory`, `tax`... | BFF gateway |

Tạo file `k8s/service-mesh/authorization-policy.yaml`:
```yaml
# Policy 1: Cho phép product gọi inventory
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-product-to-inventory
  namespace: yas
spec:
  selector:
    matchLabels:
      app: inventory
  action: ALLOW
  rules:
  - from:
    - source:
        # Service Account của product pod
        principals: ["cluster.local/ns/yas/sa/product"]
---
# Policy 2: Deny mọi kết nối khác vào inventory (baseline deny-all)
# Khi có ít nhất 1 ALLOW policy, mặc định sẽ deny-all cho selector đó
# Policy 1 đã tạo ra deny-all ngầm cho inventory với ALLOW exception

---
# Policy 3: Cho phép order gọi tax
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-order-to-tax
  namespace: yas
spec:
  selector:
    matchLabels:
      app: tax
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/yas/sa/order"]
```

```bash
kubectl apply -f k8s/service-mesh/authorization-policy.yaml
```

---

### Bước 5 – Retry Policy

Tạo file `k8s/service-mesh/virtual-service-retry.yaml`:
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: tax-retry
  namespace: yas
spec:
  hosts:
  - tax
  http:
  - retries:
      attempts: 3
      perTryTimeout: 5s
      retryOn: 5xx,gateway-error,connect-failure,reset
    route:
    - destination:
        host: tax
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: inventory-retry
  namespace: yas
spec:
  hosts:
  - inventory
  http:
  - retries:
      attempts: 3
      perTryTimeout: 5s
      retryOn: 5xx,gateway-error,connect-failure,reset
    route:
    - destination:
        host: inventory
```

```bash
kubectl apply -f k8s/service-mesh/virtual-service-retry.yaml
```

---

### Bước 6 – Kịch bản Test (BẮT BUỘC có bằng chứng)

#### Test 1: mTLS đang hoạt động
```bash
# Kiểm tra trạng thái mTLS giữa product và inventory
PRODUCT_POD=$(kubectl get pod -n yas -l app=product -o jsonpath='{.items[0].metadata.name}')
istioctl authn tls-check $PRODUCT_POD.yas inventory.yas.svc.cluster.local

# Output kỳ vọng:
# HOST:PORT                              STATUS  SERVER     CLIENT
# inventory.yas.svc.cluster.local:8080   OK      mTLS       mTLS
```

#### Test 2: Authorization Policy – ALLOW
```bash
# product được phép gọi inventory → HTTP 200
kubectl exec -n yas deployment/product -- \
  curl -v http://inventory.yas.svc.cluster.local:8080/api/inventories \
  -H "Content-Type: application/json"

# → Kỳ vọng: HTTP/1.1 200 OK
```

#### Test 3: Authorization Policy – DENY
```bash
# rating KHÔNG được phép gọi inventory → HTTP 403
kubectl exec -n yas deployment/rating -- \
  curl -v http://inventory.yas.svc.cluster.local:8080/api/inventories

# → Kỳ vọng: HTTP/1.1 403 Forbidden
#             body: "RBAC: access denied"
```
**⚠️ Chụp screenshot cả 2 kết quả trên.**

#### Test 4: Retry Policy
```bash
# Bước 1: Giả lập tax-service down
kubectl scale deployment tax -n yas --replicas=0

# Bước 2: Gọi từ order → tax (sẽ trigger retry)
kubectl exec -n yas deployment/order -- \
  curl -v http://tax.yas.svc.cluster.local:8080/api/taxes/calculate

# Bước 3: Xem log Envoy của pod order để thấy 3 lần retry
kubectl logs -n yas -l app=order -c istio-proxy --tail=50 | grep -E "tax|retry|503"

# → Kỳ vọng: thấy 3 request đến tax với response_code=503
# Bước 4: Restore
kubectl scale deployment tax -n yas --replicas=1
```

#### Chụp Kiali Topology
```
Kiali UI → Graph → Namespace: yas
→ Chọn Display: Traffic Animation (để thấy luồng request)
→ Chụp screenshot toàn bộ topology
→ Đánh dấu và giải thích ít nhất 5 cặp service quan trọng
```

### ✅ Output TV4 (bằng chứng nộp báo cáo)
- Files YAML trong `k8s/service-mesh/` đã commit:
  - `peer-authentication.yaml`
  - `authorization-policy.yaml`
  - `virtual-service-retry.yaml`
- Screenshot `istioctl authn tls-check` xác nhận mTLS OK.
- Screenshot/Log test ALLOW: HTTP 200.
- Screenshot/Log test DENY: HTTP 403 "RBAC: access denied".
- Screenshot/Log test Retry: thấy 3 lần retry trong Envoy log.
- Screenshot Kiali topology với chú thích flow.
- File `docs/README_service_mesh.md` – hướng dẫn triển khai từng bước.

---

## Phân công Báo cáo

| Phần báo cáo | Người viết |
|---|---|
| Tổng quan kiến trúc YAS + sơ đồ hệ thống | Thành viên 1 |
| Hướng dẫn dựng K8S + deploy YAS trên GCP VM | Thành viên 1 |
| CI Pipeline: detect changed files + build/push image | Thành viên 2 |
| Jenkins job `developer_build` và `cleanup_deployment` | Thành viên 2 |
| ArgoCD: cài đặt, cấu hình, sơ đồ luồng GitOps | Thành viên 3 |
| Service Mesh: mTLS, AuthzPolicy, Retry + log test | Thành viên 4 |
| Tổng hợp, format, kiểm tra tên file `.docx` | Thành viên 3 |

---

## Timeline (còn lại)

| Ngày | TV1 | TV2 | TV3 | TV4 |
|---|---|---|---|---|
| **Ngày 1–2** | Hoàn thành phần 5 (namespace dev/staging) | Chạy Jenkins container + cấu hình credentials | Cài ArgoCD, expose NodePort, tạo cấu trúc `k8s/environments/` | Cài Istio, inject sidecar, kiểm tra 2/2 containers |
| **Ngày 3–4** | Viết báo cáo phần mình | Hoàn thiện Jenkinsfile CI (detect changed + build push) | Tạo ArgoCD Application dev+staging, cấu hình webhook | Cài Kiali, tạo traffic, chụp topology |
| **Ngày 5–6** | Review và hỗ trợ nhóm | Hoàn thiện `developer_build` + `cleanup_deployment` | Tích hợp CI→GitOps (script update values.yaml), test end-to-end | Cấu hình mTLS + AuthzPolicy + Retry |
| **Ngày 7** | — | Viết báo cáo phần mình | Viết báo cáo phần mình | Chạy toàn bộ kịch bản test, chụp screenshot, viết báo cáo |
| **Ngày 8** | Tổng hợp `.docx` | Review báo cáo | Review báo cáo | Review báo cáo |

---

## Checklist Nộp Bài

### ✅ Phần Bắt buộc (6đ)
- [ ] K8S cluster Running (`kubectl get nodes` – Ready)
- [ ] `kubectl get pods -n yas` – tất cả Running
- [ ] `kubectl get pods -n dev` và `kubectl get pods -n staging` – Running
- [ ] Truy cập được `storefront.yas.local.com` và `backoffice.yas.local.com`
- [ ] Jenkins chạy, cả nhóm truy cập được qua GCP IP:8080
- [ ] CI pipeline trigger trên **mọi branch**, chỉ build service có thay đổi
- [ ] Docker Hub có image với tag là **commit ID 7 ký tự**
- [ ] Tag `latest` trên Docker Hub được cập nhật khi merge vào `main`
- [ ] `developer_build` chạy với 2 param (service + branch), in ra URL truy cập
- [ ] `cleanup_deployment` xóa được namespace, verify bằng `kubectl get ns`

### ✅ Phần Nâng cao ArgoCD (2đ)
- [ ] ArgoCD UI truy cập được qua GCP IP
- [ ] ArgoCD Application `yas-dev`: **auto-sync**, trạng thái Synced + Healthy
- [ ] ArgoCD Application `yas-staging`: sync đúng khi có tag `v1.x.x`
- [ ] Commit history repo có commit của CI Bot update `values.yaml`
- [ ] GitHub Webhook cấu hình, ArgoCD nhận thông báo tức thì
- [ ] Test end-to-end: Commit → CI → Docker Hub → Git → ArgoCD → K8S

### ✅ Phần Nâng cao Service Mesh (2đ)
- [ ] `kubectl get pods -n yas` – tất cả pod có **READY 2/2** (app + istio-proxy)
- [ ] `istioctl authn tls-check` xác nhận mTLS OK
- [ ] Test **ALLOW** (HTTP 200) có screenshot/log
- [ ] Test **DENY** (HTTP 403 "RBAC: access denied") có screenshot/log
- [ ] Test **Retry**: log Envoy thấy 3 lần retry khi service trả 5xx
- [ ] Screenshot Kiali topology có chú thích flow
- [ ] Files YAML manifest đã commit trong `k8s/service-mesh/`

### ✅ Báo cáo
- [ ] Đặt tên file đúng format `MSSV1_MSSV2_MSSV3_MSSV4.docx` (MSSV tăng dần)
- [ ] Mỗi bước có ảnh minh chứng
- [ ] Sơ đồ kiến trúc tổng thể + sơ đồ luồng GitOps (Code → K8S)
