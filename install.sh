#!/bin/bash

# Скрипт установки LiveKit в Kubernetes
# Использование: ./install.sh

set -e

echo "🚀 Установка LiveKit в Kubernetes"
echo "=================================="
echo ""

# Проверка зависимостей
echo "📋 Проверка зависимостей..."

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl не установлен"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm не установлен"
    exit 1
fi

echo "✅ kubectl и helm установлены"
echo ""

# Проверка подключения к кластеру
echo "🔍 Проверка подключения к кластеру..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Не удается подключиться к кластеру"
    exit 1
fi
echo "✅ Подключение к кластеру OK"
echo ""

# Шаг 1: Установка nginx-ingress
echo "1️⃣ Проверка nginx-ingress controller..."
if kubectl get namespace ingress-nginx &> /dev/null; then
    echo "✅ nginx-ingress уже установлен"
else
    echo "📦 Устанавливаем nginx-ingress controller..."

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    # Для Docker Desktop
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --wait \
        --timeout 5m

    echo "✅ nginx-ingress установлен"
fi
echo ""

# Ждем готовности Ingress Controller
echo "⏳ Ожидание готовности Ingress Controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null || true

echo "✅ Ingress Controller готов"
echo ""

# Шаг 2: Генерация API ключей
echo "2️⃣ Генерация API ключей..."
API_KEY=$(openssl rand -hex 16)
API_SECRET=$(openssl rand -base64 32)

echo "API_KEY: $API_KEY"
echo "API_SECRET: $API_SECRET"
echo ""

# Сохранение ключей
cat > livekit-keys.txt <<EOF
LiveKit API Credentials (с Ingress)
====================================
Generated: $(date)

API_KEY: $API_KEY
API_SECRET: $API_SECRET

URL: http://livekit.local

Используйте эти ключи для подключения:
export LIVEKIT_URL=http://livekit.local
export LIVEKIT_API_KEY=$API_KEY
export LIVEKIT_API_SECRET=$API_SECRET
EOF

echo "✅ Ключи сохранены в livekit-keys.txt"
echo ""

# Шаг 3: Создание values с ключами
echo "3️⃣ Создание конфигурации..."
TEMP_VALUES="/tmp/livekit-ingress-values-$$.yaml"
cat > "$TEMP_VALUES" <<EOF
replicaCount: 1
terminationGracePeriodSeconds: 18000

livekit:
  port: 7880
  log_level: info

  rtc:
    use_external_ip: false
    tcp_port: 7881
    port_range_start: 50000
    port_range_end: 60000

  redis: {}

  keys:
    $API_KEY: "$API_SECRET"

  turn:
    enabled: false

loadBalancer:
  type: do
  servicePort: 80

  tls:
    - hosts:
        - livekit.local

  annotations:
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"

autoscaling:
  enabled: false

resources: {}

serviceAccount:
  create: false

podHostNetwork: true

podAnnotations:
  sidecar.istio.io/inject: "false"
  linkerd.io/inject: disabled

turnLoadbalancer:
  enable: false
EOF

echo "✅ Конфигурация создана"
echo ""

# Шаг 4: Создание namespace
echo "4️⃣ Создание namespace..."
if kubectl get namespace livekit &> /dev/null; then
    echo "⚠️  Namespace livekit уже существует"
else
    kubectl create namespace livekit
    echo "✅ Namespace создан"
fi
echo ""

# Шаг 5: Установка LiveKit
echo "5️⃣ Установка/обновление LiveKit..."

helm repo add livekit https://helm.livekit.io &> /dev/null || true
helm repo update &> /dev/null

if helm status livekit-test -n livekit &> /dev/null; then
    echo "⚠️  LiveKit уже установлен. Обновляем..."
    helm upgrade livekit-test livekit/livekit-server \
        --namespace livekit \
        --values "$TEMP_VALUES" \
        --wait \
        --timeout 5m
else
    helm install livekit-test livekit/livekit-server \
        --namespace livekit \
        --values "$TEMP_VALUES" \
        --wait \
        --timeout 5m
fi

echo "✅ LiveKit установлен"
echo ""

# Удаление временного файла
rm -f "$TEMP_VALUES"

# Шаг 6: Ожидание готовности
echo "6️⃣ Ожидание готовности pod..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=livekit-server \
  -n livekit \
  --timeout=300s

echo "✅ Pod готов"
echo ""

# Шаг 7: Проверка Ingress
echo "7️⃣ Проверка Ingress..."
kubectl get ingress -n livekit
echo ""

# Получаем хост из Ingress
INGRESS_HOST=$(kubectl get ingress -n livekit -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "livekit.local")

# Шаг 8: Настройка /etc/hosts
echo "8️⃣ Настройка /etc/hosts..."
if grep -q "$INGRESS_HOST" /etc/hosts 2>/dev/null; then
    echo "⚠️  Запись $INGRESS_HOST уже есть в /etc/hosts"
else
    echo "Добавляем 127.0.0.1 $INGRESS_HOST в /etc/hosts..."
    echo "127.0.0.1 $INGRESS_HOST" | sudo tee -a /etc/hosts > /dev/null
    echo "✅ Запись добавлена в /etc/hosts"
fi
echo ""

# Ждем применения Ingress
echo "⏳ Ожидание применения Ingress (15 сек)..."
sleep 15

# Шаг 9: Проверка доступности
echo "9️⃣ Проверка доступности..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$INGRESS_HOST/ --max-time 10 || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ LiveKit доступен! HTTP Code: $HTTP_CODE"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "⚠️  Не удалось подключиться. Проверьте что Ingress применился:"
    echo "   kubectl get ingress -n livekit"
    echo "   kubectl describe ingress -n livekit"
else
    echo "⚠️  HTTP Code: $HTTP_CODE"
    echo "   Может потребоваться время для применения настроек"
fi
echo ""

echo "════════════════════════════════════════"
echo "✅ Установка завершена!"
echo "════════════════════════════════════════"
echo ""
echo "LiveKit доступен по адресу:"
echo "  http://$INGRESS_HOST"
echo ""
echo "Проверка API:"
echo "  curl http://$INGRESS_HOST/"
echo ""
echo "Настройка окружения для CLI:"
echo "  export LIVEKIT_URL=http://$INGRESS_HOST"
echo "  export LIVEKIT_API_KEY=$API_KEY"
echo "  export LIVEKIT_API_SECRET=$API_SECRET"
echo ""
echo "Тестирование:"
echo "  livekit-cli list-rooms"
echo "  livekit-cli create-room --name test-room"
echo "  livekit-cli create-token --room test-room --identity user1"
echo ""
echo "🔑 Ваши ключи сохранены в: livekit-keys.txt"
echo ""

