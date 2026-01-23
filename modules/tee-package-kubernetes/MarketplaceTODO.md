- Replace InternalGateway with internal LoadBalancer
- Replace ExternalGateway with something, maybe just return POD data and let users do the rest
- Users must create the cluster
- DNS must be created outside of tee-module, and each client must take care of that by himself.
- User must manually create secrets in secret manager (ProxyPrivateKey) Now accepts secret name, for marketplace this will need to accept just a secret, so user can manage them as he likes
- Pack all internal terraform modules into tee-package (maybe create a script that does this)

Anyone can connect on anything inside of flare-network-staging can access everything in flare-network-staging? All kubernetes pods?
Ask about LoadBalancer pod type, instead of internal-gateway. Ask about dangers of anyone in staging-network accessing VMs port 5500.
Is in production also only one network for all?

Ask this: Hello. tee-machine-k8s-2 – Compute Engine – Flare Staging – Google Cloud console This VM is running a containerd, that is supplying three configuration endpoints on port 5500, /proxy, /initial-owner, and /extension-id

How to connect VM directly to a pod?
Network policy in kubernents for VM of tee-machine - Probaby will need my own lb - Will need mTLS