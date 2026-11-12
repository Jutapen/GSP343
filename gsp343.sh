#!/bin/bash
# ==============================================================================
#  GSP343 - Optimize Costs for Google Kubernetes Engine: Challenge Lab
#  Credit : Jutapen  (https://github.com/Jutapen)
#
#  Dijalankan di Cloud Shell dengan akun student lab.
#  Nilai opsional lewat environment variable: PROJECT_ID, ZONE, CLUSTER, POOL,
#  MAX_REPLICAS. Kalau kosong, script mengambil dari gcloud config atau bertanya.
# ==============================================================================
set -e

# ---------- Warna (nonaktif kalau output bukan terminal) ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  USE_COLOR=true
  C_INFO=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
  USE_COLOR=false
  C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_BOLD=""; C_RST=""
fi

info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RST" "$*"; }
err()  { printf '%s[ERR ]%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; }

printf '%s' "$C_BOLD"
echo "=============================================================="
echo " GSP343 - Optimize Costs for GKE: Challenge Lab"
echo " Credit : Jutapen  |  https://github.com/Jutapen"
echo "=============================================================="
printf '%s' "$C_RST"

# ---------- Helper ----------
pause() {
  echo
  read -rp ">>> Klik 'Check my progress' di halaman lab, lalu tekan ENTER untuk lanjut... " _ </dev/tty
  echo
}

# ask VAR "Pertanyaan" [default]  -> pakai nilai env kalau ada, kalau tidak tanya
ask() {
  local var="$1" prompt="$2" def="${3:-}" val
  val="${!var:-}"
  if [ -z "$val" ]; then
    if [ -n "$def" ]; then
      read -rp "$prompt [$def]: " val </dev/tty
      val="${val:-$def}"
    else
      read -rp "$prompt: " val </dev/tty
    fi
  fi
  if [ -z "$val" ]; then
    err "Nilai untuk $var tidak boleh kosong."
    exit 1
  fi
  printf -v "$var" '%s' "$val"
}

typeout() {
  local s="$1" i
  if $USE_COLOR; then
    for ((i = 0; i < ${#s}; i++)); do
      printf '%s' "${s:i:1}"
      sleep 0.02
    done
    printf '\n'
  else
    printf '%s\n' "$s"
  fi
}

# ---------- Ambil nilai dari environment / gcloud config ----------
PROJECT_ID="${PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}}"
ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || true)}"

ask PROJECT_ID "Project ID (lihat panel lab)"
ask ZONE "Zone (lab meminta us-central1-b)" "us-central1-b"
if [ "$ZONE" != "us-central1-b" ]; then
  warn "Lab meminta zone us-central1-b, sedangkan zone sekarang: $ZONE"
fi
ask CLUSTER "Cluster Name (lihat panel lab)"
ask POOL "Pool Name (lihat panel lab)"
ask MAX_REPLICAS "Max Replicas (lihat panel lab)" "10"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
info "Project : $PROJECT_ID"
info "Zone    : $ZONE"
info "Cluster : $CLUSTER"
info "Pool    : $POOL"
info "Max rep : $MAX_REPLICAS"

# ================= TASK 1 =================
echo
info "=== TASK 1: Cluster + namespace + deploy app ==="
if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" >/dev/null 2>&1; then
  warn "Cluster $CLUSTER sudah ada, dilewati."
else
  gcloud container clusters create "$CLUSTER" \
    --zone "$ZONE" \
    --machine-type e2-standard-2 \
    --num-nodes 2 \
    --release-channel rapid
fi
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE"

for ns in dev prod; do
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    kubectl create namespace "$ns"
  fi
done

if [ ! -d microservices-demo ]; then
  git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
fi
( cd microservices-demo && kubectl apply -f ./release/kubernetes-manifests.yaml --namespace dev )

info "Menunggu semua deployment di dev siap..."
kubectl wait --for=condition=available deployment --all -n dev --timeout=900s
ok "Task 1 selesai."
pause

# ================= TASK 2 =================
info "=== TASK 2: Migrasi ke node pool optimized ==="
if gcloud container node-pools describe "$POOL" --cluster "$CLUSTER" --zone "$ZONE" >/dev/null 2>&1; then
  warn "Node pool $POOL sudah ada, dilewati."
else
  gcloud container node-pools create "$POOL" \
    --cluster "$CLUSTER" \
    --zone "$ZONE" \
    --machine-type e2-custom-2-3584 \
    --num-nodes 2
fi

if gcloud container node-pools describe default-pool --cluster "$CLUSTER" --zone "$ZONE" >/dev/null 2>&1; then
  info "Cordon default-pool..."
  for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
    kubectl cordon "$node"
  done
  info "Drain default-pool..."
  for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
    kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force --timeout=600s
  done
  info "Menunggu deployment pindah ke $POOL..."
  kubectl wait --for=condition=available deployment --all -n dev --timeout=900s
  gcloud container node-pools delete default-pool --cluster "$CLUSTER" --zone "$ZONE" --quiet
else
  warn "default-pool sudah dihapus, dilewati."
fi
ok "Task 2 selesai."
pause

# ================= TASK 3 =================
info "=== TASK 3: PDB + update frontend ==="
if kubectl get pdb onlineboutique-frontend-pdb -n dev >/dev/null 2>&1; then
  warn "PDB onlineboutique-frontend-pdb sudah ada, dilewati."
else
  kubectl create poddisruptionbudget onlineboutique-frontend-pdb \
    --namespace dev --selector app=frontend --min-available 1
fi

kubectl patch deployment frontend -n dev --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"server","image":"gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1","imagePullPolicy":"Always"}]}}}}'
kubectl rollout status deployment/frontend -n dev --timeout=600s
ok "Task 3 selesai."
pause

