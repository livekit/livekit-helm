# 🚀 Инструкция по развертыванию LiveKit в Kubernetes

## Содержание

1. [Быстрый старт](#быстрый-старт)
2. [Требования](#требования)
3. [Установка](#установка)
4. [Тестирование](#тестирование)
5. [Решение проблем](#решение-проблем)

---

## Быстрый старт

### Автоматическая установка (1 команда):

```bash
./install.sh
```

Скрипт автоматически:

- Установит nginx-ingress controller
- Сгенерирует API ключи
- Установит LiveKit с Ingress
- Настроит /etc/hosts для доступа по http://livekit.local
- Сохранит ключи в `livekit-keys.txt`

После установки LiveKit доступен по адресу: **http://livekit.local**

### Тестирование:

```bash
# Проверка
curl http://livekit.local/

# Настройка окружения
export LIVEKIT_URL=http://livekit.local
export LIVEKIT_API_KEY=$(grep API_KEY livekit-keys.txt | awk '{print $2}')
export LIVEKIT_API_SECRET=$(grep API_SECRET livekit-keys.txt | awk '{print $2}')


# Установка CLI (если не установлен)
brew install livekit

# Создание комнаты
livekit-cli create-room --name test-room

# Генерация токена
livekit-cli create-token --room test-room --identity user1
```

---

## Требования

### Обязательно:

- **Kubernetes кластер** (1.19+)
    - Локальный: Minikube, Kind, Docker Desktop
    - Облачный: GKE, EKS, AKS
- **kubectl** (настроен для работы с кластером)
- **Helm 3**

### Опционально:

- **livekit-cli** для тестирования (`brew install livekit`)
- **Redis** для multi-node режима (при replicaCount > 1)

### Порты:

- **7880** - HTTP/WebSocket API
- **7881** - RTC TCP
- **50000-60000** - RTC UDP (медиа трафик)

---

## Установка

### Автоматическая установка (рекомендуется)

```bash
./install.sh
```

### Ручная установка

```bash
# 1. Сгенерировать API ключи
API_KEY=$(openssl rand -hex 16)
API_SECRET=$(openssl rand -base64 32)
echo "API_KEY: $API_KEY"
echo "API_SECRET: $API_SECRET"

# 2. Отредактировать values-minimal.yaml
# Замените devkey на ваши ключи в секции livekit.keys

# 3. Создать namespace
kubectl create namespace livekit

# 4. Добавить helm репозиторий
helm repo add livekit https://helm.livekit.io
helm repo update

# 5. Установить
helm install livekit-test livekit/livekit-server \
  --namespace livekit \
  --values values-minimal.yaml

# 6. Проверить статус
kubectl get pods -n livekit
```

### Проверка установки:

```bash
# Статус pod'ов
kubectl get pods -n livekit

# Логи
kubectl logs -n livekit -l app.kubernetes.io/name=livekit-server

# Сервисы
kubectl get svc -n livekit
```

---

## Настройка Ingress

### Преимущества использования Ingress:

- ✅ Прямой HTTP доступ к LiveKit
- ✅ Доступ по домену (http://livekit.local)
- ✅ Встроенная поддержка WebSocket
- ✅ Готов к production (добавьте TLS сертификаты)

### Автоматическая настройка:

```bash
./install.sh
```

Скрипт:

1. Установит nginx-ingress controller (если не установлен)
2. Настроит LiveKit с Ingress
3. Добавит `livekit.local` в /etc/hosts
4. Проверит доступность

После запуска LiveKit доступен по: **http://livekit.local**

### Использование:

```bash
# Все команды работают с http://livekit.local
export LIVEKIT_URL=http://livekit.local
export LIVEKIT_API_KEY=your_key
export LIVEKIT_API_SECRET=your_secret

livekit-cli list-rooms
livekit-cli create-room --name test-room
```

### Добавление TLS (HTTPS):

Для production создайте values файл с TLS настройками:

```yaml
loadBalancer:
  type: nginx
  tls:
    - hosts:
        - livekit.yourdomain.com
      secretName: livekit-tls-secret
```

Затем обновите установку:

```bash
helm upgrade livekit-test livekit/livekit-server \
  --namespace livekit \
  --values your-production-values.yaml
```

---

## Тестирование

### 1. Проверка API

```bash
curl http://livekit.local/
# Должен вернуть HTML страницу LiveKit
```

### 2. Работа с LiveKit CLI

```bash
# Установка CLI
brew install livekit

# Настройка окружения
export LIVEKIT_URL=http://livekit.local
export LIVEKIT_API_KEY=$(grep API_KEY livekit-keys.txt | awk '{print $2}')
export LIVEKIT_API_SECRET=$(grep API_SECRET livekit-keys.txt | awk '{print $2}')

# Список комнат
livekit-cli list-rooms

# Создание комнаты
livekit-cli create-room --name test-room

# Генерация токена для подключения
livekit-cli create-token \
  --room test-room \
  --identity user1 \
  --valid-for 24h
```

### 3. Тестирование в браузере

1. Откройте https://example.livekit.io/
2. Выберите "Custom" для LiveKit URL
3. Введите `ws://livekit.local`
4. Вставьте сгенерированный токен
5. Присоединитесь к комнате

---

## Решение проблем

### ❌ Ошибка: "connection refused" или сайт не открывается

**Причины:**

1. Ingress не применился
2. Запись в /etc/hosts отсутствует
3. Pod не запущен

**Решение:**

```bash
# Проверьте что pod запущен
kubectl get pods -n livekit

# Проверьте Ingress
kubectl get ingress -n livekit

# Проверьте /etc/hosts
grep livekit.local /etc/hosts

# Проверьте подключение
curl http://livekit.local/
```

### ❌ Ошибка: "unauthorized"

**Причина:** Неправильные API ключи.

**Решение:**

```bash
# Проверьте ключи в файле
cat livekit-keys.txt

# Убедитесь что используете правильные ключи
echo $LIVEKIT_API_KEY
echo $LIVEKIT_API_SECRET
```

### ❌ Pod не запускается

```bash
# Описание pod'а
kubectl describe pod -n livekit -l app.kubernetes.io/name=livekit-server

# Логи
kubectl logs -n livekit -l app.kubernetes.io/name=livekit-server

# События
kubectl get events -n livekit --sort-by='.lastTimestamp'
```

### 🔄 Полная переустановка

```bash
# Удалить LiveKit
helm uninstall livekit-test -n livekit

# Удалить namespace
kubectl delete namespace livekit

# Переустановить
./install.sh
```

---

## Полезные команды

### Управление

```bash
# Обновить конфигурацию (создайте свой values файл)
helm upgrade livekit-test livekit/livekit-server \
  --namespace livekit \
  --values your-values.yaml

# Перезапустить pod'ы
kubectl rollout restart deployment -n livekit livekit-test-livekit-server

# Масштабировать
kubectl scale deployment -n livekit livekit-test-livekit-server --replicas=2
```

### Мониторинг

```bash
# Статус
kubectl get all -n livekit

# Логи в реальном времени
kubectl logs -n livekit -l app.kubernetes.io/name=livekit-server -f

# Логи последних N строк
kubectl logs -n livekit -l app.kubernetes.io/name=livekit-server --tail=50

# Использование ресурсов
kubectl top pods -n livekit
```

### Очистка

```bash
# Удалить релиз
helm uninstall livekit-test -n livekit

# Удалить namespace
kubectl delete namespace livekit

# Удалить сохраненные ключи
rm -f livekit-keys.txt
```

---

## Конфигурация

### Базовая конфигурация

Скрипт `install.sh` автоматически создает конфигурацию с настройками:

- 1 реплика
- Ingress с nginx
- Без Redis
- Без TURN сервера

### Для production

Создайте файл `values-production.yaml` с настройками:

```yaml
replicaCount: 3  # Несколько реплик

livekit:
  rtc:
    use_external_ip: true  # Для облачных кластеров

  redis:
    address: redis-master.livekit.svc.cluster.local:6379  # Обязательно для multi-node

  turn:
    enabled: true  # Для работы через NAT
    domain: turn.yourdomain.com
    tls_port: 3478

  keys:
    prodkey: "ваш-безопасный-секрет"

loadBalancer:
  type: alb  # или gke, nginx для внешнего доступа

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10

resources:
  limits:
    cpu: 6000m
    memory: 2048Mi
  requests:
    cpu: 4000m
    memory: 1024Mi
```

---

## Архитектура

```
┌─────────────────┐
│   Клиенты       │ (Web, Mobile, Desktop)
└────────┬────────┘
         │ WebSocket + WebRTC
         ▼
┌─────────────────┐
│ LoadBalancer/   │ (опционально для production)
│   Ingress       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ LiveKit Server  │ ◄──► Redis (для multi-node)
│   Pods          │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│  TURN Server    │ (опционально для NAT)
└─────────────────┘
```

### Особенности:

- **podHostNetwork: true** - Pod использует host network
- **Один pod на ноду** - Из-за диапазона портов
- **Redis для масштабирования** - Обязателен при replicaCount > 1
- **TURN для NAT** - Необходим если клиенты за firewall

---

## Доступные файлы

- **install.sh** - 🌐 Скрипт автоматической установки LiveKit
- **GUIDE.md** - 📘 Полная документация
- **livekit-keys.txt** - 🔑 API ключи (создается после установки)

---

## Ресурсы

- [Официальная документация LiveKit](https://docs.livekit.io/)
- [Kubernetes Deployment Guide](https://docs.livekit.io/deploy/kubernetes/)
- [GitHub - LiveKit](https://github.com/livekit/livekit)
- [Примеры приложений](https://github.com/livekit/livekit-examples)
- [Web Example для тестирования](https://example.livekit.io/)

---

## Чеклист тестирования

- [ ] Установлен Kubernetes кластер
- [ ] Установлены kubectl и helm
- [ ] Запущен `./install.sh`
- [ ] Pod в статусе Running
- [ ] Ключи сохранены в `livekit-keys.txt`
- [ ] API отвечает (`curl http://livekit.local/`)
- [ ] Установлен livekit-cli
- [ ] Переменные окружения настроены
- [ ] Создана тестовая комната
- [ ] Сгенерирован токен
- [ ] Протестировано подключение через браузер

---

**Быстрая справка:**

```bash
# Установка
./install.sh

# Тестирование
export LIVEKIT_URL=http://livekit.local
export LIVEKIT_API_KEY=$(grep API_KEY livekit-keys.txt | awk '{print $2}')
export LIVEKIT_API_SECRET=$(grep API_SECRET livekit-keys.txt | awk '{print $2}')
livekit-cli create-room --name test-room
```

