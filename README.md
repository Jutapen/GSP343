# GSP343 - Optimize Costs for Google Kubernetes Engine: Challenge Lab

Script otomatis untuk lab Google Cloud **GSP343**, dijalankan di Cloud Shell.

**Credit: Jutapen** - https://github.com/Jutapen

## Cara pakai (satu baris)

1. Mulai lab, buka Cloud Shell dengan akun student lab (gunakan jendela Incognito).
2. Jalankan:

```bash
curl -fsSL https://raw.githubusercontent.com/Jutapen/GSP343/main/gsp343.sh | bash
```

3. Script akan membaca Project ID dari gcloud config. Lalu isi sesuai panel **Lab setup and access**:
   - Cluster Name
   - Pool Name
   - Max Replicas
4. Script berhenti di akhir tiap task. Klik **Check my progress** di halaman lab, lalu tekan ENTER.

Opsional, nilai bisa diberikan lewat environment variable supaya tidak ditanya:

```bash
curl -fsSL https://raw.githubusercontent.com/Jutapen/GSP343/main/gsp343.sh | CLUSTER=nama-cluster POOL=nama-pool MAX_REPLICAS=10 bash
```

## Yang dikerjakan script

| Task | Isi |
|------|-----|
| 1 | Cluster zonal `us-central1-b`, `e2-standard-2`, 2 node, release channel `rapid`; namespace `dev` dan `prod`; deploy OnlineBoutique ke `dev` |
| 2 | Node pool baru `e2-custom-2-3584` (2 node); cordon dan drain `default-pool`; hapus `default-pool` |
| 3 | PDB `onlineboutique-frontend-pdb` (min-available 1); image frontend `gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1`; `imagePullPolicy: Always` |
| 4 | HPA frontend (CPU 50%, 1 sampai Max Replicas); cluster autoscaler 1-6 node; load test 8000 user; HPA recommendationservice (CPU 50%, 1-5) |

Task 5 bersifat opsional dan tidak dikerjakan.

## Langkah manual (GUI / CLI)

1. **Cluster:** Kubernetes Engine > Create > Standard, zona `us-central1-b`, 2 node `e2-standard-2`, release channel Rapid. Lalu `kubectl create namespace dev` dan `kubectl create namespace prod`, clone `microservices-demo`, dan `kubectl apply -f ./release/kubernetes-manifests.yaml --namespace dev`.
2. **Node pool:** Tambah node pool dengan 2 node bertipe `e2-custom-2-3584`. Jalankan `kubectl cordon` dan `kubectl drain --ignore-daemonsets --delete-emptydir-data` untuk setiap node `default-pool`, lalu hapus `default-pool`.
3. **Frontend:** `kubectl create poddisruptionbudget onlineboutique-frontend-pdb --namespace dev --selector app=frontend --min-available 1`. Edit deployment `frontend`: ubah image dan set `imagePullPolicy: Always`.
4. **Autoscaling:** `kubectl autoscale deployment frontend --namespace dev --cpu-percent=50 --min=1 --max=<Max Replicas>`. Aktifkan cluster autoscaler pada node pool baru (min 1, max 6). Jalankan load test dari pod `loadgenerator`, lalu `kubectl autoscale deployment recommendationservice --namespace dev --cpu-percent=50 --min=1 --max=5`.

## Yang normal terjadi

- Pembuatan cluster dan node pool butuh beberapa menit.
- Saat drain muncul pesan "cordoned" dan "evicting pod". Itu memang yang diminta lab.
- `default-pool` dihapus dengan sengaja di akhir Task 2.
- Kolom TARGETS pada HPA bisa `<unknown>/50%` sekitar 1 menit sebelum menampilkan angka.
- Selama load test, pod `Pending` atau `Insufficient cpu` itu wajar karena cluster autoscaler sedang menambah node.
- Load test dijalankan di background (log: `loadtest.log`). Script berhenti memantaunya di akhir, tetapi proses locust di dalam pod loadgenerator tetap berjalan sampai lab selesai.
- Menjalankan ulang script aman. Resource yang sudah ada akan dilewati.

## Disclaimer

Repo ini dibuat untuk tujuan edukasi. Tidak berafiliasi dengan Google. Gunakan hanya dengan akun student yang disediakan lab, bukan akun pribadi.

## Lisensi

MIT, lihat [LICENSE](LICENSE).