# ================= TASK 4 =================
info "=== TASK 4: Autoscaling ==="
if kubectl get hpa frontend -n dev >/dev/null 2>&1; then
  warn "HPA frontend sudah ada, dilewati."
else
  kubectl autoscale deployment frontend --namespace dev \
    --cpu-percent=50 --min=1 --max="$MAX_REPLICAS"
fi

gcloud container clusters update "$CLUSTER" --zone "$ZONE" \
  --node-pool "$POOL" --enable-autoscaling --min-nodes 1 --max-nodes 6

info "Mengambil IP frontend-external..."
FRONTEND_IP=""
tries=0
while [ -z "$FRONTEND_IP" ] && [ "$tries" -lt 60 ]; do
  FRONTEND_IP=$(kubectl get svc frontend-external -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -z "$FRONTEND_IP" ]; then
    echo "  menunggu IP..."
    sleep 10
    tries=$((tries + 1))
  fi
done
if [ -z "$FRONTEND_IP" ]; then
  err "IP frontend-external belum tersedia."
  exit 1
fi
ok "Frontend IP: $FRONTEND_IP"

LG_POD=$(kubectl get pod --namespace=dev | grep 'loadgenerator' | cut -f1 -d ' ')
info "Menjalankan load test 8000 user di background (log: loadtest.log)"
nohup kubectl exec "$LG_POD" --namespace=dev -- sh -c \
  "export USERS=8000; locust --host=\"http://$FRONTEND_IP\" --headless -u \"8000\" 2>&1" \
  > loadtest.log 2>&1 </dev/null &
LOAD_PID=$!

echo
info "Amati Kubernetes Engine > Workloads. recommendationservice akan mulai kewalahan."
read -rp ">>> Tunggu 1-2 menit, lalu tekan ENTER untuk menerapkan HPA recommendationservice... " _ </dev/tty

if kubectl get hpa recommendationservice -n dev >/dev/null 2>&1; then
  warn "HPA recommendationservice sudah ada, dilewati."
else
  kubectl autoscale deployment recommendationservice --namespace dev \
    --cpu-percent=50 --min=1 --max=5
fi
kubectl get hpa -n dev
ok "Task 4 selesai."
pause

kill "$LOAD_PID" 2>/dev/null || true

# ================= PENUTUP =================
echo
banner=(
' ____   ___  _   _ _____ '
'|  _ \ / _ \| \ | | ____|'
'| | | | | | |  \| |  _|  '
'| |_| | |_| | |\  | |___ '
'|____/ \___/|_| \_|_____|'
)
grad=(39 45 51 87 123)
for i in "${!banner[@]}"; do
  if $USE_COLOR; then
    printf '\033[1;38;5;%sm%s\033[0m\n' "${grad[$i]}" "${banner[$i]}"
  else
    printf '%s\n' "${banner[$i]}"
  fi
done

echo
printf '%sGSP343 - Optimize Costs for Google Kubernetes Engine: Challenge Lab%s\n' "$C_BOLD" "$C_RST"
echo
printf '%s✔%s Cluster %s (zonal, %s, rapid) dibuat\n' "$C_OK" "$C_RST" "$CLUSTER" "$ZONE"
printf '%s✔%s Namespace dev dan prod dibuat, OnlineBoutique ter-deploy di dev\n' "$C_OK" "$C_RST"
printf '%s✔%s Node pool %s (e2-custom-2-3584, 2 node), default-pool dihapus\n' "$C_OK" "$C_RST" "$POOL"
printf '%s✔%s PDB onlineboutique-frontend-pdb (min-available 1)\n' "$C_OK" "$C_RST"
printf '%s✔%s Frontend memakai image v2.1 dengan imagePullPolicy Always\n' "$C_OK" "$C_RST"
printf '%s✔%s HPA frontend (CPU 50%%, 1-%s pod)\n' "$C_OK" "$C_RST" "$MAX_REPLICAS"
printf '%s✔%s Cluster autoscaler pada %s (1-6 node)\n' "$C_OK" "$C_RST" "$POOL"
printf '%s✔%s HPA recommendationservice (CPU 50%%, 1-5 pod)\n' "$C_OK" "$C_RST"
echo
printf 'Service URL : http://%s\n' "$FRONTEND_IP"
echo
typeout "Jangan lupa mampir ke GitHub saya: https://github.com/Jutapen"
echo
printf '%sCredit: Jutapen%s\n' "$C_BOLD" "$C_RST"
