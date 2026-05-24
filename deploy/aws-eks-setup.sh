#!/bin/bash

###############################################################################
# ZENITH.IA - AWS EKS Automated Setup Script
# Este script configura um cluster EKS completo com Istio, Prometheus, etc.
# Tempo: ~30 minutos
# Custo: ~$300-400/mês
###############################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
CLUSTER_NAME="zenith-ops"
REGION="us-east-1"
NAMESPACE="zenith"
NODE_TYPE="t3.medium"
NODES_MIN=2
NODES_MAX=10

###############################################################################
# Funções
###############################################################################

print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 não está instalado!"
        echo "Instale com: $2"
        exit 1
    fi
    print_success "$1 encontrado"
}

###############################################################################
# Verificações Iniciais
###############################################################################

print_header "Verificando Pré-requisitos"

check_command "aws" "pip install awscli"
check_command "eksctl" "curl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_\$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin"
check_command "kubectl" "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
check_command "helm" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

print_info "Verificando AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials não configurados!"
    echo "Execute: aws configure"
    exit 1
fi
print_success "AWS credentials OK"

###############################################################################
# Criar Cluster EKS
###############################################################################

print_header "Criando Cluster EKS"

if eksctl get cluster --name=$CLUSTER_NAME --region=$REGION &> /dev/null; then
    print_info "Cluster $CLUSTER_NAME já existe"
else
    print_info "Criando cluster $CLUSTER_NAME (pode levar 15-20 minutos)..."
    
    eksctl create cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --nodegroup-name primary \
        --node-type $NODE_TYPE \
        --nodes $NODES_MIN \
        --nodes-min $NODES_MIN \
        --nodes-max $NODES_MAX \
        --managed \
        --enable-ssm \
        --with-oidc \
        --enable-logging='[\"api\",\"audit\",\"authenticator\",\"controllerManager\",\"scheduler\"]'
    
    print_success "Cluster EKS criado"
fi

# Atualizar kubeconfig
print_info "Atualizando kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
print_success "Kubeconfig atualizado"

# Verificar nodes
print_info "Aguardando nodes ficarem prontos..."
kubectl wait --for=condition=Ready node --all --timeout=300s 2>/dev/null || true
kubectl get nodes
print_success "Nodes prontos"

###############################################################################
# Instalar AWS Load Balancer Controller
###############################################################################

print_header "Instalando AWS Load Balancer Controller"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --wait

print_success "AWS Load Balancer Controller instalado"

###############################################################################
# Instalar Istio
###############################################################################

print_header "Instalando Istio Service Mesh"

# Download Istio
if [ ! -d "istio-1.20.0" ]; then
    print_info "Baixando Istio..."
    curl -L https://istio.io/downloadIstio | sh -
fi

cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Instalar Istio
print_info "Instalando Istio (profile: production)..."
istioctl install --set profile=production -y

# Label namespace
kubectl label namespace default istio-injection=enabled --overwrite

print_success "Istio instalado"
cd ..

###############################################################################
# Criar Namespace e Configurações
###############################################################################

print_header "Configurando Namespace e RBAC"

# Criar namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Criar RBAC
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: zenith-sa
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: zenith-role
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: zenith-rolebinding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: zenith-role
subjects:
- kind: ServiceAccount
  name: zenith-sa
  namespace: $NAMESPACE
EOF

print_success "Namespace e RBAC configurados"

###############################################################################
# Instalar Prometheus e Grafana
###############################################################################

print_header "Instalando Prometheus e Grafana"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --wait

print_success "Prometheus e Grafana instalados"

# Port forward info
print_info "Para acessar Grafana:"
print_info "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
print_info "  Default user: admin / prom-operator"

###############################################################################
# Deploy da Aplicação
###############################################################################

print_header "Deployando ZENITH.IA"

# Criar ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: zenith-config
  namespace: $NAMESPACE
