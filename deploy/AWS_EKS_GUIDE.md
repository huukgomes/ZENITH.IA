# AWS EKS Deployment Guide - ZENITH.IA

## 📋 Pré-requisitos

### Ferramentas Obrigatórias
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# eksctl (EKS CLI)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Istio CLI
curl -L https://istio.io/downloadIstio | sh -
cd istio-* && sudo cp bin/istioctl /usr/local/bin/
```

### Conta AWS
- Conta AWS ativa
- Permissões IAM adequadas
- Access Key ID e Secret Access Key configurados

```bash
aws configure
# AWS Access Key ID: YOUR_KEY
# AWS Secret Access Key: YOUR_SECRET
# Default region: us-east-1
# Default output format: json
```

---

## 🚀 Passo 1: Setup Automático (Recomendado)

```bash
# Clonar repositório
git clone https://github.com/huukgomes/ZENITH.IA.git
cd ZENITH.IA

# Tornar script executável
chmod +x deploy/aws-eks-setup.sh

# Executar setup (leva ~20-30 minutos)
./deploy/aws-eks-setup.sh
```

**O script faz automaticamente:**
- ✅ Cria cluster EKS
- ✅ Instala Istio
- ✅ Instala Load Balancer Controller
- ✅ Instala Prometheus + Grafana
- ✅ Deploy da aplicação
- ✅ Configura namespaces e RBAC

---

## 🔧 Passo 2: Configuração Manual (Opcional)

### 2.1 Criar Cluster EKS

```bash
eksctl create cluster \
  --name zenith-ops \
  --region us-east-1 \
  --nodegroup-name primary \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 10 \
  --managed \
  --enable-ssm
```

### 2.2 Update Kubeconfig

```bash
aws eks update-kubeconfig --name zenith-ops --region us-east-1
kubectl get nodes  # Verificar conexão
```

### 2.3 Instalar Istio

```bash
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=production -y
kubectl label namespace default istio-injection=enabled
cd ..
```

### 2.4 Instalar Ingress Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=zenith-ops \
  --set serviceAccount.create=true
```

### 2.5 Deploy da Aplicação

```bash
# Criar namespace
kubectl create namespace zenith
kubectl label namespace zenith istio-injection=enabled

# Aplicar manifestos
kubectl apply -f k8s/eks-deployment.yaml -n zenith
kubectl apply -f k8s/istio.yaml -n zenith
kubectl apply -f k8s/secrets.yaml -n zenith

# Verificar
kubectl get pods -n zenith
kubectl get svc -n zenith
```

---

## 📊 Verificar Deployment

### Status dos Pods
```bash
kubectl get pods -n zenith
kubectl describe pod <pod-name> -n zenith
kubectl logs <pod-name> -n zenith -c fastapi
```

### Status dos Services
```bash
kubectl get svc -n zenith
kubectl describe svc fastapi-service -n zenith
```

### Status do Cluster
```bash
kubectl get nodes
kubectl describe node <node-name>
kubectl top nodes
kubectl top pods -n zenith
```

### Verificar Istio
```bash
kubectl get vs -n zenith  # VirtualServices
kubectl get dr -n zenith  # DestinationRules
kubectl get pa -n zenith  # PeerAuthentication
istioctl analyze
```

---

## 🌐 Acessar a Aplicação

### 1. Obter URL do Load Balancer
```bash
kubectl get svc -n zenith
# Copiar o EXTERNAL-IP

# Ou automaticamente:
kubectl get svc fastapi-service -n zenith \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 2. Testar Aplicação
```bash
# Health check
curl http://<LOAD_BALANCER_URL>/health

# Ready check
curl http://<LOAD_BALANCER_URL>/ready

# API
curl http://<LOAD_BALANCER_URL>/api/v1/config
```

### 3. Port Forward (Teste Local)
```bash
kubectl port-forward -n zenith svc/fastapi-service 8000:8000
curl http://localhost:8000/health
```

---

## 📈 Monitoramento & Observabilidade

### Grafana (Dashboards)
```bash
# Acessar Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Abrir: http://localhost:3000
# Default credentials: admin / prom-operator
```

### Prometheus (Métricas)
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prom-prometheus 9090:9090
# Abrir: http://localhost:9090
```

### Kiali (Service Mesh)
```bash
istioctl dashboard kiali
# Visualize seu service mesh em tempo real
```

### Jaeger (Distributed Tracing)
```bash
kubectl port-forward -n istio-system svc/jaeger 16686:16686
# Abrir: http://localhost:16686
```

---

## 🔐 Gerenciar Secrets

### Usando AWS Secrets Manager
```bash
# Criar secret
aws secretsmanager create-secret \
  --name zenith/database-url \
  --secret-string "postgresql://user:pass@host:5432/zenith"

# Atualizar Kubernetes com o secret
kubectl apply -f k8s/secrets.yaml -n zenith
```

### Usar Vault (Recomendado)
```bash
# Deploy Vault (se não estiver)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -n vault --create-namespace

# Acessar secrets no código
# Vejo: src/vault_client.py
```

