kubectl config set-context --current --namespace=tee

kubectl get pods
kubectl logs (kubectl get pods -o name -n tee | Select-String "tee-proxy-server-k8s-2") -n tee
kubectl describe svc (kubectl get pods -o name | Select-String "tee-proxy-server-k8s-2") -n default
kubectl exec -it (kubectl get pods -o name | Select-String "tee-proxy-server-k8s-2") -n default -- sh

kubectl get deployments
kubectl rollout restart deployment/tee-proxy-server-k8s-1 -n tee
kubectl rollout restart deployment/tee-proxy-server-k8s-2 -n tee
kubectl rollout restart deployment/tee-c-chain-indexer-cli-coston-k8s-ftso-v2-c-chain-indexer
kubectl rollout restart deployment/tee-c-chain-indexer-coston-k8s-ftso-v2-c-chain-indexer
kubectl logs tee-proxy-server-k8s-2-669cf69c77-v84dj --namespace=default
kubectl logs tee-c-chain-indexer-cli-coston-k8s-ftso-v2-c-chain-indexerfcgds --namespace=tee

kubectl scale deployment tee-proxy-server-k8s-1 --replicas=0 -n tee
kubectl scale deployment tee-proxy-server-k8s-2 --replicas=0 -n tee

kubectl exec -it (kubectl get pods -o name -n tee | Select-String "tee-c-chain-indexer-coston-k8s-ftso-v2-c-chain-indexer") -n tee -- sh
kubectl logs (kubectl get pods -o name -n tee | Select-String "tee-c-chain-indexer-coston-k8s-ftso-v2-c-chain-indexer") -n tee
kubectl rollout restart deployment/tee-c-chain-indexer-coston-k8s-ftso-v2-c-chain-indexer -n tee

kubectl get pods -o name | Select-String "tee-proxy-serverk8s-test"

rm info ; wget localhost:6662/info ; head -c 500 info

kubectl get svc tee-proxy-server -n default


terraform taint module.tee_package_kubernetes.helm_release.tee_proxy_server
terraform taint module.tee_package_kubernetes.google_compute_instance.tee_machine
terraform taint module.tee_package_kubernetes.helm_release.gateway_route
terraform taint module.tee_package_kubernetes.helm_release.gateway_route_external

terraform taint module.tee_package_kubernetes_2.helm_release.tee_proxy_server
terraform taint module.tee_package_kubernetes_2.google_compute_instance.tee_machine
terraform taint module.tee_package_kubernetes_2.helm_release.gateway_route
terraform taint module.tee_package_kubernetes_2.helm_release.gateway_route_external

terraform taint module.tee_indexer_new.helm_release.indexer

kubectl get pods --namespace=tee
kubectl logs tee-c-chain-indexer-coston-k8s-ftso-v2-c-chain-indexer-5788lx9h --namespace=tee


terraform state list | Select-String "module.tee_indexer_new" | ForEach-Object {terraform taint "$($_.Line)" }


kubectl patch svc tee-proxy-server-694db9cdbb-ft9hx -n default
kubectl get svc tee-proxy-server


hostname=tee-proxy-k8s
http://tee-proxy-k8s.flare-network-staging.internal


Delete policies if taint fails:

kubectl delete gcpbackendpolicies.networking.gke.io tee-proxy-serverk8s-test-route-proxy
kubectl delete gcpbackendpolicies.networking.gke.io tee-proxy-serverk8s-test-route-proxy-private

kubectl delete healthcheckpolicies.networking.gke.io tee-proxy-serverk8s-test-route-proxy
kubectl delete healthcheckpolicies.networking.gke.io tee-proxy-serverk8s-test-route-proxy-private

kubectl delete HTTPRoute.gateway.networking.k8s.io tee-proxy-serverk8s-test-route-proxy
kubectl delete HTTPRoute.gateway.networking.k8s.io tee-proxy-serverk8s-test-route-proxy

wget --quiet \
     --method=POST \
     --header="Content-Type: application/json" \
     --body-data='{"url":"http://tee-proxy-k8s.flare-network-staging.internal"}' \
     -O - \
     http://localhost:5500/proxy


wget --post-data="" -O - -S  http://localhost:6662/instruction
wget --post-data="" -O - -S  "tee-proxy-server-k8s-4-public.tee.svc.cluster.local:6662/instruction"
wget --post-data="" -O - -S  "http://tee-proxy-k8s-4.flare.rocks/instruction"


wget --quiet \
     --method=POST \
     --header="Content-Type: application/json" \
     --body-data='{"extensionId": "0x0000000000000000000000000000000000000000000000000000000000000000"}' \
     -O - \
     http://localhost:5500/extension-id
     


wget -S -O- --post-data={} --header="Content-Type: application/json" http://tee-proxy-k8s-1.flare-network-staging.internal/queue/direct
wget -S -O- --post-data={} --header="Content-Type: application/json" https://tee-proxy-k8s-1.flare-network-staging.internal/queue/direct

wget -S -O- http://tee-proxy-k8s.flare-network-staging.internal
wget -S -O- http://tee-proxy-k8s.flare.rocks/info
wget -S -O- localhost:6661/healthy
wget -S -O- tee-proxy-server-k8s-1-public.default.svc.cluster.local:6662/info
wget -S -O- 10.105.208.37/info


Reset redis:
kubectl run -it redis-test --image=redis:7-alpine --restart=Never --rm -- sh
Package1:
redis-cli -h 10.115.21.251 -p 6379 FLUSHALL
Package2:
redis-cli -h 10.198.143.195 -p 6379 FLUSHALL
Extension:
redis-cli -h 10.150.55.91 -p 6379 FLUSHALL

redis-cli -h 10.115.21.251 -p 6379 info memory | grep maxmemory_policy

Find largest keys:

redis-cli -h 10.115.21.251 -p 6379 --scan | while read key; do
    size=$(redis-cli -h 10.115.21.251 -p 6379 MEMORY USAGE "$key")
    echo "$size $key"
done | sort -nr | head -n 10


kubectl run -it mysql-test --image=mysql:8 --restart=Never --rm -- sh
mysql -h tee-c-chain-indexer-coston-k8s-db.flare-network-staging.internal -P 3306 -u indexer -p

use indexer;
show tables;
select * from blocks order by timestamp desc limit 20;

ip: 35.241.221.113
port: 3306
username: indexer-reader
password: sMgYpa2Eh2u3cRZg
database: indexer

mysql -h 35.241.221.113 -u indexer-reader -p
ping 35.241.221.113:3306