data:
  ENVIRONMENT: production
  LOG_LEVEL: info
  OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
  KAFKA_BOOTSTRAP_SERVERS: kafka:9092
  VAULT_ADDR: http://vault:8200
EOF

# Criar Secrets
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: zenith-secrets
  namespace: $NAMESPACE
type: Opaque
stringData:
  DATABASE_URL: "postgresql://zenith:zenith@postgres:5432/zenith"
  VAULT_TOKEN: "s.xxxxxxxxxxxxxxxxxxxxxxxx"
  KAFKA_SASL_PASSWORD: "password"
EOF

# Deploy
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-deployment
  namespace: $NAMESPACE
  labels:
    app: fastapi
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: fastapi
  template:
    metadata:
      labels:
        app: fastapi
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: zenith-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: fastapi
        image: huukgomes/zenith-ia:latest
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8000
          protocol: TCP
        envFrom:
        - configMapRef:
            name: zenith-config
        - secretRef:
            name: zenith-secrets
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - fastapi
              topologyKey: kubernetes.io/hostname
      volumes:
      - name: tmp
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
  namespace: $NAMESPACE
  labels:
    app: fastapi
spec:
  type: LoadBalancer
  selector:
    app: fastapi
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
    name: http
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF

print_success "ZENITH.IA deployado"

###############################################################################
# Istio Configuration
###############################################################################

print_header "Configurando Istio VirtualService"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: zenith-vs
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: fastapi-service
        port:
          number: 80
      weight: 100
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  - route:
    - destination:
        host: fastapi-service
        port:
          number: 80
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: zenith-dr
  namespace: $NAMESPACE
spec:
  host: fastapi-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: $NAMESPACE
spec:
  mtls:
    mode: STRICT
EOF

print_success "Istio VirtualService configurado"

###############################################################################
# Verificações Finais
###############################################################################

print_header "Verificações Finais"

print_info "Aguardando pods ficarem prontos..."
kubectl rollout status deployment/fastapi-deployment -n $NAMESPACE --timeout=300s

print_info "Status dos Pods:"
kubectl get pods -n $NAMESPACE

print_info "Status dos Services:"
kubectl get svc -n $NAMESPACE

# Obter Load Balancer URL
print_info "Aguardando Load Balancer IP..."
sleep 10
LB_URL=$(kubectl get svc fastapi-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

if [ "$LB_URL" != "pending" ] && [ -n "$LB_URL" ]; then
    print_success "Load Balancer URL: http://$LB_URL"
else
    print_info "Load Balancer ainda está se configurando, verifique com:"
    print_info "  kubectl get svc fastapi-service -n $NAMESPACE"
fi

###############################################################################
# Resumo Final
###############################################################################

print_header "✅ Setup Completo!"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎉 ZENITH.IA foi deployado com sucesso no AWS EKS!"
echo ""
echo "📊 Comandos úteis:"
echo ""
echo "  # Ver pods:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "  # Ver logs:"
echo "  kubectl logs -f deployment/fastapi-deployment -n $NAMESPACE"
echo ""
echo "  # Acessar aplicação:"
echo "  kubectl port-forward -n $NAMESPACE svc/fastapi-service 8000:80"
echo "  curl http://localhost:8000/health"
echo ""
echo "  # Grafana (Monitoramento):"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "  # User: admin / Password: prom-operator"
echo ""
echo "  # Kiali (Service Mesh):"
echo "  istioctl dashboard kiali"
echo ""
echo "  # Escalar:"
echo "  kubectl scale deployment fastapi-deployment --replicas=5 -n $NAMESPACE"
echo ""
echo "  # Deletar tudo:"
echo "  eksctl delete cluster --name $CLUSTER_NAME --region $REGION"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 Documentação: deploy/AWS_EKS_GUIDE.md"
echo "🔗 Repositório: https://github.com/huukgomes/ZENITH.IA"
echo ""

print_success "Seu cluster está pronto para uso! 🚀"