---

## 🚀 CI/CD com GitHub Actions

### 1. Configurar Secrets no GitHub

```
Settings → Secrets and variables → Actions
```

Adicionar:
- `AWS_ACCESS_KEY_ID` - Sua AWS key
- `AWS_SECRET_ACCESS_KEY` - Sua AWS secret
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub token
- `SLACK_WEBHOOK` - (Opcional) Para notificações

### 2. Trigger Automático

A cada push em `main`:
```bash
git push origin main
# GitHub Actions automaticamente:
# 1. Build Docker image
# 2. Roda testes
# 3. Push para Docker Hub
# 4. Deploy para EKS
# 5. Notifica no Slack
```

---

## 📋 Scaling & Auto-scaling

### Manual Scaling
```bash
kubectl scale deployment fastapi-deployment --replicas=5 -n zenith
```

### Auto-scaling (HPA)
```bash
# Já configurado em k8s/hpa.yaml
# Min: 2 pods
# Max: 10 pods
# Trigger: CPU > 70% ou Memory > 80%

# Verificar status
kubectl get hpa -n zenith
kubectl top pods -n zenith  # Ver uso atual
```

---

## 🔄 Updates & Rollouts

### Deploy Nova Versão
```bash
# Build e push nova imagem
docker build -t huukgomes/zenith-ia:v1.1.0 .
docker push huukgomes/zenith-ia:v1.1.0

# Update deployment
kubectl set image deployment/fastapi-deployment \
  fastapi=huukgomes/zenith-ia:v1.1.0 \
  -n zenith \
  --record

# Monitorar rollout
kubectl rollout status deployment/fastapi-deployment -n zenith
kubectl rollout history deployment/fastapi-deployment -n zenith
```

### Rollback
```bash
# Voltar para versão anterior
kubectl rollout undo deployment/fastapi-deployment -n zenith

# Rollback para revision específica
kubectl rollout undo deployment/fastapi-deployment --to-revision=2 -n zenith
```

---

## 💾 Backup & Disaster Recovery

### Backup de Dados
```bash
# RDS (PostgreSQL) - Automático via AWS
aws rds describe-db-snapshots --db-instance-identifier zenith-db

# Backup manual
aws rds create-db-snapshot \
  --db-instance-identifier zenith-db \
  --db-snapshot-identifier zenith-backup-$(date +%s)
```

### Backup de ConfigMaps/Secrets
```bash
# Exportar todos os recursos
kubectl get all,cm,secret -n zenith -o yaml > zenith-backup.yaml

# Restaurar
kubectl apply -f zenith-backup.yaml -n zenith
```

### Disaster Recovery
```bash
# Restaurar do snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier zenith-db-recovered \
  --db-snapshot-identifier zenith-backup-12345

# Redeploy aplicação
kubectl delete namespace zenith
kubectl apply -f k8s/
```

---

## 🧹 Cleanup (Deletar Recursos)

### Importante: Isso deletará TUDO!
```bash
# Delete namespace e recursos
kubectl delete namespace zenith

# Delete cluster EKS
eksctl delete cluster --name zenith-ops --region us-east-1

# Deletar RDS
aws rds delete-db-instance \
  --db-instance-identifier zenith-db \
  --skip-final-snapshot

# Deletar Kafka (MSK)
aws kafka delete-cluster --cluster-arn <arn>
```

---

## 🐛 Troubleshooting

### Pods não iniciando
```bash
kubectl describe pod <pod-name> -n zenith
kubectl logs <pod-name> -n zenith --previous
```

### Erro de recursos
```bash
kubectl top nodes
kubectl describe node <node>
# Se necessário: eksctl scale nodegroup --cluster=zenith-ops --name=primary --nodes=3
```

### Erro de conectividade
```bash
# Verificar service mesh
istioctl analyze
kubectl get vs -n zenith
kubectl get dr -n zenith

# Testar dentro do cluster
kubectl run debug --image=curlimages/curl -it --rm -- /bin/sh
curl http://fastapi-service:8000/health
```

### Logs
```bash
# Acessar logs de controladores
kubectl logs deployment/aws-load-balancer-controller -n kube-system
kubectl logs deployment/istio-ingressgateway -n istio-system
```

---

## 💡 Dicas Importantes

1. **Always use namespaces** - Melhor organização
2. **Enable RBAC** - Segurança
3. **Use resource requests/limits** - Evita problemas
4. **Monitor constantemente** - Prometheus + Grafana
5. **Backup regularmente** - Crítico em produção
6. **Use GitOps** - ArgoCD para auto-deploy
7. **Configure alertas** - Slack/PagerDuty

---

## 📞 Suporte

- AWS Support: https://console.aws.amazon.com/support
- EKS Docs: https://docs.aws.amazon.com/eks
- Istio Docs: https://istio.io/docs
- Kubernetes Docs: https://kubernetes.io/docs

---

**Última atualização:** 2026-05-24
